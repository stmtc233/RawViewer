cmake_minimum_required(VERSION 3.10)

project(native_lib LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include_directories(libraw)

file(GLOB_RECURSE LIBRAW_SOURCES 
    "libraw/src/libraw_c_api.cpp"
    "libraw/src/libraw_datastream.cpp"
    "libraw/src/decoders/*.cpp"
    "libraw/src/decompressors/*.cpp"
    "libraw/src/demosaic/*.cpp"
    "libraw/src/integration/*.cpp"
    "libraw/src/metadata/*.cpp"
    "libraw/src/postprocessing/*.cpp"
    "libraw/src/preprocessing/*.cpp"
    "libraw/src/tables/*.cpp"
    "libraw/src/utils/*.cpp"
    "libraw/src/write/*.cpp"
    "libraw/src/x3f/*.cpp"
)

list(FILTER LIBRAW_SOURCES EXCLUDE REGEX ".*_ph\\.cpp$")

add_library(native_lib SHARED
    wrapper.cpp
    ${LIBRAW_SOURCES}
)

target_link_libraries(native_lib android log)

# Enable OpenMP so LibRaw's demosaic takes its multi-threaded path.
# -static-openmp links the runtime into libnative_lib.so, so there is no extra
# libomp.so to package or load at runtime.
target_compile_options(native_lib PRIVATE -fopenmp -static-openmp)
target_link_options(native_lib PRIVATE -fopenmp -static-openmp)
