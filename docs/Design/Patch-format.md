# Patch format

Patches live in **section** directories under `dist/` — `all/` and the
family/platform sections (`ia32/`, `arm/`, `s390x/`, `mac/`, `win32/`). Which section
a patch belongs in is set by the platforms it affects; see
[Directory-structure.md](Directory-structure.md) and
[`dist/README.md`](../../dist/README.md) for the sections and the apply-map.

Every patch is **three files sharing a base name**. The base name is the logical
change, kebab-case: `32bit-windows-build`, `zlib-sse2`, `s390-simulator-const-cast`.
All three files are required — the workflow fails a build that finds a `.patch`
without a matching `.sha256sum`.

```
dist/win32/
  32bit-windows-build.patch       the code change
  32bit-windows-build.sha256sum   sha256 of the .patch, verified before applying
  32bit-windows-build.md          what the patch does
```

## Which section?

Put a patch in the **most specific** section that covers every platform it affects:

- affects **every** platform, or is a harmless portable fix → `all/`;
- affects one **family** (32-bit x86, 32-bit ARM, Apple Clang) → `ia32/`, `arm/`,
  `mac/`;
- affects one **platform** → `s390x/`, `win32/`.

A change that spans families is **split by hunk** into each family's section, so a
build only ever applies the hunks its target needs. The former `v8-gyp-cross-build`
(one file, s390x hunks + an ia32 hunk) became `s390x/v8-gyp-s390x-mksnapshot` +
`ia32/v8-gyp-ia32-push-registers`; the former `zlib-simd` became `arm/zlib-neon` +
`ia32/zlib-sse2`. Split by taking whole hunks: keep each hunk's `@@` header and body
verbatim, drop the `index` line, and `git apply` each part against a pristine tree to
confirm it still applies. No single build may apply two sections that touch the same
file.

## `<name>.patch`

The code change, as `git diff` or `git format-patch` output, applying cleanly with
`git apply` to a **pristine upstream checkout** of the tracked release. That is what
CI applies it to, so verify it there — clone upstream at the tag and `git apply` the
patch (and every other patch its build would apply).

- **Group by logical change, not by file.** One patch may touch several files if they
  are one change: `32bit-windows-build` touches `configure.py`, `common.gypi`,
  `node.gyp`, `src/node_metadata.cc`, `toolchain.gypi`, `vcbuild.bat` and
  `BUILDING.md` because they are one concern — restoring the 32-bit Windows build.
- **Generate from a tree based on the upstream tag.** If you keep a working branch
  with upstream at the tag as its base, `git diff v24.19.0..HEAD -- <paths>` gives the
  patch. `git format-patch` works too; either applies with `git apply`.
- **CRLF:** upstream Windows-touching files (e.g. `vcbuild.bat`) are CRLF. `git apply`
  preserves the upstream line endings for context lines, so a patch authored from an
  LF working copy still applies — the content is what matters, not the author's EOL.

## `<name>.sha256sum`

```sh
cd dist/win32 && sha256sum 32bit-windows-build.patch > 32bit-windows-build.sha256sum
```

Run it **in the section directory** so the file records the bare name
(`<hash>  32bit-windows-build.patch`), which is how CI checks it (`sha256sum -c`).
Recompute it **whenever the patch changes** — a stale checksum fails the build, which
is the point: it makes a silently-edited patch impossible.

## `<name>.md`

What the patch does, in the WeKan CHANGELOG style, so it can be lifted into
`CHANGELOG.md`:

```markdown
# <name>

One-line summary of what the patch restores or fixes.

The body: what was wrong upstream, why, and what the patch does now — as much detail
as the change deserves, word-wrapped at 80. Link upstream issues/PRs as
[nodejs/node#NNNNN](https://github.com/nodejs/node/pull/NNNNN).

**Files:** `path/one`, `path/two`
**Platforms:** win32 (`dist/win32/`).
**Applies to:** upstream Node.js 24.x (verified against `v24.19.0`).
```

The `**Platforms:**` line names the section and the platforms it reaches; the
`**Applies to:**` line names the upstream version the patch is verified against —
update it when re-porting to a newer release or major.

## The sections as a whole

| Section | Patch | What it does |
|---------|-------|--------------|
| `all/` | `v8-turboshaft-template-disambiguator` | Explicit `template` disambiguator a stricter compiler needs. |
| `ia32/` | `v8-gyp-ia32-push-registers` | Selects V8's ia32 `push_registers_asm.cc`. |
| `ia32/` | `zlib-sse2` | `-msse2` for zlib SIMD on 32-bit x86. |
| `ia32/` | `icu-cross-build` | Maps ia32→x86 for the ICU `genccode` host tool. |
| `arm/` | `zlib-neon` | `-mfpu=neon` for zlib SIMD on 32-bit ARM; ARMv8 CRC kept off ARMv7. |
| `s390x/` | `v8-gyp-s390x-mksnapshot` | s390x mksnapshot forced single-threaded under the V8 simulator. |
| `s390x/` | `s390-simulator-const-cast` | Const-cast so the s390 simulator compiles. |
| `mac/` | `crypto-kmac-aggregate-init` | KMAC brace initialiser Apple Clang accepts. |
| `win32/` | `32bit-windows-build` | Restores the 32-bit Windows build upstream removed in Node 23. |

These are documented once more, for readers of the release notes, in
[../../CHANGELOG.md](../../CHANGELOG.md).
