# CLAUDE.md — instructions Claude reads first

Claude Code reads this file at the repo root before doing work here. Follow it.

This repository (github.com/wekan/node-patches) carries **only patches** to upstream
Node.js — no Node.js source. It is modelled on
[Betterbird/thunderbird-patches](https://github.com/Betterbird/thunderbird-patches):
CI clones upstream Node.js at a tag, applies the patches, and publishes the built
binaries. WeKan embeds those binaries. The old `wekan/node` source fork is being
retired in favour of this repo, so a change that used to be a commit on the fork is
now a patch here.

## First: are you the maintainer or a contributor?

Check the current git identity before committing:

```
git config user.name && git config user.email
```

- **Maintainer mode** — ONLY when the identity is exactly
  `Lauri Ojansivu <x@xet7.org>`. Then, and only then: commit **directly to the
  current branch** as `Lauri Ojansivu <x@xet7.org>` with no AI trailer and no pull
  request, and the release step below is available. Per the standing rule you still
  **commit only; do not push** unless explicitly asked.
- **Contributor mode** — any other git identity. Then: do **not** commit directly and
  do **not** run the release step. Make changes on a branch and open a **pull
  request** for the maintainer to review.

## What is in this repo

```
node-patches/
  CHANGELOG.md                 wekan-style changelog (see below)
  CLAUDE.md                    this file
  node-major.txt               the Node.js major line to track (e.g. 24)
  .github/workflows/
    release-all.yml            clone upstream, apply patches, build 14 platforms, publish
    release-all-missing.yml    build only the binaries a release does not yet carry
  releases/
    newest-release.sh          resolve the newest upstream v<MAJOR>.x release
    dist-dirs-for.sh           the apply-map: platform -> dist/ sections
  tests/
    workflow-logic.sh          offline: runs the workflows' own shell blocks
    patches-apply.sh           network: applies every section to upstream
  dist/
    README.md                  the sections and the apply-map, in prose
    all/                       common: applied to EVERY platform
    ia32/ arm/ s390x/ mac/ win32/   family/platform sections
      <name>.patch             the code patch (git apply / git format-patch style)
      <name>.sha256sum         sha256 of <name>.patch, checked before applying
      <name>.md                what the patch does, wekan-changelog style
  docs/Design/                 how the repo is laid out and how the build works
```

See [docs/Design/Directory-structure.md](docs/Design/Directory-structure.md) for the
full layout, [dist/README.md](dist/README.md) for the sections and apply-map, and
[docs/Design/How-the-build-works.md](docs/Design/How-the-build-works.md) for the
clone→verify→apply→build→publish flow.

## Working on the patches

Patches are organised by **platform**, not by version: a **common** `all/` section
plus **family/platform** sections (`ia32/`, `arm/`, `s390x/`, `mac/`, `win32/`). Every
build applies `dist/all` plus the sections the apply-map
([releases/dist-dirs-for.sh](releases/dist-dirs-for.sh)) assigns its target. The
upstream version is resolved separately — the newest `v<MAJOR>.x` release, where
`MAJOR` is in `node-major.txt` — so the sections carry forward across upstream
releases. The rules:

- **One patch = three files** with the same base name: `<name>.patch`,
  `<name>.sha256sum`, `<name>.md`. All three are required; a workflow that finds a
  `.patch` without a matching `.sha256sum` fails the build (the checksum is verified
  before the patch is applied), and a `.md` documents it for the changelog and for
  the next reader.
- **Put a patch in the most specific section** that covers every platform it affects:
  every platform → `all/`; a family (32-bit x86, 32-bit ARM, Apple Clang) → `ia32/`,
  `arm/`, `mac/`; one platform → `s390x/`, `win32/`. A change spanning families is
  **split by hunk** into each family's section (no single build applies two sections
  that touch the same file). Keep the apply-map in step with the build matrix.
- **Group by logical change, not by file.** A patch may touch several files if they
  are one change (the 32-bit Windows patch touches seven). Name it for what it does
  (`32bit-windows-build`, `zlib-sse2`), not for a file.
- **Generate a patch** from a source tree that has upstream at the tag as its base:
  `git diff v24.19.0..HEAD -- <paths>` (or `git format-patch`). Keep each patch
  applying cleanly to a **pristine upstream checkout** — that is what CI applies it
  to. Verify by cloning upstream at the tag and `git apply`-ing the section's patches.
- **Recompute the checksum whenever the patch changes:**
  `sha256sum <name>.patch > <name>.sha256sum` (run it in the section directory so the
  file records the bare name, which is how CI checks it). A stale checksum fails the
  build.
- **Write the `.md` in wekan-changelog style:** a `# <name>` title, a one-line
  summary, the body (what was wrong, what it does now), then `**Files:**`,
  `**Platforms:**` and `**Applies to:**`. It is the source for the CHANGELOG entry.
