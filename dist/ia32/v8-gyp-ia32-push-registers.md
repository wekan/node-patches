# v8-gyp-ia32-push-registers

Selects V8's ia32 heap stack-scanning source on 32-bit x86, so the build links.

V8 12.8+ has no ia32 `push_registers_masm.asm` any more — only
`push_registers_asm.cc` — so `tools/v8_gypfiles/v8.gyp` selects the `.cc` variant
for an ia32 host or target. Its top-level `asm()` carries a `_WIN32` branch written
in Clang's syntax, which is why the win32 build uses ClangCL. This is the V8 half
of the 32-bit x86 support; the Windows-specific build restoration is in
`win32/32bit-windows-build`, and this is one hunk-split half of the former
`v8-gyp-cross-build` patch (the s390x half is
`s390x/v8-gyp-s390x-mksnapshot`).

**Files:** `tools/v8_gypfiles/v8.gyp`
**Platforms:** i386, win32 (`dist/ia32/`).
**Applies to:** upstream Node.js 24.x (verified against `v24.19.0`).
