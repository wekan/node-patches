#!/usr/bin/env bash
# Print the dist/ subdirectories to apply for a build-matrix platform, most
# general first (one per line). This is the APPLY-MAP - the single place that
# says which patch sets a platform gets:
#
#   all    every platform (the common section)
#   ia32   i386 + win32          (32-bit x86)
#   arm    armhf + armv7         (32-bit ARM)
#   s390x  s390x                 (IBM Z, cross under the V8 simulator)
#   mac    mac-x64 + mac-arm64   (Apple Clang)
#   win32  win32                 (Windows 32-bit only)
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
  s390x)             echo s390x ;;
  mac-x64|mac-arm64) echo mac ;;
  # x64, arm64, ppc64le, riscv64, loong64, win64 take the common set only.
esac
