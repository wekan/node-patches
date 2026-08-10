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
- The fourteen platforms: `i386`, `armv6`, `armhf`, `armv7`, `loong64`, `x64`,
  `arm64`, `ppc64le`, `s390x`, `riscv64`, `win64`, `win32`, `mac-x64`,
  `mac-arm64`.

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
**`all/`** section and the **`ia32/`**, **`arm/`**, **`mac/`** and **`win32/`**
family sections, and the **Release All** / **Release All Missing** workflows clone
the newest upstream release, verify and apply each platform's sections, and build
the fourteen-platform binary set that WeKan embeds. The patches restore **32-bit
Windows**, add the **32-bit x86** and **32-bit ARM** SIMD/build flags, and correct
**Apple Clang** and **V8** compile errors; **s390x** builds with a real
**mksnapshot** under **qemu-user** instead of the big-endian V8 simulator, so it
needs no patch of its own. The fourteenth platform is **armv6** — Raspberry Pi 1
and Zero, which nobody publishes a Node.js for any more, though V8 and
`configure.py` still carry the support and only the build was missing.
Below that: the fixes the **first run** turned up — a `mv` that could never
work and killed all thirteen builds seconds after cloning, release notes read from a
tree this repo does not have, and a `.lib` listed as a platform — the two **test
scripts** that now catch that class of failure in a second instead of hours, and the
design docs and maintainer instructions the repo is set up with.

This release adds the following patch sections for the upstream Node.js v24.x line:

**The common section** (`dist/all/`) - applied to every platform.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/9aa6398">v8-turboshaft-template-disambiguator — adds the template keyword a stricter compiler requires</a>. Thanks to xet7.</summary>

`deps/v8/src/compiler/turboshaft/int64-lowering-reducer.h` needs an explicit
`template` disambiguator on a dependent member call, which some compilers this repo
builds with reject without it. It is valid C++ everywhere, so it is applied to every
platform.

</details>

**32-bit x86** (`dist/ia32/`) - applied to i386 and win32.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/9aa6398">v8-gyp-ia32-push-registers — selects V8's ia32 stack-scanning source so 32-bit x86 links</a>. Thanks to xet7.</summary>

V8 12.8+ has no ia32 `push_registers_masm.asm`, only `push_registers_asm.cc`, so
`tools/v8_gypfiles/v8.gyp` selects the `.cc` variant for an ia32 host or target. Its
`_WIN32` branch is written in Clang syntax, which is why the win32 build uses ClangCL.
Split by hunk from the former combined v8-gyp patch; the s390x half is in the s390x
section.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/9aa6398">zlib-sse2 — gives the bundled zlib the -msse2 flag its SSE2 intrinsics need on 32-bit x86</a>. Thanks to xet7.</summary>

On x86_64 SSE2 is part of the architecture; on 32-bit x86 gcc targets plain i686 and
rejects the SSE2 intrinsics zlib's SIMD source uses. `deps/zlib/zlib.gyp` adds
`-msse2` (and the Xcode / MSVS equivalents) for `target_arch=="ia32"`. Node's ia32
build already requires an SSE2 CPU, so this only asks for what the binary needs
anyway. Split by hunk from the former combined zlib patch; the NEON half is in the
ARM section.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/9aa6398">icu-cross-build — maps ia32 to x86 for the ICU genccode host tool</a>. Thanks to xet7.</summary>

`tools/icu/icu-generic.gyp` maps the `ia32` dest-cpu to the `x86` name the ICU
`genccode` host tool expects, so the ICU data step runs during a 32-bit build instead
of failing on an unknown architecture.

</details>

**32-bit ARM** (`dist/arm/`) - applied to armhf and armv7.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/9aa6398">zlib-neon — gives the bundled zlib the -mfpu=neon flag, and keeps the ARMv8 CRC path off ARMv7</a>. Thanks to xet7.</summary>

On arm64 NEON is the baseline; on 32-bit ARM it is an extension and the SIMD file is
otherwise compiled as plain ARMv7-A, so its NEON intrinsics fail to inline.
`deps/zlib/zlib.gyp` adds `-mfpu=neon` for `target_arch=="arm"`, scopes the ARMv8-only
`zlib_arm_crc32` dependency to arm64, and sets `ARMV8_OS_*` directly so 32-bit ARM
links. Split by hunk from the former combined zlib patch.

</details>

