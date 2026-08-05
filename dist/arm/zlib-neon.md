# zlib-neon

Gives the bundled zlib the `-mfpu=neon` flag its NEON intrinsics need on 32-bit
ARM, and keeps the ARMv8-only CRC32 path off 32-bit ARM.

zlib's SIMD source uses NEON intrinsics. On arm64 NEON is the baseline and needs
no flag; on 32-bit ARM it is an extension and the file is otherwise compiled as
plain ARMv7-A, so every NEON intrinsic fails to inline ("target specific option
mismatch"). `deps/zlib/zlib.gyp` adds `-mfpu=neon` for `target_arch=="arm"` on the
adler32, data-chunk and deflate SIMD targets. It also scopes the `zlib_arm_crc32`
dependency (compiled `-march=armv8-a+aes+crc`, which a 32-bit ARM compiler
rejects) to `arm64` only, and sets the `ARMV8_OS_*` define directly for 32-bit ARM
so `adler32.c` links without the ARMv8 CRC path. This is the NEON half of the
former `zlib-simd` patch; the SSE2 half is `ia32/zlib-sse2`.

**Files:** `deps/zlib/zlib.gyp`
**Platforms:** armhf, armv7 (`dist/arm/`).
**Applies to:** upstream Node.js 24.x (verified against `v24.19.0`).
