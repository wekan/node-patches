# dist/ — the patch sections

Patches are organised by **which platforms they affect**, not by upstream version.
Every build applies the **common** section plus the **family/platform** sections its
target maps to. The upstream version is resolved at build time (the newest
`v<MAJOR>.x` release; see [`../node-major.txt`](../node-major.txt)), so these
sections are version-agnostic and carry forward across upstream releases.

## Sections

| Section | Applies to | What it carries |
|---------|-----------|-----------------|
| `all/` | every platform | Cross-cutting Node.js 26 source fixes for 32-bit ARM CPU features, scalar Highway paths, x86 hashing, typed arrays and PPC64LE TOC range. |
| `ia32/` | i386, win32, android-x86 | 32-bit x86: V8 ia32 `push_registers`, zlib `-msse2`, ICU `genccode` name mapping. (Histogram AVX2 kept off ia32 is upstream since v26.11.1.) |
| `arm/` | armhf, armv7 | 32-bit ARM: zlib `-mfpu=neon`, ARMv8-only CRC path kept off ARMv7. |
| `armv6/` | armv6 | Set an explicit ARMv6 architecture for V8 snapshot compilation. |
| `riscv64/` | riscv64 | Use linkable floating-point min/max assembler methods in Maglev. |
| `mac/` | mac-x64, mac-arm64 | Apple Clang: KMAC brace initialisation. |
| `win32/` | win32 | Windows 32-bit build restoration (upstream removed it in Node 23). |
| `openbsd/` | openbsd-x64, openbsd-arm64 | OpenBSD: the OpenBSD ports `lang/node` patches (by Volker Schlecht and others), rebased onto Node 26 - V8's OpenBSD platform and embedded-code section, W^X and retguard, IBT/BTI, abseil/highway, `wxneeded`. Also the bundled OpenSSL's source lists, and zlib's `cpu_check_features()` on arm64. |
| `bsd-arm64/` | openbsd-arm64 | Node's bundled OpenSSL for a BSD on arm64: the no-asm source list and the 31 no-asm dispatcher headers point at `linux-aarch64/no-asm` (configured `--openssl-no-asm`); before, they fell through to linux-x86_64 sources and linux-elf headers. |
| `netbsd/` | netbsd-x64 | NetBSD: pkgsrc's `lang/nodejs` patches for Node 26.11.1 - `netbsd` in the gyp OS lists, c-ares config, V8 platform and memory fixes, header includes. |
| `android/` | android-arm64, android-armv7, android-x64, android-x86 | Android/Termux: Termux's nodejs patches adapted (paths, `localhost` on IPv6, gyp `OS=="android"`, bionic runtime fixes) and zlib CPU features via `getauxval`. |

## Apply-map

The one place `platform → sections` lives is
[`../releases/dist-dirs-for.sh`](../releases/dist-dirs-for.sh). It must stay in step
with the build matrix in [`../.github/workflows/release-all.yml`](../.github/workflows/release-all.yml).

| Platform | Sections applied |
|----------|------------------|
| x64, arm64, ppc64le, loong64, win64, win-arm64, freebsd-x64 | `all` |
| i386 | `all`, `ia32` |
| win32 | `all`, `ia32`, `win32` |
| armhf, armv7 | `all`, `arm` |
| armv6 | `all`, `armv6` |
| riscv64 | `all`, `riscv64` |
| s390x | `all` |
| mac-x64, mac-arm64 | `all`, `mac` |
| android-arm64, android-x64 | `all`, `android` |
| android-x86 | `all`, `ia32`, `android` |
| android-armv7 | `all`, `arm`, `android` |
| openbsd-x64 | `all`, `openbsd` |
| openbsd-arm64 | `all`, `openbsd`, `bsd-arm64` |
| netbsd-x64 | `all`, `netbsd` |

`all/` is applied first, then each family/platform section, in the order above.
Two sections of one build may touch the same file - android-x86's `ia32/` and
`android/` both change `tools/v8_gypfiles/v8.gyp` - so they are applied
cumulatively, and `tests/patches-apply.sh` applies every platform's sections in
that order against the upstream release.

## Each patch is three files

Every patch is `<name>.patch`, `<name>.sha256sum` (checksum of the `.patch`, verified
before it is applied), and `<name>.md` (what it does). See
[../docs/Design/Patch-format.md](../docs/Design/Patch-format.md).
