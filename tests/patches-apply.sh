#!/usr/bin/env bash
# Does every platform's patch set still apply to the upstream release the build
# would clone? That is the question this repo lives or dies on: a patch that no
# longer applies fails the build minutes in, on all fourteen platforms at once,
# and the only warning is a `git apply` error in a log nobody is watching.
#
#   ./tests/patches-apply.sh              # the newest upstream v<MAJOR>.x release
#   ./tests/patches-apply.sh v24.19.0     # a particular one
#
# It does NOT clone Node.js - that is a gigabyte to answer a question about
# twelve files. It reconstructs a tree of exactly the files the patches touch,
# fetched from nodejs/node at the tag, and runs `git apply` over it the way the
# workflow does: dist/all first, then the platform's family sections, in the
# apply-map's order, cumulatively, so a conflict WITHIN a platform's own set is
# caught as well as one against upstream.
#
# Needs the network. Exits 77 (the conventional "skipped") when nodejs/node
# cannot be reached, so a sandbox without network says so rather than reporting
# a green run it did not do.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW="https://raw.githubusercontent.com/nodejs/node"

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

command -v git >/dev/null || { echo "git is required."; exit 1; }
command -v curl >/dev/null || { echo "curl is required."; exit 1; }

# The version the workflow itself would build, resolved by the workflow's own
# script, so this test and the build never disagree about what "newest" is.
V="$(bash "$ROOT/releases/newest-release.sh" "$ROOT" "${1:-}" 2>/dev/null)"
if [ -z "${V:-}" ]; then
  echo "SKIP: could not resolve the newest upstream release (no network?)."
  exit 77
fi
echo "Upstream release: $V"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
git init -q .

# Which files the patches touch, straight out of their own headers. Derived
# rather than listed, so a patch that starts touching another file is fetched
# without anyone remembering to add it here. `/dev/null` is the a-side of a
# patch that CREATES a file - there is nothing upstream to fetch for it.
files="$(cat "$ROOT"/dist/*/*.patch | sed -n 's#^--- a/##p' | sort -u)"
[ -n "$files" ] || { echo "No patches found in $ROOT/dist."; exit 1; }

echo "Fetching the $(printf '%s\n' "$files" | wc -l | tr -d ' ') files the patches touch, at $V:"
for f in $files; do
  mkdir -p "$(dirname "$f")"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$f" "$RAW/$V/$f"; then
    if [ ! -s "$f" ] && ! curl -fsS --max-time 20 -o /dev/null "$RAW/$V/README.md" 2>/dev/null; then
      echo "SKIP: nodejs.org/github is unreachable."
      exit 77
    fi
    fail "upstream $V has no $f - the patch is against a file that is gone"
    rm -f "$f"
  fi
done
# The build applies the patches to a real checkout, where configure.py is
# executable. Mode matters to `git apply`: a mode mismatch is a warning, not an
# error, but matching upstream keeps the test's output honest.
[ -f configure.py ] && chmod +x configure.py
[ -f vcbuild.bat ] && chmod +x vcbuild.bat
git add -A
git -c user.email=t@t -c user.name=t commit -qm "upstream $V"
echo

# Every platform in the build matrix, through its own sections, exactly as the
# workflow's apply loop does it.
matrix="$(grep -E '^ +- platform: ' "$ROOT/.github/workflows/release-all.yml" | awk '{print $3}')"
for p in $matrix; do
  git checkout -q . && git clean -qfd
  dirs="$(bash "$ROOT/releases/dist-dirs-for.sh" "$p")"
  echo "$p (sections: $(printf '%s ' $dirs))"
  for d in $dirs; do
    for patch in "$ROOT/dist/$d"/*.patch; do
      [ -e "$patch" ] || continue
      n="$(basename "$patch")"
      # The checksum first, from inside the section directory - the same check,
      # in the same place, the workflow makes before it applies anything.
      if ! ( cd "$ROOT/dist/$d" && sha256sum -c "${n%.patch}.sha256sum" >/dev/null 2>&1 ); then
        fail "$d/$n: checksum does not match the patch"
        continue
      fi
      if err="$(git apply --whitespace=nowarn "$patch" 2>&1)"; then
        ok "$d/$n"
      else
        fail "$d/$n does not apply to $V: $(printf '%s' "$err" | head -3 | tr '\n' ' ')"
      fi
    done
  done
done
git checkout -q . && git clean -qfd

echo
if [ "$fails" -eq 0 ]; then
  echo "patches-apply: every section applies to $V."
else
  echo "patches-apply: $fails failure(s) against $V."
fi
exit $(( fails > 0 ))
