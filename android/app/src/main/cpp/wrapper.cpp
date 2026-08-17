#include "libraw/libraw.h"

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <android/log.h>

#define LOG_TAG "NativeLib"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#define EXPORT __attribute__((visibility("default"))) __attribute__((used))

extern "C" {

    // `format` values:
    //   0: encoded image bytes (embedded JPEG preview, passed through as-is)
    //   2: RGBA8888 pixels, `stride` bytes per row
    struct ThumbnailResult {
        uint8_t* data;
        int size;
        int width;
        int height;
        int format;
        int stride;
    };

    struct ImageResult {
        uint8_t* data; // RGBA8888 pixels
        int size;
        int width;
        int height;
        int stride;
    };

}  // extern "C"

namespace {

ThumbnailResult empty_thumbnail() { return {nullptr, 0, 0, 0, 0, 0}; }

ImageResult empty_image() { return {nullptr, 0, 0, 0, 0}; }

// LibRaw calls this between processing stages. Returning non-zero aborts the
// decode with LIBRAW_CANCELLED_BY_CALLBACK, which is what makes cancelling a
// queued preview actually stop burning CPU.
int cancel_progress_callback(void* data, enum LibRaw_progress, int, int) {
  const auto* flag = static_cast<const std::atomic<bool>*>(data);
  return (flag != nullptr && flag->load(std::memory_order_relaxed)) ? 1 : 0;
}

void attach_cancel_token(LibRaw& raw_processor, void* cancel_token) {
  if (cancel_token != nullptr) {
    raw_processor.set_progress_handler(cancel_progress_callback, cancel_token);
  }
}

bool is_cancelled(void* cancel_token) {
  const auto* flag = static_cast<const std::atomic<bool>*>(cancel_token);
  return flag != nullptr && flag->load(std::memory_order_relaxed);
}

// Expand LibRaw's packed RGB output into RGBA8888, which is what
// ui.ImageDescriptor.raw() consumes with zero further decoding.
void copy_rgb_to_rgba(uint8_t* destination,
                      const uint8_t* source,
                      int width,
                      int height) {
  const size_t total_pixels =
      static_cast<size_t>(width) * static_cast<size_t>(height);
  for (size_t i = 0; i < total_pixels; ++i) {
    destination[i * 4 + 0] = source[i * 3 + 0];
    destination[i * 4 + 1] = source[i * 3 + 1];
    destination[i * 4 + 2] = source[i * 3 + 2];
    destination[i * 4 + 3] = 255;
  }
}

// Expand LibRaw's 3-channel or 1-channel 8-bit output into RGBA8888.
// Returns false when the layout is not something we can convert.
bool fill_rgba_from_processed(ImageResult& result,
                              const libraw_processed_image_t* image) {
  if (image->bits != 8 || (image->colors != 3 && image->colors != 1)) {
    return false;
  }

  const int width = image->width;
  const int height = image->height;
  const size_t total_pixels =
      static_cast<size_t>(width) * static_cast<size_t>(height);
  const size_t rgba_size = total_pixels * 4;

  auto* rgba = static_cast<uint8_t*>(malloc(rgba_size));
  if (rgba == nullptr) {
    return false;
  }

  if (image->colors == 3) {
    copy_rgb_to_rgba(rgba, image->data, width, height);
  } else {
    for (size_t i = 0; i < total_pixels; ++i) {
      const uint8_t gray = image->data[i];
      rgba[i * 4 + 0] = gray;
      rgba[i * 4 + 1] = gray;
      rgba[i * 4 + 2] = gray;
      rgba[i * 4 + 3] = 255;
    }
  }

  result.data = rgba;
  result.size = static_cast<int>(rgba_size);
  result.width = width;
  result.height = height;
  result.stride = width * 4;
  return true;
}

}  // namespace

