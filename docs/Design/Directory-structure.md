# Directory structure

`node-patches` carries **only patches** to upstream Node.js, never Node.js source.
The binaries WeKan embeds are built by CI, which clones upstream at a release tag,
applies the patches here, builds, and publishes. This is the same model as
[Betterbird/thunderbird-patches](https://github.com/Betterbird/thunderbird-patches).

```
node-patches/
├── CHANGELOG.md                       Release notes, WeKan-changelog format.
├── CLAUDE.md                          Maintainer/contributor rules for this repo.
├── node-major.txt                     The Node.js major line to track (e.g. 24).
├── .github/
│   └── workflows/
│       ├── release-all.yml            Clone upstream → verify+apply patches → build
│       │                              14 platforms → publish to the release.
│       └── release-all-missing.yml    Build only the binaries a release lacks;
│                                      calls release-all.yml (reusable) per platform.
├── releases/
│   ├── newest-release.sh              Resolve the newest upstream v<MAJOR>.x release.
│   └── dist-dirs-for.sh               The apply-map: platform → dist/ sections.
├── dist/
│   ├── README.md                      The sections and the apply-map, in prose.
│   ├── all/                           Common: applied to EVERY platform.
│   │   └── v8-turboshaft-template-disambiguator.{patch,sha256sum,md}
│   ├── ia32/                          32-bit x86: i386 + win32.
│   │   ├── v8-gyp-ia32-push-registers.{patch,sha256sum,md}
│   │   ├── zlib-sse2.{patch,sha256sum,md}
│   │   └── icu-cross-build.{patch,sha256sum,md}
│   ├── arm/                           32-bit ARM: armhf + armv7.
│   │   └── zlib-neon.{patch,sha256sum,md}
│   ├── s390x/                         IBM Z, cross under the V8 simulator.
│   │   ├── v8-gyp-s390x-mksnapshot.{patch,sha256sum,md}
│   │   └── s390-simulator-const-cast.{patch,sha256sum,md}
│   ├── mac/                           Apple Clang: mac-x64 + mac-arm64.
│   │   └── crypto-kmac-aggregate-init.{patch,sha256sum,md}
│   └── win32/                         Windows 32-bit only.
│       └── 32bit-windows-build.{patch,sha256sum,md}
└── docs/
    └── Design/
        ├── Directory-structure.md     This file.
        ├── How-the-build-works.md     The clone→verify→apply→build→publish flow.
        └── Patch-format.md            The three-file convention and how to author it.
```

## `dist/` — patches organised by platform, not by version

Patches are grouped by **which platforms they affect**, in a `common` section plus
`family/platform` sections — not by upstream version. Every build applies `dist/all`
(the common section) plus the sections the **apply-map** assigns its target; the
upstream version is resolved separately (below), so the sections carry forward across
upstream releases without editing.

| Section | Applies to | What it carries |
|---------|-----------|-----------------|
| `all/` | every platform | Cross-cutting source fixes valid everywhere. |
| `ia32/` | i386, win32 | 32-bit x86 build/compile fixes. |
| `arm/` | armhf, armv7 | 32-bit ARM SIMD flags. |
| `s390x/` | s390x | IBM Z cross-build fixes. |
| `mac/` | mac-x64, mac-arm64 | Apple Clang fixes. |
| `win32/` | win32 | Windows 32-bit build restoration. |

The **apply-map** — `platform → sections` — lives in one place,
[`releases/dist-dirs-for.sh`](../../releases/dist-dirs-for.sh), and is tabulated in
[`dist/README.md`](../../dist/README.md). `all/` is applied first, then each
family/platform section; no single build applies two sections that touch the same
file, so order within a build never conflicts.

Every patch is **three files sharing a base name**:

| File | What it is |
|------|-----------|
| `<name>.patch` | The code change, as `git diff` / `git format-patch` output, applying cleanly to a pristine upstream checkout of the tracked version. |
| `<name>.sha256sum` | `sha256sum <name>.patch`, run in the section directory so it records the bare name. CI verifies this **before** applying the patch, so a corrupted or edited patch fails loudly instead of applying wrong. |
| `<name>.md` | What the patch does — a `# <name>` title, one-line summary, body, `**Files:**`, `**Platforms:**`, `**Applies to:**`. The source for the CHANGELOG entry and the next reader's explanation. |

The name is the **logical change**, not a file: `32bit-windows-build` touches seven
files but is one patch; `zlib-sse2` is one concern in one file. A change that spans
platform families is split by hunk into each family's section (the former
`v8-gyp-cross-build` became `s390x/v8-gyp-s390x-mksnapshot` + `ia32/v8-gyp-ia32-push-registers`).
See [Patch-format.md](Patch-format.md).

## `node-major.txt` — which upstream line to track

A one-line file naming the Node.js major (e.g. `24`). The build reads it, then
resolves the **newest upstream `v<MAJOR>.x` release** — a published tag, never a
branch head or a commit between releases. Bumping to a new major is a one-line edit;
the patch sections are re-verified against the new line and updated as needed.

## `.github/workflows/` and `releases/` — the build

`release-all.yml` is the whole build; `release-all-missing.yml` is a thin planner
that reuses it for a subset of platforms. The `releases/` scripts hold the two pieces
of logic both workflows share — the version resolution and the apply-map — so they
cannot drift. Neither workflow carries Node.js source. See
[How-the-build-works.md](How-the-build-works.md).

## What is NOT here

- **No Node.js source.** It is cloned from `github.com/nodejs/node` at the release
  tag each build.
- **No version directories.** The upstream version is resolved at build time from
  `node-major.txt`, not carried in `dist/`.
- **No built binaries in git.** They live on the GitHub Releases of this repo, one
  set per version, named `node-<platform>` / `node-<platform>.exe` with a
  `node-<platform>.sha256sum` each.
- **No translations.** Unlike the WeKan repo, this one has no `imports/i18n`.
