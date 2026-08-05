# How the build works

This repo carries no Node.js source. The build reconstructs the source at run time:
**clone upstream → verify → apply patches → build → publish**. Two workflows do it.

## Release All (`.github/workflows/release-all.yml`)

A `workflow_dispatch` (also callable as a reusable workflow) that builds one upstream
Node.js version for all thirteen platforms and uploads the binaries to that version's
GitHub Release.

1. **Pick the version.** The `version` input, or — when empty — the newest upstream
   `v<MAJOR>.x` release, where `MAJOR` is read from `node-major.txt`
   (`releases/newest-release.sh`). "Release" means a published tag, never a branch
   head or a commit between releases.
2. **Check out the patches** into `_patches/` (`actions/checkout`), keeping the repo's
   own files (the patch sections) separate from the Node.js tree about to be created.
3. **Clone upstream at the tag** — shallow, single branch — and move it into `$PWD`:
   ```sh
   git clone --depth 1 --single-branch --branch "$V" \
     https://github.com/nodejs/node.git nodesrc
   COMMIT="$(git -C nodesrc rev-parse HEAD)"   # the exact bytes built from
   mv nodesrc/* nodesrc/.git .   # $PWD is now an ordinary Node.js source tree
   ```
   `--branch "$V"` is the one release tag the patch set is for (the newest `v<MAJOR>.x`
   release), `--single-branch` fetches that ref and no other head, and `--depth 1`
   takes only the tag's commit with no history behind it — so the clone is the newest
   24.x release and nothing else. `$COMMIT` is recorded in the run summary and the
   release notes (see below), so every binary traces to the upstream source it was
   built from. From here every build step works in `$PWD` exactly as it would on a
   source fork — which is why the compile flags did not have to change when the source
   fork became a patch set.
4. **Verify and apply this platform's sections.** The apply-map
   (`releases/dist-dirs-for.sh`) names the `dist/` sections the target gets — `all`
   first, then its families — and each section's patches are checksum-verified and
   applied in filename order:
   ```sh
   for d in $(dist-dirs-for.sh "$PLATFORM"); do        # e.g. win32 -> all ia32 win32
     for p in _patches/dist/$d/*.patch; do
       ( cd _patches/dist/$d && sha256sum -c "$(basename "${p%.patch}").sha256sum" )
       git apply "$p"
     done
   done
   ```
   The checksum is verified **before** the patch is applied — a corrupted or
   hand-edited patch fails the build loudly instead of being applied wrong. A patch
   that does not apply cleanly to the pristine upstream tag also fails here, which is
   the signal to re-port it. No single build applies two sections that touch the same
   file, so order within a build never conflicts.
5. **Build** the platform (native, or cross with the per-platform flags the comments
   in the workflow explain — `--dest-cpu`, the V8 simulator for s390x mksnapshot,
   ClangCL for win32, and so on).
6. **Checksum and publish.** Each platform writes `node-<platform>.sha256sum` beside
   its binary, and both are uploaded with `gh release upload --clobber`. A release
   **accumulates**: a rebuilt platform overwrites only its own two assets; every other
   platform's binary is left in place, so all thirteen collect on one release across
   however many runs it takes. The release notes carry a **provenance table** — the
   upstream repo, the `v<MAJOR>.x` branch, the tag, and the exact commit — resolved
   from the tag with `git ls-remote` (immutable, so it matches what the build jobs
   cloned).

## Release All Missing (`.github/workflows/release-all-missing.yml`)

Building all thirteen to obtain one that failed is wasteful — several platforms take
hours. This workflow builds only what a release lacks:

1. **Plan.** List the release's assets and compare against the thirteen platforms. A
   platform counts as present only when BOTH `node-<platform>[.exe]` and
   `node-<platform>.sha256sum` are on the release, so a half-published platform is
   rebuilt rather than left broken.
2. **Build the missing set** by calling `release-all.yml` (a reusable workflow) with a
   `platforms` filter of exactly those. The build steps are not duplicated — a second
   copy of thirteen platforms' flags would drift.

It uses a **distinct concurrency group** from `release-all.yml`: a reusable workflow
that requests a group already held by its caller deadlocks. Mutual exclusion where it
matters still holds, because the actual build+upload happens inside `release-all.yml`,
which keeps its own group.

## Why build platforms nodejs.org already ships

Two reasons, spelled out in the workflow header:

- **The fixes.** The patch set carries build-configuration fixes (ICU, `/SAFESEH`,
  zlib flags) that any platform benefits from, and a bundle set should not be half
  built on patched Node.js and half on stock Node.js depending on the CPU.
- **The backstop.** A fallback only works if it covers everything. When nodejs.org or
  unofficial-builds has not published a version for a platform yet, this repo is what
  fills the gap — and it can only fill a gap it builds.

## Keeping up with upstream releases

Nothing to do for a new **patch** release of the same major: the build already
targets the newest `v<MAJOR>.x` release, so when upstream ships v24.20.0 the next run
clones and builds it against the existing sections — no version to type, no directory
to add. Only if a patch no longer applies to the newer release does the build fail, at
the `git apply` step, which is the signal to re-port that one patch.

To re-port a patch: clone upstream at the failing tag, apply the section, fix the
patch, regenerate it (`git diff` / `git format-patch`), recompute its `.sha256sum`,
update its `.md`, and add a CHANGELOG entry.

## Moving to a new major line

1. Edit `node-major.txt` (e.g. `24` → `26`).
2. Clone upstream at the new line's newest release and verify every section still
   applies; re-port what does not.
3. Recompute the changed `.sha256sum`s, update the `.md`s, add a CHANGELOG entry, and
   run **Release All** (no `version` → the newest release of the new major).

See [Patch-format.md](Patch-format.md) for the three-file convention.
