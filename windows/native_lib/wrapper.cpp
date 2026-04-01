#include "libraw/libraw.h"
#include <cstring>
#include <cstdlib>
#include <vector>

// Cross-platform export macro
#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

extern "C" {

    struct ThumbnailResult {
        uint8_t* data;
        int size;
        int width;
        int height;
        int format; // 0: JPEG, 1: RGB Bitmap
    };

    struct ImageResult {
        uint8_t* data; // RGB data
        int size;
        int width;
        int height;
    };

    // Helper function to free memory
    EXPORT void free_buffer(uint8_t* buffer) {
        if (buffer) {
            free(buffer);
        }
    }

    // Despite the ABI name, get_thumbnail semantically returns the RAW fast
    // preview layer.
    EXPORT void get_thumbnail(const wchar_t* file_path, ThumbnailResult* out) {
        if (out == nullptr) return;

        *out = {nullptr, 0, 0, 0, 0};

        if (file_path == nullptr) return;

        LibRaw RawProcessor;
        
        if (RawProcessor.open_file(file_path) != LIBRAW_SUCCESS) {
            return;
        }

        // Try to unpack the embedded RAW preview first.
        if (RawProcessor.unpack_thumb() == LIBRAW_SUCCESS) {
            int errc = 0;
            libraw_processed_image_t *thumb = RawProcessor.dcraw_make_mem_thumb(&errc);
            
            if (thumb) {
                // Copy data
                out->size = thumb->data_size;
                out->data = (uint8_t*)malloc(out->size);
                if (out->data) {
                    memcpy(out->data, thumb->data, out->size);
                }
                
                // Map LibRaw types to our format
                if (thumb->type == LIBRAW_IMAGE_JPEG) {
                    out->format = 0; // JPEG
                } else if (thumb->type == LIBRAW_IMAGE_BITMAP) {
                    out->format = 1; // RGB Bitmap
                    out->width = thumb->width;
                    out->height = thumb->height;
                }
                
                LibRaw::dcraw_clear_mem(thumb);
                RawProcessor.recycle();
                return;
            }
        }
        
        // Fallback: generate a RAW fast preview from decoded RAW data.
        RawProcessor.imgdata.params.use_camera_wb = 1;
        RawProcessor.imgdata.params.half_size = 1;
        RawProcessor.imgdata.params.output_bps = 8;
        
        if (RawProcessor.unpack() == LIBRAW_SUCCESS) {
            if (RawProcessor.dcraw_process() == LIBRAW_SUCCESS) {
                libraw_processed_image_t *image = RawProcessor.dcraw_make_mem_image();
                
                if (image) {
                    out->format = 1;
                    out->width = image->width;
                    out->height = image->height;
                    out->size = image->data_size;
                    out->data = (uint8_t*)malloc(out->size);
                    
                    if (out->data) {
                        uint8_t* src = image->data;
                        uint8_t* dst = out->data;
                        int total_pixels = out->width * out->height;
                        
                        for (int i = 0; i < total_pixels; ++i) {
                            dst[i * 3 + 0] = src[i * 3 + 2]; // B
                            dst[i * 3 + 1] = src[i * 3 + 1]; // G
                            dst[i * 3 + 2] = src[i * 3 + 0]; // R
                        }
                    }
                    LibRaw::dcraw_clear_mem(image);
                }
            }
        }

        RawProcessor.recycle();
    }

    // Despite the ABI name, get_preview semantically returns the decoded RAW
    // layer.
    EXPORT void get_preview(const wchar_t* file_path, int half_size,
                            ImageResult* out) {
        if (out == nullptr) return;

        *out = {nullptr, 0, 0, 0};

        if (file_path == nullptr) return;

        LibRaw RawProcessor;

        RawProcessor.imgdata.params.use_camera_wb = 1;
        RawProcessor.imgdata.params.half_size = half_size;
        RawProcessor.imgdata.params.output_bps = 8;
        RawProcessor.imgdata.params.output_color = 1;

        if (RawProcessor.open_file(file_path) != LIBRAW_SUCCESS) {
            return;
        }

        if (RawProcessor.unpack() != LIBRAW_SUCCESS) {
            RawProcessor.recycle();
            return;
        }
        
        if (RawProcessor.dcraw_process() != LIBRAW_SUCCESS) {
            RawProcessor.recycle();
            return;
        }

        libraw_processed_image_t *image = RawProcessor.dcraw_make_mem_image();
        
        if (image) {
            out->width = image->width;
            out->height = image->height;
            out->size = image->data_size;
            out->data = (uint8_t*)malloc(out->size);
            if (out->data) {
                uint8_t* src = image->data;
                uint8_t* dst = out->data;
                int total_pixels = out->width * out->height;
                
                for (int i = 0; i < total_pixels; ++i) {
                    dst[i * 3 + 0] = src[i * 3 + 2]; // B
                    dst[i * 3 + 1] = src[i * 3 + 1]; // G
                    dst[i * 3 + 2] = src[i * 3 + 0]; // R
                }
            }
            LibRaw::dcraw_clear_mem(image);
        }

        RawProcessor.recycle();
    }
}
