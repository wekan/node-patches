#!/usr/bin/env bash
# Save a staged build's workspace for the next job (releases/build-openbsd.sh
# stopped gmake at its deadline and left .stage-partial).
#
# The whole workspace goes - the patched upstream tree, out/ and _patches -
# because make decides what to build from timestamps: a fresh clone would be
# newer than every object and everything would be compiled again. tar keeps
# the timestamps. .stage-env carries what the build step wrote to GITHUB_ENV
# (the version and commit the release names), which the next job's own clone
# step does not run to set.
set -euo pipefail
[ -f .stage-partial ] || { echo "::error::No .stage-partial: the build was not stopped at a deadline."; exit 1; }
printf 'VERSION=%s\nUPSTREAM_COMMIT=%s\n' "${VERSION:?}" "${UPSTREAM_COMMIT:?}" > .stage-env
# zstd on all cores; the artifact upload then stores it as it is.
#
# Written OUTSIDE the workspace, and moved in once it is complete: tar --zstd
# hands the output to zstd, which creates stage.tar.zst in . while tar is
# reading ., so GNU tar saw the directory change under it ("tar: .: file
# changed as we read it") and exited 1 - every openbsd-arm64 stage of v26.12.0
# stopped there, before anything was saved for the next one.
archive="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/stage.tar.zst"
rm -f "$archive" stage.tar.zst
tar --zstd -cf "$archive" .
mv "$archive" stage.tar.zst
ls -l stage.tar.zst
echo "STAGED_PARTIAL=true" >> "$GITHUB_ENV"
{
  echo "### Staged build saved"
  echo ""
  echo "The deadline came before the build finished; the next stage resumes it from $(du -sh out | cut -f1) of out/."
} >> "$GITHUB_STEP_SUMMARY"
