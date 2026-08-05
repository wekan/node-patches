# dist/ — the patch sections

Patches are organised by **which platforms they affect**, not by upstream version.
Every build applies the **common** section plus the **family/platform** sections its
target maps to. The upstream version is resolved at build time (the newest
`v<MAJOR>.x` release; see [`../node-major.txt`](../node-major.txt)), so these
sections are version-agnostic and carry forward across upstream releases.

## Sections

| Section | Applies to | What it carries |
|---------|-----------|-----------------|
| `all/` | every platform | Cross-cutting source fixes valid everywhere (V8 Turboshaft template disambiguator). |
| `ia32/` | i386, win32 | 32-bit x86: V8 ia32 `push_registers`, zlib `-msse2`, ICU `genccode` name mapping. |
| `arm/` | armhf, armv7 | 32-bit ARM: zlib `-mfpu=neon`, ARMv8-only CRC path kept off ARMv7. |
| `s390x/` | s390x | IBM Z cross-build under the V8 simulator: mksnapshot single-threaded, simulator const-cast. |
| `mac/` | mac-x64, mac-arm64 | Apple Clang: KMAC brace initialisation. |
| `win32/` | win32 | Windows 32-bit build restoration (upstream removed it in Node 23). |

## Apply-map

The one place `platform → sections` lives is
[`../releases/dist-dirs-for.sh`](../releases/dist-dirs-for.sh). It must stay in step
with the build matrix in [`../.github/workflows/release-all.yml`](../.github/workflows/release-all.yml).

| Platform | Sections applied |
|----------|------------------|
| x64, arm64, ppc64le, riscv64, loong64, win64 | `all` |
| i386 | `all`, `ia32` |
| win32 | `all`, `ia32`, `win32` |
| armhf, armv7 | `all`, `arm` |
| s390x | `all`, `s390x` |
| mac-x64, mac-arm64 | `all`, `mac` |

`all/` is applied first, then each family/platform section. No single build applies
two sections that touch the same file, so order within a build never conflicts.

## Each patch is three files

Every patch is `<name>.patch`, `<name>.sha256sum` (checksum of the `.patch`, verified
before it is applied), and `<name>.md` (what it does). See
[../docs/Design/Patch-format.md](../docs/Design/Patch-format.md).
