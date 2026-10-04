#!/usr/bin/env bash
# Attach one build's files to a GitHub Release, the moment that build is done.
#
#   upload-release-assets.sh <tag> <file>...
#
# Called as the LAST step of every build job in .github/workflows/release-all.yml
# (and so of every release-all-missing.yml run, which calls that workflow), so a
# platform's node-<platform> binary is downloadable as soon as it is built and
# checked, not when the slowest of the sixteen platforms finishes.
#
# - --clobber: a rebuilt platform replaces its own old asset; every other asset
#   on the release is left alone, so a release still ACCUMULATES.
# - Binaries first, .sha256sum files last. A checksum on the release therefore
#   always means its binary is there too, which is the "present" test
#   release-all-missing.yml and the publish job apply.
# - Each upload is retried, and then CHECKED: the asset must be on the release
#   with the same size as the local file. An API hiccup is retried rather than
#   costing an hours-long build its upload.
#
# Needs GH_TOKEN, and GH_REPO (or GITHUB_REPOSITORY) naming THIS repository: the
# build job's workspace root is an upstream nodejs/node clone, and gh would
# otherwise take the repository from that clone's remote.
#
# Bash 3.2 compatible (the macOS runners), so no empty-array expansions under
# `set -u`.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <tag> <file>..." >&2
  exit 2
fi
tag="$1"; shift

GH_REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
if [ -z "$GH_REPO" ]; then
  echo "::error::GH_REPO (or GITHUB_REPOSITORY) must name the repository to upload to." >&2
  exit 2
fi
export GH_REPO

attempts="${UPLOAD_ATTEMPTS:-5}"
delay="${UPLOAD_RETRY_DELAY:-15}"

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "::error::$f does not exist - nothing to attach for it." >&2
    exit 1
  fi
done

# Binaries (and the .lib) before checksums.
ordered=""
for f in "$@"; do case "$f" in *.sha256sum) ;; *) ordered="$ordered $f" ;; esac; done
for f in "$@"; do case "$f" in *.sha256sum) ordered="$ordered $f" ;; esac; done

file_size() { wc -c < "$1" | tr -d ' '; }

for f in $ordered; do
  name="$(basename "$f")"
  want="$(file_size "$f")"
  n=1
  while :; do
    if gh release upload "$tag" "$f" --clobber; then
      got="$(gh release view "$tag" --json assets \
        --jq ".assets[] | select(.name == \"$name\") | .size" 2>/dev/null || true)"
      if [ "$got" = "$want" ]; then
        echo "Attached $name ($want bytes) to $tag."
        break
      fi
      echo "::warning::$name is on $tag with size '${got:-none}', expected $want."
    fi
    if [ "$n" -ge "$attempts" ]; then
      echo "::error::Could not attach $name to $tag after $attempts attempts." >&2
      exit 1
    fi
    echo "Retrying $name in $((n * delay))s (attempt $((n + 1)) of $attempts)."
    sleep $((n * delay))
    n=$((n + 1))
  done
done
