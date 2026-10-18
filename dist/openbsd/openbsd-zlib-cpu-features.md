# openbsd-zlib-cpu-features

Gives the bundled zlib's `cpu_features.c` an OpenBSD arm64 branch.

On arm64 `deps/zlib/zlib.gyp` builds zlib with NEON and the ARMv8 CRC32
code (`arm_fpu=="neon"`), and `deflate.c` and `crc32.c` then call
`cpu_check_features()`. `cpu_features.c` defines that function only for the
operating systems it names with an `ARMV8_OS_*` macro - Linux, Android,
macOS, Fuchsia, iOS, Windows - and zlib.gyp names none for OpenBSD, so the
v26.12.0 openbsd-arm64 build stopped linking `openssl-cli`: "undefined
symbol: cpu_check_features".

The patch defines `ARMV8_OS_OPENBSD` for `__OpenBSD__` on `__aarch64__`,
which makes `cpu_check_features()` run `_cpu_check_features()` once through
`pthread_once`, as on Linux. That reads the CRC32 and PMULL bits with
`elf_aux_info(AT_HWCAP)` when `<sys/auxv.h>` and the `HWCAP_*` constants
exist, and otherwise leaves both off, so zlib uses its portable CRC code
rather than an instruction the CPU may not have. On openbsd-x64 the patch
changes nothing.

**Files:** `deps/zlib/cpu_features.c`  
**Platforms:** openbsd-arm64 (applied with `dist/openbsd/`, inert on openbsd-x64).  
**Applies to:** upstream Node.js 26.x (verified against `v26.12.0`).
