# 32bit-windows-build

Restores the 32-bit Windows (x86 / ia32) build that upstream Node.js removed in
Node 23 ([nodejs/node#53184](https://github.com/nodejs/node/pull/53184)), plus the
32-bit x86/ARM Linux build flags that go with it.

Upstream stopped building and supporting 32-bit Windows in Node 23, deleting the
ia32/x86 pieces from the build. This project still ships a 32-bit Windows binary
(`node-win32.exe`), so those pieces are put back:

- **`configure.py`** — `ia32`/`x86` in `valid_arch` and the arch matchup, so
  `--dest-cpu=x86` and `vcbuild.bat x86` resolve to `ia32` again.
- **`common.gypi`** — the `/SAFESEH:NO` (`ImageHasSafeExceptionHandlers: false`)
  linker opt-out and the `TargetMachine` settings, scoped to ia32, placed here
  (not in `node.gyp`) so they reach V8's and ICU's targets too.
- **`node.gyp`** — a comment noting the `/SAFESEH:NO` opt-out moved to
  `common.gypi` (upstream had it here).
- **`src/node_metadata.cc`** — `process.release.libUrl` special-cases `ia32` to
  the `win-x86` directory name again, the way the Windows `node.lib` is published.
- **`tools/v8_gypfiles/toolchain.gypi`** — `/arch:SSE2` for ia32, so V8's ia32
  code generator does not emit surprising 80-bit-double artifacts.
- **`vcbuild.bat`** — the `x86`/`ia32` argument, WoW64 handling, and the
  `amd64_x86` cross toolchain selection.
- **`BUILDING.md`** — lists Windows x86 (32-bit) as a supported platform again.

These are the Windows-only pieces. The generic 32-bit x86 (ia32) pieces a win32
build also needs — the V8 `push_registers_asm.cc` selection, zlib `-msse2`, and the
ICU `genccode` name mapping — are in the **ia32** family (`dist/ia32/`), applied to
both `win32` and `i386`. That is why the apply-map gives win32 `all + ia32 + win32`.

**Files:** `configure.py`, `common.gypi`, `node.gyp`, `src/node_metadata.cc`,
`tools/v8_gypfiles/toolchain.gypi`, `vcbuild.bat`, `BUILDING.md`
**Platforms:** win32 (`dist/win32/`).
**Applies to:** upstream Node.js 24.x (verified against `v24.19.0`).
