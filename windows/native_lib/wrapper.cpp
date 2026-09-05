#include "libraw/libraw.h"

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>

// Cross-platform export macro
#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

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

// Extract only the JPEG bytes stored in the RAW container. Unlike the thumbnail
// layer below, this deliberately does not fall back to RAW processing, so a
// null result is the authoritative "this file has no embedded JPEG".
ThumbnailResult extract_embedded_jpeg(LibRaw& RawProcessor) {
    ThumbnailResult result = empty_thumbnail();

    if (RawProcessor.unpack_thumb() != LIBRAW_SUCCESS) {
        return result;
    }

    int errc = 0;
    libraw_processed_image_t* thumb =
        RawProcessor.dcraw_make_mem_thumb(&errc);
    if (thumb == nullptr) {
        return result;
    }

    if (thumb->type == LIBRAW_IMAGE_JPEG && thumb->data_size > 0) {
        result.data = static_cast<uint8_t*>(malloc(thumb->data_size));
        if (result.data != nullptr) {
            memcpy(result.data, thumb->data, thumb->data_size);
            result.size = static_cast<int>(thumb->data_size);
            result.format = 0;
        }
    }

    LibRaw::dcraw_clear_mem(thumb);
    return result;
}

// Expand LibRaw's packed RGB output into RGBA8888, which is what
// ui.ImageDescriptor.raw() consumes with zero further decoding.
void copy_rgb_to_rgba(uint8_t* destination,
                      const uint8_t* source,
                      int width,
                      int height) {
  const size_t total_pixels = static_cast<size_t>(width) * static_cast<size_t>(height);
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
  const size_t total_pixels = static_cast<size_t>(width) * static_cast<size_t>(height);
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

// Build the RAW thumbnail layer: the cheapest image we can produce.
//
// Prefer the embedded preview via unpack_thumb(). Encoded JPEG previews are
// passed straight through because the engine decodes JPEG efficiently already.
// If the file exposes no usable preview, fall back to a half-size RAW decode
// so the UI still gets an image quickly. The payload is therefore not
// necessarily the embedded JPEG — get_embedded_jpeg() is the no-fallback
// path for callers that need that distinction.
ThumbnailResult process_thumbnail(LibRaw& raw_processor, void* cancel_token) {
    ThumbnailResult result = empty_thumbnail();

    if (raw_processor.unpack_thumb() == LIBRAW_SUCCESS) {
        int errc = 0;
        libraw_processed_image_t* thumb = raw_processor.dcraw_make_mem_thumb(&errc);

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
    }

    if (is_cancelled(cancel_token)) {
        return result;
    }

    // Fallback: no usable embedded preview, so decode the RAW at half size.
    raw_processor.imgdata.params.use_camera_wb = 1;
    raw_processor.imgdata.params.half_size = 1;
    raw_processor.imgdata.params.output_bps = 8;
    raw_processor.imgdata.params.output_color = 1;

    if (raw_processor.unpack() == LIBRAW_SUCCESS &&
        raw_processor.dcraw_process() == LIBRAW_SUCCESS) {
        libraw_processed_image_t* image = raw_processor.dcraw_make_mem_image();

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
    }

    return result;
}

// Build the decoded RAW layer used as the final high-quality image.
ImageResult process_preview(LibRaw& raw_processor, int half_size) {
    ImageResult result = empty_image();

    raw_processor.imgdata.params.use_camera_wb = 1;
    raw_processor.imgdata.params.half_size = half_size;
    raw_processor.imgdata.params.output_bps = 8;
    raw_processor.imgdata.params.output_color = 1;

    if (raw_processor.unpack() != LIBRAW_SUCCESS ||
        raw_processor.dcraw_process() != LIBRAW_SUCCESS) {
        return result;
    }

    libraw_processed_image_t* image = raw_processor.dcraw_make_mem_image();
    if (image != nullptr) {
        fill_rgba_from_processed(result, image);
        LibRaw::dcraw_clear_mem(image);
    }

    return result;
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

    // Despite the ABI name, get_thumbnail returns the RAW thumbnail layer,
    // which may be a RAW decode rather than an embedded thumbnail.
    EXPORT void get_thumbnail(const wchar_t* file_path, void* cancel_token,
                              ThumbnailResult* out) {
        if (out == nullptr) return;

        *out = empty_thumbnail();

        if (file_path == nullptr) return;

        LibRaw RawProcessor;
        attach_cancel_token(RawProcessor, cancel_token);

        if (RawProcessor.open_file(file_path) != LIBRAW_SUCCESS) {
            return;
        }

        *out = process_thumbnail(RawProcessor, cancel_token);
        RawProcessor.recycle();
    }

    EXPORT void get_embedded_jpeg(const wchar_t* file_path,
                                  ThumbnailResult* out) {
        if (out == nullptr) return;

        *out = empty_thumbnail();
        if (file_path == nullptr) return;

        LibRaw RawProcessor;
        if (RawProcessor.open_file(file_path) != LIBRAW_SUCCESS) {
            return;
        }

        *out = extract_embedded_jpeg(RawProcessor);
        RawProcessor.recycle();
    }

    // Despite the ABI name, get_preview semantically returns the decoded RAW
    // layer.
    EXPORT void get_preview(const wchar_t* file_path, int half_size,
                            void* cancel_token, ImageResult* out) {
        if (out == nullptr) return;

        *out = empty_image();

        if (file_path == nullptr) return;

        LibRaw RawProcessor;
        attach_cancel_token(RawProcessor, cancel_token);

        if (RawProcessor.open_file(file_path) != LIBRAW_SUCCESS) {
            return;
        }

        *out = process_preview(RawProcessor, half_size);
        RawProcessor.recycle();
    }
}
