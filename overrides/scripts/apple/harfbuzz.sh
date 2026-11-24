#!/bin/bash
# CamTape override of ffmpeg-kit's scripts/apple/harfbuzz.sh.
#
# Why: HarfBuzz 11.x no longer ships autotools (no autogen.sh / configure.ac),
# so the upstream script cannot build it. This builds the same HarfBuzz
# 11.3.3 source with its CMake build, as a static library with FreeType,
# and writes the harfbuzz.pc that ffmpeg.sh reads.
#
# Only the HarfBuzz library is built (no utilities, no subset, no tests).
# CoreText, GLib, ICU and Graphite are off: FFmpeg's drawtext only needs
# HarfBuzz shaping on top of FreeType.

mkdir -p "${BUILD_DIR}" || return 1
cd "${BUILD_DIR}" || return 1

FT_PREFIX="${LIB_INSTALL_BASE}/freetype"
PNG_PREFIX="${LIB_INSTALL_BASE}/libpng"

cmake -Wno-dev \
  -DCMAKE_VERBOSE_MAKEFILE=0 \
  -DCMAKE_C_FLAGS="${CFLAGS}" \
  -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_SYSROOT="${SDK_PATH}" \
  -DCMAKE_FIND_ROOT_PATH="${SDK_PATH};${FT_PREFIX};${PNG_PREFIX}" \
  -DCMAKE_OSX_SYSROOT="$(get_sdk_name)" \
  -DCMAKE_OSX_ARCHITECTURES="$(get_cmake_osx_architectures)" \
  -DCMAKE_SYSTEM_NAME="${CMAKE_SYSTEM_NAME}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${LIB_INSTALL_PREFIX}" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_LINKER="$LD" \
  -DCMAKE_AR="$(xcrun --sdk $(get_sdk_name) -f ar)" \
  -DCMAKE_SYSTEM_PROCESSOR="$(get_target_cpu)" \
  -DBUILD_SHARED_LIBS=OFF \
  -DHB_HAVE_FREETYPE=ON \
  -DFREETYPE_INCLUDE_DIRS="${FT_PREFIX}/include/freetype2" \
  -DFREETYPE_INCLUDE_DIR_ft2build="${FT_PREFIX}/include/freetype2" \
  -DFREETYPE_INCLUDE_DIR_freetype2="${FT_PREFIX}/include/freetype2" \
  -DFREETYPE_LIBRARY="${FT_PREFIX}/lib/libfreetype.a" \
  -DCMAKE_REQUIRED_LIBRARIES="${FT_PREFIX}/lib/libfreetype.a;${PNG_PREFIX}/lib/libpng16.a;-lz" \
  -DHB_HAVE_CORETEXT=OFF \
  -DHB_HAVE_GLIB=OFF \
  -DHB_HAVE_GOBJECT=OFF \
  -DHB_HAVE_ICU=OFF \
  -DHB_HAVE_GRAPHITE2=OFF \
  -DHB_HAVE_INTROSPECTION=OFF \
  -DHB_BUILD_UTILS=OFF \
  -DHB_BUILD_SUBSET=OFF \
  -DHB_BUILD_TESTS=OFF \
  "${BASEDIR}"/src/"${LIB_NAME}" || return 1

make -j$(get_cpu_count) harfbuzz || return 1

make install/fast 1>>"${BASEDIR}"/build.log 2>&1 || make install || return 1

# FFmpeg's configure finds HarfBuzz through pkg-config. HarfBuzz is C++,
# so the static library needs libc++ at the final link.
cat >"${INSTALL_PKG_CONFIG_DIR}/harfbuzz.pc" <<PC
prefix=${LIB_INSTALL_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: harfbuzz
Description: HarfBuzz text shaping library
Version: 11.3.3
Requires.private: freetype2
Libs: -L\${libdir} -lharfbuzz -lc++
Cflags: -I\${includedir}/harfbuzz
PC

rm -f "${LIB_INSTALL_PREFIX}"/lib/*.la