**Apple Clang** (`dist/mac/`) - applied to mac-x64 and mac-arm64.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/9aa6398">crypto-kmac-aggregate-init — uses the brace initialiser Apple Clang accepts for KMAC</a>. Thanks to xet7.</summary>

`src/crypto/crypto_kmac.cc` uses C++20 parenthesized aggregate initialisation that GCC
and modern Clang accept but the macOS runner's Apple Clang rejects. The patch uses the
portable brace form instead, the same style `crypto_hash.cc` already uses.

</details>

**Windows 32-bit** (`dist/win32/`) - applied to win32.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/9aa6398">32bit-windows-build — restores the 32-bit Windows (x86 / ia32) build upstream removed in Node 23</a>. Thanks to xet7.</summary>

Upstream stopped building 32-bit Windows in Node 23
([nodejs/node#53184](https://github.com/nodejs/node/pull/53184)). WeKan still ships a
`node-win32.exe`, so the patch puts back the `valid_arch` and arch matchup in
`configure.py`, the ia32-scoped `/SAFESEH:NO` and `TargetMachine` settings in
`common.gypi`, the `win-x86` `libUrl` special-case in `src/node_metadata.cc`,
`/arch:SSE2` in `toolchain.gypi`, the `x86` argument and `amd64_x86` cross toolchain
in `vcbuild.bat`, and the Windows x86 row in `BUILDING.md`. The generic 32-bit x86
pieces a win32 build also needs are in the ia32 section.

</details>

and adds a fourteenth platform:

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/c5d6ca4">armv6 — Raspberry Pi 1 and Zero, which nobody else publishes a Node.js for</a>. Thanks to xet7.</summary>

nodejs.org dropped its ARMv6 binaries after Node 11 and unofficial-builds has
none, so an ARMv6 board has no Node.js runtime at all — the same gap this
repository already fills for loong64 and 32-bit Windows, and the same shape: the
SUPPORT is still in the source, only the build was missing.

V8 still lists it. `deps/v8/src/codegen/arm/assembler-arm.cc` has
`static const unsigned kArmv6 = 0u;` with `kArmv7 = kArmv6 | (1u << ARMv7)`, and
accepts `--arm-arch=armv6`, printing *"Supported values are: armv8 /
armv7+sudiv / armv7 / armv6"* for anything else. `configure.py` still carries
`is_arch_armv6()` setting `arm_version='6'`, and `vfp` — VFPv2, the ARMv6 FPU —
is still in `valid_arm_fpu`. ARMv5 is the one that really is gone: V8's list
stops at armv6, which is why armel stays in the "deliberately not here" list.

It is built like armhf — cross compiled from an i386 container, because
`v8config.h` refuses a 32-bit ARM target on a 64-bit host — with
`--with-arm-fpu=vfp` and `-march=armv6+fp`, the Raspberry Pi OS baseline for
those boards.

**The `-march` has to ride on `CC` and `CXX`, not on `CFLAGS`,** and that is why
`matrix.extra_cflags` exists at all: `configure.py` decides `arm_version` by
PROBING the compiler's predefined macros — `is_arch_armv6()` looks for
`__ARM_ARCH_6*__` — so a `-march` that is only in `CFLAGS` is invisible to it
and the build would come out ARMv7 while claiming to be ARMv6. The field is
empty for every other platform, which leaves their `CC` exactly as it was.

It takes the COMMON patch set only, unlike armhf and armv7. `dist/arm` is the
NEON patch — it puts `-mfpu=neon` on zlib's SIMD targets — and ARMv6 has no
NEON, so that flag would be a compile error rather than a speed-up. Nothing is
lost: `zlib.gyp` gates every ARM SIMD path on `arm_fpu == "neon"`, so an armv6
build selects the scalar code by itself and the patch has nothing to fix.

**What is and is not verified.** The workflow parses, both test suites pass
(`tests/workflow-logic.sh` caught the release-notes platform list, which is why
it is updated in both places), the apply-map returns the common set for armv6
and the NEON set for armhf/armv7, and every claim about V8 and `configure.py`
above is quoted from the v24.x source. The BUILD itself is not verified here and
cannot be: it is a multi-hour ARM cross compile, so the first run is its test —
and armhf, the same shape, has been measured past 180 minutes at ~85%, so 360 is
the timeout.

</details>

and fixes what the armv6 runs turned up:

**armv6** - the two walls the first two runs hit, each in something that is not
armv6 code at all.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/c6eaea4">armv6 passes -marm, or glibc's own headers refuse the hard-float ABI</a>. Thanks to xet7.</summary>

The first armv6 build died 82 seconds in, on the first four files it compiled:

```
/usr/arm-linux-gnueabihf/include/bits/stdio.h:40:1: sorry, unimplemented:
Thumb-1 'hard-float' VFP ABI
make[1]: *** [deps/openssl/openssl.target.mk:1308: .../ssl/d1_msg.o] Error 1
```

Debian's `arm-linux-gnueabihf` gcc defaults to **Thumb**. On ARMv7 that is
Thumb-2, which supports the hard-float VFP ABI — which is why armhf and armv7
have never needed to say anything about it. `-march=armv6` has only **Thumb-1**,
and GCC has never implemented the hard-float VFP ABI for Thumb-1, so the
toolchain's default mode and this `-march` are a combination the compiler
refuses.

What made it read like a broken toolchain rather than a missing flag is WHERE it
refuses: inside glibc's own headers, on every static inline in `stdio.h`,
`stdlib.h` and `byteswap.h`. Not one file of ours appears in the error.

`-marm` builds in ARM mode instead — which is what Raspberry Pi OS builds these
boards with anyway — and is the only change: `-march=armv6+fp -mfpu=vfp
-mfloat-abi=hard` stay exactly as they were, and so does the `arm_version='6'`
`configure.py` probes out of them.

`tests/workflow-logic.sh` grows the check that any target naming `-march=armv6`
also passes `-marm`, verified BOTH ways: it passes as committed, and removing
`-marm` from the matrix makes it fail with the reason. A one-word flag in a
build that only fails after apt, a clone and a minute of compiling is the kind
that goes missing twice.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/d5a9fe5">armv6 gets the HWY_BROKEN_EMU128 define armv7 already had, or V8's JSON stringifier will not compile</a>. Thanks to xet7.</summary>

With `-marm` in, the second run got 45 minutes further and stopped in V8:

```
deps/v8/third_party/highway/src/hwy/ops/shared-inl.h:368:27: error:
static assertion failed: Too many lanes
  note: the comparison reduces to '(16 <= 1)'
deps/v8/src/json/json-stringifier.cc:3356:33: error: no matching function for
call to 'Set(hwy::N_SCALAR::FixedTag<unsigned char, 16>&, int)'
```

Highway's `HWY_BROKEN_EMU128` defaults to **1** for GCC older than 14 — a GCC
bug Highway works around by target rather than by version — and when it is 1
Highway drops its fallback target from **EMU128**, sixteen emulated lanes, to
**SCALAR**, one. `json-stringifier.cc` asks for `hw::FixedTag<uint8_t, 16>` on
that path unconditionally, and one lane cannot hold sixteen.

Upstream already carries the workaround — for s390x, for AIX, and for 32-bit ARM
— but the ARM condition is an exact `arm_version==7`. An ARMv6 build sets
`arm_version` to 6, from the compiler's own `__ARM_ARCH_6*__`, so it never
matched: ARMv6 was the one 32-bit ARM target left on SCALAR.
`dist/all/v8-gyp-armv6-hwy-emu128.patch` makes the condition read
`arm_version==7 or arm_version==6`.

**The 6-versus-7 distinction was never about the bug**, which belongs to the
compiler: the object that failed is a HOST object, built by the same container's
`g++` that compiles the armhf and armv7 jobs successfully WITH the define. And
EMU128 is Highway's pure C++ emulation of 128-bit vectors, so enabling it asks
nothing of the CPU — it is the same code ARMv7 has been compiling all along.

It is in the COMMON section rather than `dist/arm`, for two reasons: the change
sits inside a `v8_target_arch=="arm"` condition, so it is a no-op everywhere
else, and armv6 does not take `dist/arm` at all — that is the NEON patch.

Verified against real upstream: `tests/patches-apply.sh` fetches Node v24.19.0
and applies every section, this patch included, for all fourteen platforms; the
patched `v8.gyp` still parses; and the trio check sees its `.patch`,
`.sha256sum` and `.md`. The BUILD is the next CI run, as before.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/3d16f16">armv6 builds for the CPU those boards have, so V8's 8-byte atomics are lock-free</a>. Thanks to xet7.</summary>

With `-marm` and the `HWY_BROKEN_EMU128` define in, the third run got **74
minutes** further — past the host tools and into the real ARM cross compile —
and stopped in V8:

```
deps/v8/src/common/segmented-table.h:124:44: error: static assertion failed
static_assert(std::atomic<FreelistHead>::is_always_lock_free);
  required from 'class SegmentedTable<JSDispatchEntry, 268435456>'
```

`FreelistHead` is two `uint32`s, so that is an **8-byte atomic**. The plain
ARMv6 baseline has `LDREX`/`STREX` for words only; the 64-bit pair,
`LDREXD`/`STREXD`, arrived in **ARMv6K**. Without them an 8-byte atomic is not
lock-free, the assertion is false, and V8's JS dispatch table — leaptiering,
which is on by default — does not compile.

The fix is `-mcpu=arm1176jzf-s` instead of `-march=armv6+fp`, and it is not a
workaround: **that is the CPU these boards have.** The Raspberry Pi 1 and the
Zero are ARM1176JZF-S, which is ARMv6KZ — ARMv6K plus the security extensions —
so building for the baseline was asking for a machine narrower than anything
that will ever run this bundle, and paying for it with V8.

Nothing else moves. `-marm`, `-mfpu=vfp` and `-mfloat-abi=hard` stay;
`configure.py` still probes `__ARM_ARCH_6*__` and still comes out at
`arm_version` 6, so `--arm-arch=armv6` and the `HWY_BROKEN_EMU128` patch —
which keys on `arm_version==6` — apply exactly as before.

The guard covers both walls now, and reads the armv6 matrix entry rather than
grepping for a flag string that has just changed: ARM mode, an ARMv6K CPU, and
hard-float. Checked in the failing direction too — putting `-march=armv6+fp`
back fails it with *"asks for a CPU without LDREXD"*.

</details>

and fixes the following in the release workflows:

**Release All** - the workflow that clones upstream, applies the patches and
publishes.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/6f673ce1536f17cdd1d90e5e7366a54137919173">The upstream tree is moved into the workspace once, not twice, so the builds get past the clone</a>. Thanks to xet7.</summary>

The first run failed all thirteen builds, three seconds after cloning, before a
compiler ever started - and the publish job with them, since it then had no
artifact to attach. The step moves the cloned Node.js tree up beside
`_patches/`:

```
shopt -s dotglob
mv nodesrc/* .
mv nodesrc/.git .
```

`dotglob` is what makes `nodesrc/*` include the dotfiles, so the glob had
ALREADY moved `.git`. The second `mv` could only ever answer `cannot stat
'nodesrc/.git': No such file or directory`, and under `set -e` that ended the
step. The line is gone; `rmdir nodesrc` is now the assertion that the move was
complete, since it refuses a non-empty directory, and a check that `.git` really
arrived says so in one line rather than leaving `git apply` to fail obscurely.

Verified end to end here, not only read: a real shallow clone of `v24.19.0`,
moved, checksum-verified and patched, for `x64` (one section) and for `win32`
(five patches across three sections), after which the patched tree's own
`./configure` completes.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/6f673ce1536f17cdd1d90e5e7366a54137919173">The release notes carry upstream's own notes again, fetched from the tag rather than read from a tree that is not there</a>. Thanks to xet7.</summary>

The publish job composed the notes by reading
`doc/changelogs/CHANGELOG_V24.md` out of the workspace. That job checks out THIS
repository - which carries patches, not a Node.js tree - so the file was never
there and the notes could only ever come out as the header with nothing under
it. It now fetches that changelog from `nodejs/node` at the tag that was built.
A tag is immutable, so the file it reads is the changelog of exactly the source
the binaries were built from, and a 404 leaves the header alone instead of
pasting an error page into the release.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/6f673ce1536f17cdd1d90e5e7366a54137919173">The Windows import library stops appearing on the release as a platform of its own</a>. Thanks to xet7.</summary>

The Windows jobs upload `node-win32.lib` beside `node-win32.exe` - the import
library native addons link against. The notes step turned every downloaded
artifact into a platform name and dropped only the `.sha256sum` files, so the
`.lib` became a platform called `win32.lib`, listed beside the real ones. It is
filtered out with the checksums now.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/6f673ce1536f17cdd1d90e5e7366a54137919173">The actions are off the deprecated Node 20 runtime</a>. Thanks to xet7.</summary>

Every job warned that `actions/checkout@v4` and `actions/download-artifact@v4`
target Node.js 20 and were being forced onto Node 24. They move to the majors
WeKan's own release workflow already runs - `checkout@v7`,
`upload-artifact@v7`, `download-artifact@v8` - which target Node 24 themselves.

</details>

and fixes the three builds the second run lost:

**Windows** - both builds, dead in their first seconds, on the first thing the
build does.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/6e2cc9e">The Windows builds get past their first step: patches are checked out byte-exact</a>. Thanks to xet7.</summary>

win64 and win32 both died seconds after cloning:

```
sha256sum: 'v8-turboshaft-template-disambiguator.patch'$'\r': No such file
sha256sum: WARNING: 1 listed file could not be read
```

and the step ended with exit code 1.

Git for Windows checks text files out with CRLF — `core.autocrlf=true` is its
default and `actions/checkout` does not turn it off — so the `.sha256sum` files
arrived with a trailing carriage return and `sha256sum -c`, which reads the
FILENAME out of that file, went looking for a file whose name ends in one. The
`.patch` files had been converted too, so had the checksum somehow passed,
`git apply` would have failed next on a patch whose every line ends CRLF while
the upstream file it patches ends LF.

`.gitattributes` now marks `*.patch` and `*.sha256sum` as `-text`: no checkout
converts them, on any platform, which also matters because a patch's own content
may legitimately be CRLF — `win32/32bit-windows-build` patches `vcbuild.bat`.
The build's check no longer hands the file to `sha256sum -c` either; it compares
the recorded hash itself, with any CR stripped. That is the belt to the braces,
since `.gitattributes` only helps a checkout that happens after it.

</details>

**IBM Z** - the one big-endian platform, now built like a native s390x build.

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/36232d9f2c2ad8537a7d0c1b2b44aff647866c86">The s390x build script parses again - an apostrophe was ending it early</a>. Thanks to xet7.</summary>

The build that replaced the simulator died three seconds in, before it compiled
anything: `line 41: unexpected EOF while looking for matching "`, and the
release job correctly reported that no platform produced a binary. One character
caused it. The cross-compile body is a single-quoted `sh -c '...'` argument, and
the line that verifies the gyp edit read `grep -q "want_separate_host_toolset':
0"` - that apostrophe ENDS the single-quoted argument, and a single quote cannot
be escaped from inside one, not with a backslash and not by nesting it in double
quotes. Everything after it was parsed as something else and the script never
reached `make`.

`config.gypi` holds `'want_separate_host_toolset': 0`, so the check reads the
same line with the quote matched by a dot - `grep -qE
"want_separate_host_toolset.: *0"` - and the block stays one argument.
`tests/workflow-logic.sh` gains a check that extracts every `run:` block from
both workflows, substitutes the `${{ }}` expressions the way Actions does before
a shell sees them, and hands each to `bash -n`. Every check before it reads what
the blocks DO, which is why none noticed a block that cannot be parsed at all.
It fails on the previous line, naming the step, and passes on this one.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/7778e1e">s390x builds a real mksnapshot under qemu-user instead of V8's big-endian simulator</a>. Thanks to xet7.</summary>

Every cross target runs mksnapshot as a host binary that SIMULATES the target
inside V8. The little-endian ones (ppc64le, riscv64, loong64) simulate fine, but
the big-endian s390x simulator segfaulted every time it generated the
snapshot - `Segmentation fault (core dumped)`, `v8_snapshot` Error 139 - and
single-threaded mode, dropping the register-allocator stress flag, and a 16 MB
simulated stack all failed to stop it.

s390x now builds the way nodejs.org does: a REAL s390x mksnapshot, no
simulator. The new `cross-qemu` build mode turns `want_separate_host_toolset`
off so the V8 build-tools compile for the target, registers qemu-user via
binfmt, and runs those s390x tools through it with `QEMU_LD_PREFIX` pointing at
the cross toolchain's libraries. The object files are still cross-compiled at
native speed; only the few seconds a build-tool runs are emulated. Because it is
a clean native-style build, the two `dist/s390x` simulator patches are removed -
s390x needs no patch of its own now.

Unproven until a run confirms it, so s390x stays BEST-EFFORT in the matrix
(`continue-on-error`, the only platform that is): nodejs.org publishes
linux-s390x for every release and WeKan's `resolve-node-source.sh` takes its
Node.js from nodejs.org first, so the gap costs a WeKan bundle nothing
meanwhile, and the platform comes back by itself the day it builds.

</details>

and adds the following tests:

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/6f673ce1536f17cdd1d90e5e7366a54137919173">Two test scripts that run without a 13-platform build</a>. Thanks to xet7.</summary>

A build takes hours on thirteen platforms and cannot run in the sandbox at all,
so the failures worth catching are the ones that kill a job in its first
seconds - which is precisely what the `mv` above was.

`tests/workflow-logic.sh` needs no network and no runner. It EXTRACTS the shell
blocks out of `release-all.yml` and RUNS them against a fabricated workspace,
rather than restating them in a test, so a pass means the workflow's own lines
behave. Its negative test puts the removed `mv nodesrc/.git .` back and requires
the block to fail, which is what proves it can tell the two apart. It also
checks that the build matrix, `release-all-missing.yml`'s platform list and the
release notes' list name the same platforms, that the apply-map answers for
every platform, that each patch is a complete `.patch`/`.sha256sum`/`.md` trio
whose checksum matches, and that no build applies two sections touching one
file.

`tests/patches-apply.sh` answers the question the repository lives or dies on:
does every platform's patch set still apply to the upstream release the build
would clone. It reconstructs a tree of exactly the files the patches touch -
derived from their own headers, so a patch that starts touching another file is
fetched without anyone remembering - and applies each platform's sections
cumulatively, checksum first, as the workflow does. No clone: a gigabyte to
answer a question about thirteen files. It exits 77 when upstream is
unreachable, so a sandbox without network says so instead of reporting a green
run it did not do.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/6e2cc9e">Guards so the second run's two failures cannot come back unnoticed</a>. Thanks to xet7.</summary>

`tests/workflow-logic.sh` now also checks that `.gitattributes` marks `*.patch`
and `*.sha256sum` as `-text`, since a repository without that line is one
Windows checkout away from the failure above; that the build's checksum check —
extracted from the workflow and run, as everything else in that file is —
accepts a `.sha256sum` written with CRLF and still rejects a wrong hash; and
that s390x is the ONLY platform marked best-effort, because a platform that
quietly stops building is a platform nobody notices is gone.

</details>

and documents how to work on this repository:

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/0b9679b">AGENTS.md — what a contributor, human or otherwise, has to know before touching a patch</a>. Thanks to xet7.</summary>

A patches-only repository is unusual enough that the obvious first move is the
wrong one: there is no Node.js source here to edit, so a change is a change to a
`.patch` file, and it has to apply to a tag nobody has cloned yet. `AGENTS.md`
writes that down — the directory layout and which platform reads which section,
that patches are applied to the newest upstream RELEASE tag rather than a branch
head, how to verify one applies before pushing, and which workflow builds what.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/44a2ce0">Every place that counts the platforms says fourteen, and the historical ones say when they meant thirteen</a>. Thanks to xet7.</summary>

Adding armv6 above made a number wrong in eleven places — `AGENTS.md`,
`CLAUDE.md`, both design docs, both test scripts and both workflows still said
thirteen platforms, and two of them said it as `13`. A build-matrix count in
prose is exactly the kind of fact that rots quietly: nothing fails, and the next
reader trusts it.

The distinction that mattered while fixing them is that **not every "thirteen"
was wrong**. The first run's failure really did kill thirteen builds three
seconds after cloning — that is a fact about that run, not about the matrix — so
those sentences keep the number and now say so out loud (*"thirteen of them at
the time, fourteen since armv6"*) instead of leaving the next reader to guess
whether it is history or a stale count.

One count was wrong for a different reason: `tests/patches-apply.sh` and both
instruction files describe the no-clone trick as *"a gigabyte to answer a
question about thirteen files"*. The patches touch **twelve** files. Counted
from the patch headers themselves, which is where the script gets them too.

</details>

<details>
<summary><a href="https://github.com/wekan/node-patches/commit/8999131">The maintainer rules move to WeKan's CLAUDE.md and AGENTS.md, and the copies here are removed</a>. Thanks to xet7.</summary>

`CLAUDE.md` and `AGENTS.md` here said who maintains this repository, who commits
and as whom, and how the CHANGELOG is written. Every word of that is true of each
repository WeKan clones into its `.tools/` directory and none of it is specific
to this one, so it was a second copy of a rule — and a second copy drifts. WeKan's
own `CLAUDE.md` and `AGENTS.md` now carry the rules for all of them, including
the layout of `.tools/` and the instruction not to add these files back here.

What was genuinely about THIS repository was already elsewhere and stays:
`docs/Design/Directory-structure.md` and `docs/Design/How-the-build-works.md` for
the layout and the build, `dist/README.md` for the sections and the apply-map,
and each test script's own header for what it checks. The design doc and the
README point at WeKan's files for the rules, so a reader who starts here still
finds them.

</details>

Thanks to above GitHub users for their contributions.
