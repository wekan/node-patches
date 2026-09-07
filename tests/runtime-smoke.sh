#!/bin/sh
# Run before an artifact is named or uploaded. In cross-qemu mode binfmt and
# QEMU_LD_PREFIX must already point at this target's emulator and cross sysroot.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
: "${1:?usage: runtime-smoke.sh node-binary [platform]}"
"$1" "$script_dir/runtime-smoke.cjs" "${2:-}"