extern "C" {

    // Helper function to free memory
    EXPORT void free_buffer(uint8_t* buffer) {
        if (buffer) {
            free(buffer);
        }
    }

    // Cancellation tokens are owned by the caller: create one per request, pass
    // it into get_thumbnail()/get_preview(), set it from another thread to abort,
    // then destroy it once the call has returned.
    EXPORT void* create_cancel_token() {
        return new std::atomic<bool>(false);
    }

    EXPORT void cancel_token_set(void* token) {
        if (token != nullptr) {
            static_cast<std::atomic<bool>*>(token)->store(
                true, std::memory_order_relaxed);
        }
    }

    EXPORT void destroy_cancel_token(void* token) {
        delete static_cast<std::atomic<bool>*>(token);
    }

    // Build the RAW fast preview layer.
    //
    // Prefer the embedded preview via unpack_thumb(). Encoded JPEG previews are
    // passed straight through because the engine decodes JPEG efficiently
    // already. If the file does not expose one, fall back to a half-size RAW
    // decode so the UI still gets a fast first image.
    ThumbnailResult process_thumbnail(LibRaw& RawProcessor, void* cancel_token) {
        ThumbnailResult result = empty_thumbnail();

        if (RawProcessor.unpack_thumb() == LIBRAW_SUCCESS) {
            int errc = 0;
            libraw_processed_image_t *thumb = RawProcessor.dcraw_make_mem_thumb(&errc);

            if (thumb != nullptr) {
                if (thumb->type == LIBRAW_IMAGE_JPEG) {
                    result.size = static_cast<int>(thumb->data_size);
                    result.data = static_cast<uint8_t*>(malloc(thumb->data_size));
                    if (result.data != nullptr) {
                        memcpy(result.data, thumb->data, thumb->data_size);
                        result.format = 0;
                    } else {
                        result.size = 0;
                    }
                    LibRaw::dcraw_clear_mem(thumb);
                    return result;
                }

                if (thumb->type == LIBRAW_IMAGE_BITMAP) {
                    ImageResult bitmap = empty_image();
                    if (fill_rgba_from_processed(bitmap, thumb)) {
                        result.data = bitmap.data;
                        result.size = bitmap.size;
                        result.width = bitmap.width;
                        result.height = bitmap.height;
                        result.stride = bitmap.stride;
                        result.format = 2;
                        LibRaw::dcraw_clear_mem(thumb);
                        return result;
                    }
                }

                LibRaw::dcraw_clear_mem(thumb);
            }
        } else {
            LOGD("unpack_thumb failed");
        }

        if (is_cancelled(cancel_token)) {
            return result;
        }

        // Fallback: generate a RAW fast preview from decoded RAW data.
        RawProcessor.imgdata.params.use_camera_wb = 1;
        RawProcessor.imgdata.params.half_size = 1; // Half size for speed
        RawProcessor.imgdata.params.output_bps = 8;
        RawProcessor.imgdata.params.output_color = 1;

        if (RawProcessor.unpack() == LIBRAW_SUCCESS) {
            if (RawProcessor.dcraw_process() == LIBRAW_SUCCESS) {
                libraw_processed_image_t *image = RawProcessor.dcraw_make_mem_image();

                if (image != nullptr) {
                    ImageResult bitmap = empty_image();
                    if (fill_rgba_from_processed(bitmap, image)) {
                        result.data = bitmap.data;
                        result.size = bitmap.size;
                        result.width = bitmap.width;
                        result.height = bitmap.height;
                        result.stride = bitmap.stride;
                        result.format = 2;
                    }
                    LibRaw::dcraw_clear_mem(image);
                }
            } else {
                LOGD("dcraw_process failed");
            }
        } else {
             LOGD("unpack failed");
        }

        return result;
    }

    // Despite the ABI name, get_thumbnail semantically returns the RAW fast
    // preview layer.
    EXPORT void get_thumbnail(const char* file_path, void* cancel_token,
                              ThumbnailResult* out) {
        if (!out) return;

        *out = empty_thumbnail();

        if (!file_path) {
            return;
        }

        LibRaw RawProcessor;
        attach_cancel_token(RawProcessor, cancel_token);

        int ret = RawProcessor.open_file(file_path);
        if (ret != LIBRAW_SUCCESS) {
            LOGE("open_file failed: %d for %s", ret, file_path);
            return;
        }

        *out = process_thumbnail(RawProcessor, cancel_token);
        RawProcessor.recycle();
    }

    EXPORT void get_thumbnail_from_buffer(uint8_t* buffer, int size,
                                          void* cancel_token,
                                          ThumbnailResult* out) {
        if (!out) return;

        *out = empty_thumbnail();

        if (!buffer || size <= 0) {
            return;
        }

        LibRaw RawProcessor;
        attach_cancel_token(RawProcessor, cancel_token);

        int ret = RawProcessor.open_buffer(buffer, (size_t)size);
        if (ret != LIBRAW_SUCCESS) {
             LOGE("open_buffer failed: %d", ret);
             return;
        }

        *out = process_thumbnail(RawProcessor, cancel_token);
        RawProcessor.recycle();
    }

    // Build the decoded RAW layer used as the final high-quality image.
    ImageResult process_preview(LibRaw& RawProcessor, int half_size) {
        ImageResult result = empty_image();

        // Configure decoded RAW output. half_size trades quality for speed.
        RawProcessor.imgdata.params.use_camera_wb = 1;
        RawProcessor.imgdata.params.half_size = half_size; // 1: Half size, 0: Full size
        RawProcessor.imgdata.params.output_bps = 8; // 8-bit output
        RawProcessor.imgdata.params.output_color = 1; // sRGB

        if (RawProcessor.unpack() != LIBRAW_SUCCESS) {
            return result;
        }

        // dcraw_process
        if (RawProcessor.dcraw_process() != LIBRAW_SUCCESS) {
            return result;
        }

        // Convert to memory image
        libraw_processed_image_t *image = RawProcessor.dcraw_make_mem_image();

        if (image != nullptr) {
            fill_rgba_from_processed(result, image);
            LibRaw::dcraw_clear_mem(image);
        }

        return result;
    }

    // Despite the ABI name, get_preview semantically returns the decoded RAW
    // layer.
    EXPORT void get_preview(const char* file_path, int half_size,
                            void* cancel_token, ImageResult* out) {
        if (!out) return;

        *out = empty_image();

        if (!file_path) {
            return;
        }

        LibRaw RawProcessor;
        attach_cancel_token(RawProcessor, cancel_token);

        int ret = RawProcessor.open_file(file_path);
        if (ret != LIBRAW_SUCCESS) {
            LOGE("get_preview open_file failed: %d", ret);
            return;
        }

        *out = process_preview(RawProcessor, half_size);
        RawProcessor.recycle();
    }

    EXPORT void get_preview_from_buffer(uint8_t* buffer, int size, int half_size,
                                        void* cancel_token, ImageResult* out) {
        if (!out) return;

        *out = empty_image();

        if (!buffer || size <= 0) {
            return;
        }

        LibRaw RawProcessor;
        attach_cancel_token(RawProcessor, cancel_token);

        int ret = RawProcessor.open_buffer(buffer, (size_t)size);
        if (ret != LIBRAW_SUCCESS) {
            LOGE("get_preview open_buffer failed: %d", ret);
            return;
        }

        *out = process_preview(RawProcessor, half_size);
        RawProcessor.recycle();
    }
}
