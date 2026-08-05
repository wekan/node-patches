# zlib-sse2

Gives the bundled zlib the `-msse2` flag its SSE2 intrinsics need on 32-bit x86,
where SSE2 is not on by default.

zlib's SIMD source uses SSE2 intrinsics. On x86_64 SSE2 is part of the
architecture and needs no flag; on 32-bit x86 gcc targets plain i686 and rejects
every SSE2 intrinsic the file uses. `deps/zlib/zlib.gyp` adds `-msse2` (and the
Xcode / MSVS equivalents) for `target_arch=="ia32"` on the data-chunk and deflate
SIMD targets. Node's ia32 build already requires an SSE2 CPU (V8's ia32 code
generator emits SSE2), so this only asks the compiler for what the binary needs
anyway. This is the SSE2 half of the former `zlib-simd` patch; the NEON half is
`arm/zlib-neon`.

**Files:** `deps/zlib/zlib.gyp`
**Platforms:** i386, win32 (`dist/ia32/`).
**Applies to:** upstream Node.js 24.x (verified against `v24.19.0`).
