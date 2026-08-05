# Platforms

Node.js binaries built from upstream + these patches, at these platforms:

- [Releases](https://github.com/wekan/node-patches/releases)
- [Upstream Node.js](https://github.com/nodejs/node)
- [How WeKan consumes them](https://github.com/wekan/wekan)
- [Design docs](docs/Design/Directory-structure.md)

Each build applies its platform's patch sections onto a **shallow, single-branch**
clone (`--depth 1 --single-branch`) of the newest upstream Node.js **release** — the
newest `v<MAJOR>.x` tag (`MAJOR` from [`node-major.txt`](node-major.txt)), never a
branch head or a commit between releases, and with no git history behind the tag.
What was cloned for the current line:

| Upstream | Branch | Tag | Commit |
|----------|--------|-----|--------|
| [nodejs/node](https://github.com/nodejs/node) | v24.x | [v24.19.0](https://github.com/nodejs/node/releases/tag/v24.19.0) | [`cdc1b38d40cb567b7ad0b39c86addf830a0af0ae`](https://github.com/nodejs/node/commit/cdc1b38d40cb567b7ad0b39c86addf830a0af0ae) |

Each release's own notes repeat this table for the exact version it carries, filled
in by the build from the tag it cloned.

<details>
<summary>Version</summary>

- Patches are organised by **platform**, not by version: a common `dist/all/` section
  plus family/platform sections (`ia32/`, `arm/`, `s390x/`, `mac/`, `win32/`). Every
  build applies `dist/all` plus the sections the apply-map assigns its target. See
  [dist/README.md](dist/README.md).
- Each patch is a `*.patch` file with a `*.sha256sum` (the checksum of the patch file)
  and a `*.md` (what the patch does). The build clones upstream at the release tag,
  verifies each checksum, and applies the patch.
- The upstream version is resolved at build time — the newest `v<MAJOR>.x` release —
  so the sections carry forward across upstream releases without editing.
- The binaries a release carries are named `node-<platform>` (`node-<platform>.exe`
  on Windows), each with a `node-<platform>.sha256sum`. A release accumulates
  binaries — a rebuilt platform clobbers its own asset and leaves the rest alone.
- The thirteen platforms: `i386`, `armhf`, `armv7`, `loong64`, `x64`, `arm64`,
  `ppc64le`, `s390x`, `riscv64`, `win64`, `win32`, `mac-x64`, `mac-arm64`.

</details>

# TODO Later

<details>
<summary>Carried to a future release.</summary>

Investigated but not finished, with findings recorded for whoever picks them up
next. Entries that have since been done are removed from this list as they are
handled (their commits carry the short description and link).

Nothing carried yet — this is the first patch set.

</details>

# Upcoming node-patches release

**In short:** the first patch set, for the upstream Node.js **v24.x** line, and the
repository that carries it — a **patches-only** repo modelled on
[Betterbird/thunderbird-patches](https://github.com/Betterbird/thunderbird-patches).
It holds no Node.js source: patches are organised by platform into a common
**`all/`** section and the **`ia32/`**, **`arm/`**, **`s390x/`**, **`mac/`** and
**`win32/`** family sections, and the **Release All** / **Release All Missing**
workflows clone the newest upstream release, verify and apply each platform's
sections, and build the thirteen-platform binary set that WeKan embeds. The patches
restore **32-bit Windows**, add the **32-bit x86** and **32-bit ARM** SIMD/build
flags, fix the **s390x** cross-build, and correct **Apple Clang** and **V8** compile
errors. Below that: the design docs and the maintainer instructions the repo is set
up with.

This release adds the following patch sections for the upstream Node.js v24.x line:

**The common section** (`dist/all/`) - applied to every platform.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/HEAD">v8-turboshaft-template-disambiguator — adds the template keyword a stricter compiler requires</a>. Thanks to xet7.</summary>

`deps/v8/src/compiler/turboshaft/int64-lowering-reducer.h` needs an explicit
`template` disambiguator on a dependent member call, which some compilers this repo
builds with reject without it. It is valid C++ everywhere, so it is applied to every
platform.

</details>

**32-bit x86** (`dist/ia32/`) - applied to i386 and win32.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/HEAD">v8-gyp-ia32-push-registers — selects V8's ia32 stack-scanning source so 32-bit x86 links</a>. Thanks to xet7.</summary>

V8 12.8+ has no ia32 `push_registers_masm.asm`, only `push_registers_asm.cc`, so
`tools/v8_gypfiles/v8.gyp` selects the `.cc` variant for an ia32 host or target. Its
`_WIN32` branch is written in Clang syntax, which is why the win32 build uses ClangCL.
Split by hunk from the former combined v8-gyp patch; the s390x half is in the s390x
section.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/HEAD">zlib-sse2 — gives the bundled zlib the -msse2 flag its SSE2 intrinsics need on 32-bit x86</a>. Thanks to xet7.</summary>

On x86_64 SSE2 is part of the architecture; on 32-bit x86 gcc targets plain i686 and
rejects the SSE2 intrinsics zlib's SIMD source uses. `deps/zlib/zlib.gyp` adds
`-msse2` (and the Xcode / MSVS equivalents) for `target_arch=="ia32"`. Node's ia32
build already requires an SSE2 CPU, so this only asks for what the binary needs
anyway. Split by hunk from the former combined zlib patch; the NEON half is in the
ARM section.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/HEAD">icu-cross-build — maps ia32 to x86 for the ICU genccode host tool</a>. Thanks to xet7.</summary>

`tools/icu/icu-generic.gyp` maps the `ia32` dest-cpu to the `x86` name the ICU
`genccode` host tool expects, so the ICU data step runs during a 32-bit build instead
of failing on an unknown architecture.

</details>

**32-bit ARM** (`dist/arm/`) - applied to armhf and armv7.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/HEAD">zlib-neon — gives the bundled zlib the -mfpu=neon flag, and keeps the ARMv8 CRC path off ARMv7</a>. Thanks to xet7.</summary>

On arm64 NEON is the baseline; on 32-bit ARM it is an extension and the SIMD file is
otherwise compiled as plain ARMv7-A, so its NEON intrinsics fail to inline.
`deps/zlib/zlib.gyp` adds `-mfpu=neon` for `target_arch=="arm"`, scopes the ARMv8-only
`zlib_arm_crc32` dependency to arm64, and sets `ARMV8_OS_*` directly so 32-bit ARM
links. Split by hunk from the former combined zlib patch.

</details>

**IBM Z** (`dist/s390x/`) - applied to s390x.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/HEAD">v8-gyp-s390x-mksnapshot — runs s390x mksnapshot single-threaded so it does not segfault the V8 simulator</a>. Thanks to xet7.</summary>

mksnapshot for s390x runs the target code under the big-endian s390x V8 simulator on
the x86_64 host, and that simulator is not thread-safe here. `tools/v8_gypfiles/v8.gyp`
drops the `--stress-turbo-late-spilling` default for s390x, excludes it from
`--concurrent-builtin-generation`, and forces it fully `--single-threaded`. Because it
is applied only to s390x, every other platform keeps upstream's defaults. Split by
hunk from the former combined v8-gyp patch.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/HEAD">s390-simulator-const-cast — fixes the s390 constants build under the V8 simulator</a>. Thanks to xet7.</summary>

`deps/v8/src/codegen/s390/constants-s390.h` needs a const-cast so the s390 V8
simulator — used to cross-build the s390x mksnapshot on an x86 host — compiles.
nodejs.org builds s390x natively and does not compile the simulator, so upstream never
hit this.

</details>

**Apple Clang** (`dist/mac/`) - applied to mac-x64 and mac-arm64.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/HEAD">crypto-kmac-aggregate-init — uses the brace initialiser Apple Clang accepts for KMAC</a>. Thanks to xet7.</summary>

`src/crypto/crypto_kmac.cc` uses C++20 parenthesized aggregate initialisation that GCC
and modern Clang accept but the macOS runner's Apple Clang rejects. The patch uses the
portable brace form instead, the same style `crypto_hash.cc` already uses.

</details>

**Windows 32-bit** (`dist/win32/`) - applied to win32.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/HEAD">32bit-windows-build — restores the 32-bit Windows (x86 / ia32) build upstream removed in Node 23</a>. Thanks to xet7.</summary>

Upstream stopped building 32-bit Windows in Node 23
([nodejs/node#53184](https://github.com/nodejs/node/pull/53184)). WeKan still ships a
`node-win32.exe`, so the patch puts back the `valid_arch` and arch matchup in
`configure.py`, the ia32-scoped `/SAFESEH:NO` and `TargetMachine` settings in
`common.gypi`, the `win-x86` `libUrl` special-case in `src/node_metadata.cc`,
`/arch:SSE2` in `toolchain.gypi`, the `x86` argument and `amd64_x86` cross toolchain
in `vcbuild.bat`, and the Windows x86 row in `BUILDING.md`. The generic 32-bit x86
pieces a win32 build also needs are in the ia32 section.

</details>

Thanks to above GitHub users for their contributions.