- **A new upstream patch release needs nothing** — the build already targets the
  newest `v<MAJOR>.x` release. Only re-port a patch if `git apply` fails on the newer
  release. A new **major** is a one-line edit to `node-major.txt`, then re-verify and
  re-port the sections.

Fix from source and verify — do not guess. If this environment cannot run a full
14-platform build, reconstruct the source from upstream + patches and say clearly what
was and was not verified.

## Tests

Two scripts, and both run here — a 14-platform build does not, so these check
what can be checked without one:

- `./tests/workflow-logic.sh` — no network. It EXTRACTS the shell blocks out of
  `release-all.yml` and runs them, rather than restating them, so a passing test
  means the workflow's own lines behave. It also checks the three platform lists
  agree, that the apply-map answers for every platform in the build matrix, that
  every patch is a complete checksummed trio, and that no build applies two
  sections touching one file. Run it after ANY workflow edit: the first run's
  failure — all thirteen builds of the day (armv6 makes fourteen now) dead three
  seconds in, on a `mv` that could never work — is exactly what it now catches in
  a second.
- `./tests/patches-apply.sh [version]` — needs the network. It reconstructs the
  files the patches touch from upstream at the resolved release and `git apply`s
  each platform's sections cumulatively, checksum first, the same way the build
  does. It does not clone Node.js (a gigabyte to answer a question about twelve
  files) and exits 77 when upstream is unreachable, so a sandbox with no
  network says so instead of reporting a green run it did not do.

## CHANGELOG

`CHANGELOG.md` uses the **same formatting as the WeKan repo's CHANGELOG** — read that
file for the canonical rules; the shape here is identical, only the subject differs.
In short:

- The file's shape, top to bottom: `# Platforms` (the links block and a `<details>`
  summarised `Version`), then `# TODO Later` (a `<details>` per category of things
  investigated but not done), then the releases newest first, each
  `# v<x> YYYY-MM-DD node-patches release`. Nothing else is an `#` heading — a `##`
  inside a release, or a wrapped line beginning with `#`, would become one; escape a
  leading `#NNNN` as `\#NNNN`.
- During development, add entries under a new `# Upcoming node-patches release`
  section above the newest release. Do **not** hand-edit version references — the
  release step bumps those.
- The Upcoming section opens with an `**In short:**` paragraph summarising the whole
  release, notable names in `**bold**`.
- Every entry is a `<details>` block whose `<summary>` is on ONE line, ≤110 chars,
  plain text (no links/bold/backticks inside `<summary>`), ending with a full stop
  then `Thanks to …`. The commit hash lives in the `href`, never as link text. A
  blank line under the summary, the word-wrapped-at-80 body, a blank line, the close,
  and a blank line between blocks.
- Multi-entry subsections are **grouped by area** with a `**Area** - description.`
  label line (on ONE physical line, ending in a period) above each group; every entry
  under it drops the area prefix. A single-entry subsection stays flat.
- Subsection headers read as one flowing sentence: the first starts with
  `This release `, every later one with a lowercase `and `. The release ends with
  `Thanks to above GitHub users for their contributions.`
- Word-wrap at 80 chars, but never break a link across lines. Never show a long URL
  as visible text — `[#NNNN](…)`, `[short text](url)`.

There is no translation workflow in this repo — that section of the WeKan CLAUDE.md
does not apply here.

## Commit message structure

```
Do something.

Thanks to (original creator of issue, if any) and xet7 !

Fixes #1234,
```

Commit as `Lauri Ojansivu <x@xet7.org>` (maintainer only), with **no**
"Co-Authored-By" or any other AI trailer, directly to `main`. **Do not make pull
requests** (contributors do the opposite). **Commit only. Do not push** unless
explicitly asked.

## Making a release  **[maintainer only]**

- Run **Release All** (`.github/workflows/release-all.yml`, `workflow_dispatch`) with
  no `version` input to build the newest upstream `v<MAJOR>.x` release (from
  `node-major.txt`), or `-f version=v24.19.0` to pin one. It clones upstream at that
  release tag, verifies+applies each platform's sections, builds the fourteen
  platforms, and uploads each `node-<platform>` binary and its `.sha256sum` to the
  release, accumulating (a rebuilt platform clobbers only its own asset).
- Run **Release All Missing** to fill in only the platforms a release does not yet
  carry — it plans what is absent, then calls Release All for exactly those. Use it
  when a platform failed or was added after the rest were published.
- The publishing steps are **maintainer-only**. Contributors never run them.

## Environment

The editor (VSCode) runs inside a Flatpak sandbox (see the WeKan repo's
`docs/Security/Sandboxes/vscode/README.md`). A full Node.js build does not run in the
sandbox; verify patches by reconstructing the source from upstream + patches and say
what was and was not verified.

### Always validate from the actual code

When doing anything, check how it actually works in the code and the workflows first.
