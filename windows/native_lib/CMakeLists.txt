cmake_minimum_required(VERSION 3.10)

project(native_lib LANGUAGES CXX)

# 设置 C++ 标准
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 包含 LibRaw 头文件
include_directories(libraw)

# 收集 LibRaw 源文件
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

# 移除不需要的文件（如果有冲突）
list(FILTER LIBRAW_SOURCES EXCLUDE REGEX ".*_ph\\.cpp$")
# list(REMOVE_ITEM LIBRAW_SOURCES "libraw/src/demosaic/gpr_read_image.cpp")

# 添加库
add_library(native_lib SHARED
    wrapper.cpp
    ${LIBRAW_SOURCES}
)

# Windows 特有设置
if(WIN32)
    target_compile_definitions(native_lib PRIVATE LIBRAW_BUILD_CHECK)
    target_compile_definitions(native_lib PRIVATE LIBRAW_NODLL)
    target_compile_definitions(native_lib PRIVATE _CRT_SECURE_NO_WARNINGS)
    if(MSVC)
        target_compile_options(native_lib PRIVATE /wd4018 /wd4244 /wd4996 /wd4005 /wd4146 /wd4819)
    endif()
    # 或者如果不定义 LIBRAW_NODLL，则需要处理导出符号
endif()

# 启用 OpenMP，让 LibRaw 的 demosaic 走多线程分支。
#
# 必须用 /openmp:llvm 而不是传统的 /openmp：LibRaw 的 dht_demosaic.cpp 用了
# collapse(2)（OpenMP 3.0），传统 /openmp 只支持 2.0，会报 warning C4849 并
# 静默忽略该子句。
#
# 代价是产生 libomp140 运行时依赖，所以下面必须把它复制到输出目录，否则在没装
# Visual Studio 的机器上会因为缺 DLL 起不来。
if(MSVC)
    target_compile_options(native_lib PRIVATE /openmp:llvm)

    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "^([Aa][Rr][Mm]64|aarch64)$")
            set(LIBOMP_NAME "libomp140.aarch64.dll")
        else()
            set(LIBOMP_NAME "libomp140.x86_64.dll")
        endif()
    else()
        set(LIBOMP_NAME "libomp140.i386.dll")
    endif()

    # 在 MSVC 的 redist 目录里找 libomp。VS 把 LLVM 版放在 debug_nonredist/ 下，
    # 但它本身是可随应用分发的 LLVM OpenMP 运行时。
    #
    # VCToolsRedistDir 只在 vcvars 环境里有定义，Flutter 直接调 CMake 时没有，
    # 所以同时从编译器路径推导 redist 目录：
    #   VC/Tools/MSVC/<ver>/bin/... -> VC/Redist/MSVC/*
    set(LIBOMP_SEARCH_GLOBS "")

    if(DEFINED ENV{VCToolsRedistDir})
        file(TO_CMAKE_PATH "$ENV{VCToolsRedistDir}" _vc_redist)
        list(APPEND LIBOMP_SEARCH_GLOBS
            "${_vc_redist}/debug_nonredist/*/Microsoft.*.OpenMP.LLVM/${LIBOMP_NAME}"
            "${_vc_redist}/*/Microsoft.*.OpenMP.LLVM/${LIBOMP_NAME}"
        )
    endif()

    # CMAKE_CXX_COMPILER 形如 .../VC/Tools/MSVC/<ver>/bin/Hostx64/x64/cl.exe
    string(REGEX REPLACE "/VC/Tools/MSVC/.*$" "/VC/Redist/MSVC"
        _vc_redist_root "${CMAKE_CXX_COMPILER}")
    if(NOT _vc_redist_root STREQUAL "${CMAKE_CXX_COMPILER}")
        list(APPEND LIBOMP_SEARCH_GLOBS
            "${_vc_redist_root}/*/debug_nonredist/*/Microsoft.*.OpenMP.LLVM/${LIBOMP_NAME}"
            "${_vc_redist_root}/*/*/Microsoft.*.OpenMP.LLVM/${LIBOMP_NAME}"
        )
    endif()

    file(GLOB LIBOMP_CANDIDATES ${LIBOMP_SEARCH_GLOBS})

    if(LIBOMP_CANDIDATES)
        list(GET LIBOMP_CANDIDATES 0 LIBOMP_DLL)
        message(STATUS "OpenMP runtime: ${LIBOMP_DLL}")
        # 复制到 native_lib 旁边，runner 的 install 步骤会一并打包。
        add_custom_command(TARGET native_lib POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${LIBOMP_DLL}" "$<TARGET_FILE_DIR:native_lib>"
            VERBATIM
        )
        set(NATIVE_LIB_OPENMP_RUNTIME "${LIBOMP_DLL}"
            CACHE FILEPATH "OpenMP runtime DLL to bundle" FORCE)
    else()
        message(WARNING
            "找不到 ${LIBOMP_NAME}，无法启用 OpenMP（否则运行时会缺 DLL）。"
            "回退到单线程 demosaic。")
        # 收回 /openmp:llvm，避免产生一个无法满足的运行时依赖。
        get_target_property(_nl_opts native_lib COMPILE_OPTIONS)
        list(REMOVE_ITEM _nl_opts "/openmp:llvm")
        set_target_properties(native_lib PROPERTIES COMPILE_OPTIONS "${_nl_opts}")
    endif()
endif()
