#!/usr/bin/env bash
# Build Node.js for Android (Termux), in a Node.js source tree that already has
# dist/all and dist/android applied (releases/dist-dirs-for.sh android-*).
#
#   releases/build-android.sh <android-ndk-dir> <platform>
#
#   platform       Android ABI      Node --dest-cpu   NDK clang target
#   android-arm64  arm64-v8a        arm64             aarch64-linux-android
#   android-armv7  armeabi-v7a      arm               armv7a-linux-androideabi
#   android-x64    x86_64           x64               x86_64-linux-android
#   android-x86    x86              ia32              i686-linux-android
#
# WHY THIS EXISTS. Termux packages Node.js for all four Android CPUs, but it is
# behind upstream (26.4.0 when 26.11.1 was current) and it is linked to
# Termux's own shared OpenSSL, ICU, SQLite, c-ares, zlib and libffi - so its
# binary cannot be carried inside anything else. This builds the same Node.js
# release WeKan ships everywhere else, with every dependency bundled: the
# result needs only Android's own libc (bionic), so it can be embedded in a
# single-file WeKan for Termux.
#
# HOW. Node's own android-configure, by hand, so the HOST half is ours: V8's
# build tools (mksnapshot, torque, ...) run on the build machine, so they are
# built with the host GCC, and for a 32-bit target (armv7, x86) as 32-bit host
# programs (-m32) - V8 needs the host pointer width to match the target's, the
# same reason Termux and the armhf build in release-all.yml use a 32-bit host.
# The Android API level is 24 (Android 7.0), Node's and Termux's minimum.
#
# The source patches (dist/android) are Termux's nodejs patches, adapted:
# Termux paths (/tmp -> $PREFIX/tmp, /system/bin/sh -> $PREFIX/bin/sh), the
# getaddrinfo shim for localhost on IPv6, and the gyp conditions that let V8
# and libuv build for OS=android. __TERMUX__ is defined, as Termux's own
# toolchain does, because those patches key on it.
set -euo pipefail

ndk="${1:?usage: build-android.sh <android-ndk-dir> <platform>}"
# Absolute: make runs the compilers from out/, where a relative path is wrong.
ndk="$(cd "$ndk" && pwd)"
platform="${2:?usage: build-android.sh <android-ndk-dir> <platform>}"
api="${ANDROID_API_LEVEL:-24}"

case "$platform" in
  android-arm64) cpu=arm64 gyp_arch=arm64 triple=aarch64-linux-android bits=64 ;;
  android-armv7) cpu=arm   gyp_arch=arm   triple=armv7a-linux-androideabi bits=32 ;;
  android-x64)   cpu=x64   gyp_arch=x64   triple=x86_64-linux-android bits=64 ;;
  android-x86)   cpu=ia32  gyp_arch=x86   triple=i686-linux-android bits=32 ;;
  *) echo "build-android.sh: unknown platform $platform" >&2; exit 2 ;;
esac

toolchain="$ndk/toolchains/llvm/prebuilt/linux-x86_64"
[ -x "$toolchain/bin/${triple}${api}-clang" ] || {
  echo "build-android.sh: no ${triple}${api}-clang in $toolchain - is $ndk an Android NDK?" >&2
  exit 1
}

export CC="$toolchain/bin/${triple}${api}-clang"
export CXX="$toolchain/bin/${triple}${api}-clang++"
export LINK="$CXX"
export AR="$toolchain/bin/llvm-ar"
export RANLIB="$toolchain/bin/llvm-ranlib"
# __TERMUX__: the dist/android patches select Termux's paths with it.
# aligned_alloc only exists from API 28; Termux maps it the same way.
export CFLAGS="-D__TERMUX__ -Daligned_alloc=memalign ${CFLAGS:-}"
export CXXFLAGS="-D__TERMUX__ -Daligned_alloc=memalign ${CXXFLAGS:-}"
# The C++ library goes INTO the binary. The NDK's clang++ links
# libc++_shared.so by default, and Termux has it only once `pkg install
# libc++` has run - the smoke test's clean Termux image does not, and stopped
# with "library libc++_shared.so not found". A binary that needs only
# Android's own libc is the point of building these.
export LDFLAGS="-static-libstdc++ ${LDFLAGS:-}"

m32=""
[ "$bits" = 32 ] && m32=" -m32"
# A 32-bit x86 host build must also say SSE2: gcc -m32 targets i686 without
# it, and V8 refuses ia32 without SSE2 ("Did not detect required SSE2 support
# on ia32/x64", swiss-hash-table-helpers.h). The target needs nothing - the
# Android x86 ABI guarantees SSSE3, and the NDK's clang assumes it.
[ "$platform" = android-x86 ] && m32="$m32 -msse2 -mfpmath=sse"
export CC_host="gcc$m32" CXX_host="g++$m32" LINK_host="g++$m32" AR_host=ar

export GYP_DEFINES="target_arch=$gyp_arch v8_target_arch=$gyp_arch android_target_arch=$gyp_arch host_os=linux OS=android android_ndk_path=$ndk"

# Temporal off, as Termux builds it: Node's Rust crates (Temporal, ICU4X) are
# one library for both halves of a cross build (deps/crates/crates.gyp sets a
# Rust target only for Windows and macOS), so on Linux the build machine's
# x86_64 crates were linked into V8's 32-bit host tools ("i386:x86-64
# architecture of input file libnode_crates.a ... is incompatible with i386
# output", android-armv7) and would be into the Android binary next. Without
# cargo in the picture, every Android CPU builds; Temporal is the only thing
# missing, and WeKan does not use it.
./configure --dest-cpu="$cpu" --dest-os=android --cross-compiling \
  --openssl-no-asm --without-npm --v8-disable-temporal-support
make -j"${JOBS:-$(nproc)}"
"$toolchain/bin/llvm-strip" out/Release/node
file out/Release/node 2>/dev/null || true
