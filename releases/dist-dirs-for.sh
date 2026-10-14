#!/usr/bin/env bash
# Print the dist/ subdirectories to apply for a build-matrix platform, most
# general first (one per line). This is the APPLY-MAP - the single place that
# says which patch sets a platform gets:
#
#   all    every platform (the common section)
#   ia32   i386 + win32 + android-x86 (32-bit x86)
#   arm    armhf + armv7         (32-bit ARM that may use NEON)
#   armv6  armv6                 (ARMv6 build configuration)
#   riscv64 riscv64             (RISC-V Maglev link fix)
#   mac    mac-x64 + mac-arm64   (Apple Clang)
#   win32  win32                 (Windows 32-bit only)
#   android android-arm64, -armv7, -x64, -x86 (Android/Termux, NDK)
#   openbsd openbsd-x64, openbsd-arm64 (OpenBSD ports' patches)
#   netbsd  netbsd-x64            (pkgsrc's patches)
#
# s390x takes the common set only: it builds like a native s390x build (its
# real mksnapshot runs under qemu-user, see release-all.yml's cross-qemu mode),
# so it needs no s390x-specific source patches.
#
# A build applies dist/all first, then each family/platform dir its target maps
# to. Keep this in step with the build matrix in release-all.yml and the table in
# dist/README.md.
set -euo pipefail

echo all
case "${1:?usage: dist-dirs-for.sh <platform>}" in
  i386)              echo ia32 ;;
  win32)             echo ia32; echo win32 ;;
  armhf|armv7)       echo arm ;;
  # armv6 is 32-bit ARM but does not take dist/arm. dist/arm is
  # the NEON patch: it puts -mfpu=neon on zlib's SIMD targets. ARMv6 has no NEON
  # - the target is VFPv2 (--with-arm-fpu=vfp) - so that flag would be a compile
  # error rather than a speed-up. zlib.gyp selects scalar code on ARMv6.
  # Its own section fixes the ARM version detected by configure.py.
  armv6)             echo armv6 ;;
  riscv64)           echo riscv64 ;;
  mac-x64|mac-arm64) echo mac ;;
  # android-armv7 is 32-bit ARM too: dist/arm gives zlib its NEON flag and keeps
  # the ARMv8-only CRC32 path off. It touches only zlib.gyp, android only
  # cpu_features.c, so the two never meet in one file.
  android-armv7)     echo arm; echo android ;;
  android-arm64|android-x64) echo android ;;
  # android-x86 is 32-bit x86: it needs dist/ia32's V8, ICU and zlib fixes as
  # i386 and win32 do (its V8 had no ia32 code generator without them).
  android-x86)       echo ia32; echo android ;;
  # The OS packagers' patch sets, adapted to Node 26: OpenBSD ports' lang/node
  # and pkgsrc's lang/nodejs (dist/openbsd, dist/netbsd).
  openbsd-x64)       echo openbsd ;;
  # arm64 also takes dist/bsd-arm64: Node's bundled OpenSSL has no BSD arm64
  # configuration, and is built --openssl-no-asm from linux-aarch64's.
  openbsd-arm64)     echo openbsd; echo bsd-arm64 ;;
  netbsd-x64)        echo netbsd ;;
  # x64, arm64, ppc64le, loong64, s390x, win64, win-arm64 and
  # freebsd-x64 take the common set only.
esac
