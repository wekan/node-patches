# icu-cross-build

Tells ICU's `genccode` the CPU name it expects on 32-bit x86, so the ICU data
object builds for ia32 (i386 and win32).

`genccode -c` takes ICU's name for the CPU, not node's. They agree on x64, arm64
and arm by coincidence, but on 32-bit x86 node says `ia32` while ICU's
`checkCpuArchitecture()` accepts only `x64`/`x86`/`arm64`/`arm` — so a 32-bit x86
build stopped with `CPU architecture "ia32" is unknown.` The gyp now maps
`target_arch=="ia32"` to `icu_cpu_arch=x86` (which ICU maps to
`IMAGE_FILE_MACHINE_I386`, the machine type a 32-bit `.obj` needs) and passes
`<(target_arch)` for every other arch. Upstream never hit this because it no
longer builds 32-bit Windows.

**Files:** `tools/icu/icu-generic.gyp`
**Platforms:** i386, win32 (`dist/ia32/`).
**Applies to:** upstream Node.js 24.x (verified against `v24.19.0`).
