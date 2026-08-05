#!/usr/bin/env bash
# Print the upstream Node.js release to build: the NEWEST published release tag
# v<MAJOR>.<MINOR>.<PATCH> at nodejs/node, where <MAJOR> is read from
# node-major.txt. "Release" means a published tag - never a branch head, never a
# commit between releases - so a build is always of an upstream release and is
# reproducible.
#
# Usage:  newest-release.sh <repo-root> [version-override]
#
# A non-empty version-override (second argument) is printed verbatim instead of
# querying upstream. That is how release-all-missing.yml hands the reusable build
# the version its plan already resolved, so a full run and a fill-in run agree.
set -euo pipefail

ROOT="${1:-.}"
OVERRIDE="${2:-}"

if [ -n "$OVERRIDE" ]; then
  printf '%s\n' "$OVERRIDE"
  exit 0
fi

MAJOR="$(tr -cd '0-9' < "$ROOT/node-major.txt")"
[ -n "$MAJOR" ] || { echo "::error::$ROOT/node-major.txt has no major version number." >&2; exit 1; }

# Release tags only: --refs drops the ^{} dereference lines, and the strict grep
# drops anything that is not vMAJOR.MINOR.PATCH (no -rc, no other major line).
VERSION="$(git ls-remote --tags --refs https://github.com/nodejs/node.git "v${MAJOR}.*" \
  | awk '{print $2}' | sed 's#refs/tags/##' \
  | grep -E "^v${MAJOR}\.[0-9]+\.[0-9]+$" | sort -V | tail -1)"
[ -n "$VERSION" ] || { echo "::error::Found no upstream v${MAJOR}.x release tag at nodejs/node." >&2; exit 1; }

printf '%s\n' "$VERSION"
