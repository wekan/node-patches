#!/usr/bin/env bash
# What the release workflows do, checked WITHOUT a runner and without the
# network. The build itself takes hours on thirteen platforms, so the failures
# worth catching here are the ones that kill a job in its first seconds - and
# that is exactly what the first run's failure was: every one of the thirteen
# builds died three seconds after cloning, on a `mv` that could never work, and
# nothing was published.
#
# The point of this file is that it does not RE-WRITE the workflow's shell in a
# test and then check the copy. It EXTRACTS the real blocks out of
# release-all.yml and runs those, so a test passing means the workflow's own
# lines behave - and an edit that breaks them fails here rather than on a
# runner two hours later.
#
#   ./tests/workflow-logic.sh
#
# Exit 0 when everything holds, 1 with the failures listed at the end.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL="$ROOT/.github/workflows/release-all.yml"
MISSING="$ROOT/.github/workflows/release-all-missing.yml"

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 1. Moving the upstream tree into the workspace ────────────────────────────
#
# The build clones nodejs/node into nodesrc/ and then moves that tree up beside
# _patches/, because every build step works in $PWD. `shopt -s dotglob` makes
# `nodesrc/*` include the dotfiles - .git among them - so the glob moves the
# WHOLE tree.
#
# The first run's bug was a second, explicit `mv nodesrc/.git .` after it. The
# glob had already taken .git, so mv answered "cannot stat 'nodesrc/.git': No
# such file or directory" and `set -e` ended the step. Thirteen jobs, one line.
echo "The upstream tree is moved into the workspace root:"

# The real block, out of the real workflow - from the dotglob to the guard that
# checks .git arrived. Extracting rather than retyping is the whole point: this
# runs the workflow's lines, not a paraphrase of them.
# `set -euo pipefail` on top and run with `bash`, NOT sourced: the step runs
# under those options on the runner, and a sourced script inside an `&&` list
# has -e suppressed for it - which is how the first draft of this test watched
# the old bug "pass".
{ echo 'set -euo pipefail'
  sed -n '/^          shopt -s dotglob$/,/^          \[ -d \.git \]/p' "$ALL" \
    | sed 's/^          //'
} > "$TMP/move.sh"
if [ -s "$TMP/move.sh" ] && grep -q 'mv nodesrc/\*' "$TMP/move.sh" \
   && grep -q 'rmdir nodesrc' "$TMP/move.sh"; then
  ok "the move block was found in release-all.yml"
else
  fail "could not extract the move block from release-all.yml (did its indentation or wording change?)"
fi

# A workspace shaped like the runner's: the patches checkout in _patches/, the
# cloned upstream tree in nodesrc/, dotfiles and all.
fabricate() {
  rm -rf "$TMP/ws"
  mkdir -p "$TMP/ws/_patches/dist/all" \
           "$TMP/ws/nodesrc/.git/refs" \
           "$TMP/ws/nodesrc/deps/v8" \
           "$TMP/ws/nodesrc/.github/workflows"
  touch "$TMP/ws/nodesrc/configure" "$TMP/ws/nodesrc/.gitignore" \
        "$TMP/ws/nodesrc/node.gyp" "$TMP/ws/nodesrc/.git/HEAD"
}

fabricate
if ( cd "$TMP/ws" && bash "$TMP/move.sh" ) >"$TMP/move.log" 2>&1; then
  ok "it succeeds on a freshly cloned tree"
else
  fail "it failed on a freshly cloned tree: $(tail -1 "$TMP/move.log")"
fi
[ -d "$TMP/ws/.git" ]        && ok "the upstream .git ends up at the workspace root" \
                             || fail ".git did not reach the workspace root"
[ -f "$TMP/ws/configure" ]   && ok "so do the ordinary files" \
                             || fail "configure did not reach the workspace root"
[ -f "$TMP/ws/.gitignore" ]  && ok "so do the other dotfiles" \
                             || fail ".gitignore did not reach the workspace root (dotglob off?)"
[ -d "$TMP/ws/_patches" ]    && ok "the patches checkout is left where it was" \
                             || fail "_patches was disturbed by the move"
[ ! -e "$TMP/ws/nodesrc" ]   && ok "nodesrc is gone, so nothing was left behind" \
                             || fail "nodesrc survived the move - part of the tree is still in it"

# NEGATIVE: put the removed line back and the block must fail. Without this the
# test above would still pass if the bug returned in some other form; this is
# what proves the test can tell the two apart.
fabricate
sed 's#^mv nodesrc/\* \.$#mv nodesrc/* .\nmv nodesrc/.git .#' "$TMP/move.sh" > "$TMP/move-bug.sh"
if ( cd "$TMP/ws" && bash "$TMP/move-bug.sh" ) >/dev/null 2>&1; then
  fail "the old double-move did NOT fail - this test would not catch the regression"
else
  ok "re-adding the old second 'mv nodesrc/.git .' fails, as it did on the runner"
fi

# And statically, because the line is unmistakable. Comment lines are dropped
# first - the step's own comments explain the bug and say the line out loud.
if grep -vE '^\s*#' "$ALL" | grep -q 'mv nodesrc/\.git'; then
  fail "release-all.yml moves nodesrc/.git a second time - dotglob already moved it"
else
  ok "release-all.yml does not move .git twice"
fi

# ── 2. Which platforms the release notes say it carries ───────────────────────
#
# The publish job turns the downloaded artifacts back into a list of platforms.
# Everything in dist/ is an asset, so the filter has to drop what is NOT a
# platform binary: the .sha256sum files, and the Windows .lib import library,
# which otherwise became a platform of its own called `win32.lib`.
echo
echo "The publish job's asset list is turned into platform names:"

sed -n '/^          present="\$(/,/sort -u)"/p' "$ALL" | sed 's/^          //' > "$TMP/present.sh"
if grep -q 'sort -u' "$TMP/present.sh"; then
  ok "the filter was found in release-all.yml"
else
  fail "could not extract the asset filter from release-all.yml"
fi

rm -rf "$TMP/pub"; mkdir -p "$TMP/pub/dist"
( cd "$TMP/pub/dist" && touch \
    node-x64 node-x64.sha256sum \
    node-mac-arm64 node-mac-arm64.sha256sum \
    node-win32.exe node-win32.sha256sum node-win32.lib node-win32.lib.sha256sum )
got="$( cd "$TMP/pub" && . "$TMP/present.sh" && printf '%s\n' "$present" | tr '\n' ' ' )"
want="mac-arm64 win32 x64 "
if [ "$got" = "$want" ]; then
  ok "binaries become platforms, checksums and the .lib do not"
else
  fail "expected platforms [$want] but got [$got]"
fi
case " $got " in *" win32.lib "*) fail "the Windows import library is still counted as a platform" ;;
                 *) ok "node-win32.lib is not a platform called win32.lib" ;; esac

# ── 3. The three platform lists have to agree ─────────────────────────────────
#
# The build matrix is the truth; release-all-missing.yml repeats the list to
# work out what a release lacks, and the publish job repeats it to order the
# names in the notes. A platform added to one and not the others is either never
# noticed as missing or never named in the notes, and neither says so out loud.
echo
echo "Every list of platforms names the same platforms:"

matrix="$(grep -E '^ +- platform: ' "$ALL" | awk '{print $3}' | sort -u)"
missing_list="$(grep -E '^ +PLATFORMS="' "$MISSING" | sed 's/.*PLATFORMS="//; s/".*//' | tr ' ' '\n' | sed '/^$/d' | sort -u)"
notes_list="$(grep -E '^ +for a in x64 ' "$ALL" | head -1 | sed 's/.*for a in //; s/; do.*//' | tr ' ' '\n' | sed '/^$/d' | sort -u)"

[ -n "$matrix" ] && ok "the build matrix lists $(printf '%s\n' "$matrix" | wc -l | tr -d ' ') platforms" \
                 || fail "found no platforms in the build matrix"
[ "$matrix" = "$missing_list" ] \
  && ok "release-all-missing.yml's PLATFORMS matches the matrix" \
  || fail "release-all-missing.yml's PLATFORMS differs from the matrix: $(diff <(echo "$matrix") <(echo "$missing_list") | tr '\n' ' ')"
[ "$matrix" = "$notes_list" ] \
  && ok "the release notes' platform order covers the matrix" \
  || fail "the release notes' platform list differs from the matrix: $(diff <(echo "$matrix") <(echo "$notes_list") | tr '\n' ' ')"

# ── 4. The apply-map answers for every platform ───────────────────────────────
echo
echo "The apply-map covers the matrix:"
for p in $matrix; do
  dirs="$(bash "$ROOT/releases/dist-dirs-for.sh" "$p" 2>/dev/null)"
  if [ -z "$dirs" ]; then fail "dist-dirs-for.sh says nothing for $p"; continue; fi
  [ "$(printf '%s\n' "$dirs" | head -1)" = "all" ] \
    || fail "$p does not get dist/all first"
  bad=""
  for d in $dirs; do [ -d "$ROOT/dist/$d" ] || bad="$bad $d"; done
  [ -z "$bad" ] && ok "$p -> $(printf '%s ' $dirs)" \
                || fail "$p maps to section(s) that do not exist:$bad"
done

# ── 5. One patch is three files, and the checksum is the one CI verifies ──────
#
# The build reads the recorded hash out of <name>.sha256sum before applying, and
# the file is written from inside the section directory, so it records the BARE
# name. A stale checksum fails the build after the clone.
echo
echo "Every patch is a complete, checksummed, documented trio:"
for p in "$ROOT"/dist/*/*.patch; do
  [ -e "$p" ] || continue
  d="$(dirname "$p")"; n="$(basename "$p" .patch)"; rel="$(basename "$d")/$n"
  miss=""
  [ -f "$d/$n.sha256sum" ] || miss="$miss .sha256sum"
  [ -f "$d/$n.md" ]        || miss="$miss .md"
  if [ -n "$miss" ]; then fail "$rel is missing:$miss"; continue; fi
  grep -q "  $n.patch\$" "$d/$n.sha256sum" \
    || fail "$rel.sha256sum does not name the bare file '$n.patch' (CI checks it from inside the section)"
  if ( cd "$d" && sha256sum -c "$n.sha256sum" >/dev/null 2>&1 ); then
    ok "$rel"
  else
    fail "$rel checksum does not match the patch - recompute it in the section directory"
  fi
done

# ── 6. No build applies two sections that touch one file ──────────────────────
#
# The sections are applied one after another with plain `git apply`, in the
# order the apply-map prints them, so two SECTIONS editing the same file in one
# build would conflict on a runner and nowhere else. (Two patches inside one
# section are the section author's business - they are applied in name order and
# are meant to stack.)
echo
echo "No platform applies two sections that touch the same file:"
for p in $matrix; do
  clash=""
  seen=""
  for d in $(bash "$ROOT/releases/dist-dirs-for.sh" "$p"); do
    files="$(cat "$ROOT/dist/$d"/*.patch 2>/dev/null | sed -n 's#^--- a/##p' | sort -u)"
    for f in $files; do
      case " $seen " in *" $f "*) clash="$clash $d:$f" ;; esac
    done
    seen="$seen $files"
  done
  [ -z "$clash" ] && ok "$p" || fail "$p applies two sections touching:$clash"
done

# ── 7. Nothing may rewrite a patch's bytes on checkout ────────────────────────
#
# This is what killed BOTH Windows builds of the second run, seconds in. Git for
# Windows checks text files out with CRLF, so win64 and win32 got .sha256sum
# files with a trailing carriage return and the checksum step answered
#
#   sha256sum: 'v8-turboshaft-template-disambiguator.patch'$'\r': No such file
#   ##[error]Process completed with exit code 1.
#
# The .patch files had been converted too, so the `git apply` after it would have
# failed on its own. .gitattributes marks both kinds -text, and the build's
# checksum check no longer cares about a stray CR either.
echo
echo "Patches and checksums are checked out byte-exact:"

GA="$ROOT/.gitattributes"
if [ -f "$GA" ]; then
  ok ".gitattributes exists"
  grep -qE '^\*\.patch[[:space:]]+-text' "$GA" \
    && ok "*.patch is -text, so no checkout converts it" \
    || fail "*.patch is not marked -text in .gitattributes - a Windows checkout will CRLF it"
  grep -qE '^\*\.sha256sum[[:space:]]+-text' "$GA" \
    && ok "*.sha256sum is -text too" \
    || fail "*.sha256sum is not marked -text in .gitattributes - the checksum step will read a filename ending in CR"
else
  fail "there is no .gitattributes - a Windows checkout will CRLF the patches (this is the second run's win64/win32 failure)"
fi

# And the build's own check, extracted and run: it must accept a checksum file
# with CRLF and still reject a wrong hash. Belt and braces, because the braces
# (.gitattributes) only help a checkout that happens after this commit.
{ echo 'set -euo pipefail'
  sed -n '/^              want="\$(awk/,/^              fi$/p' "$ALL" | sed 's/^              //'
} > "$TMP/verify.sh"
if grep -q 'sha256sum "\$p"' "$TMP/verify.sh"; then
  ok "the checksum check was found in release-all.yml"
else
  fail "could not extract the checksum check from release-all.yml (did its indentation or wording change?)"
fi

mkdir -p "$TMP/sec"
printf 'a patch\n' > "$TMP/sec/x.patch"
sum="$(sha256sum "$TMP/sec/x.patch" | awk '{print $1}')"
printf '%s  x.patch\r\n' "$sum" > "$TMP/sec/x.sha256sum"    # CRLF, as Windows checks it out
if ( cd "$TMP" && dir="sec" n="x.patch" p="sec/x.patch" bash "$TMP/verify.sh" ) >/dev/null 2>&1; then
  ok "a CRLF checksum file still verifies"
else
  fail "a CRLF checksum file fails the build - the win64/win32 failure would come back"
fi
printf 'deadbeef  x.patch\n' > "$TMP/sec/x.sha256sum"
if ( cd "$TMP" && dir="sec" n="x.patch" p="sec/x.patch" bash "$TMP/verify.sh" ) >/dev/null 2>&1; then
  fail "a WRONG checksum passed - the check verifies nothing"
else
  ok "a wrong checksum still fails"
fi

# ── 8. Only a platform that is meant to be best-effort is one ────────────────
#
# `continue-on-error` on a matrix entry means a failure of that platform does not
# fail the workflow. That is right for s390x - the only big-endian target, built
# with a real mksnapshot under qemu-user (cross-qemu mode), which is unproven
# until a run confirms it, and nodejs.org publishes linux-s390x anyway - and
# wrong for anything else, because a platform that quietly stops building is a
# platform nobody notices is gone.
echo
echo "Best-effort is a per-platform decision, and only s390x makes it:"
grep -q 'continue-on-error: \${{ matrix.best_effort == true }}' "$ALL" \
  && ok "the job is best-effort only when its matrix entry says so" \
  || fail "release-all.yml does not gate continue-on-error on matrix.best_effort"
be="$(grep -B 40 -E '^ +best_effort: true' "$ALL" | grep -E '^ +- platform: ' | tail -1 | awk '{print $3}')"
count="$(grep -cE '^ +best_effort: true' "$ALL")"
[ "$count" = "1" ] && [ "$be" = "s390x" ] \
  && ok "s390x is the only best-effort platform" \
  || fail "expected s390x to be the only best-effort platform, found $count marked (last: ${be:-none})"

# ── 9. Every shell block in both workflows is valid shell ─────────────────────
#
# The s390x build died three seconds in with
#
#     line 41: unexpected EOF while looking for matching `"'
#
# and published nothing. The cause was one character: the whole cross-compile
# body is a single-quoted `sh -c '...'` argument, and a verification line inside
# it read `grep -q "want_separate_host_toolset': 0"`. That apostrophe ENDS the
# single-quoted argument - there is no escaping a single quote from within one -
# so the rest of the script was parsed as something else entirely.
#
# Nothing in this file would have caught it, because the checks above read what
# the blocks DO. This one only asks whether bash can parse them at all, which is
# the cheapest possible test and would have failed on that line immediately.
#
# ${{ ... }} expressions are substituted first, the way Actions does before the
# shell ever sees the script; the value does not matter, only that a placeholder
# does not itself break the quoting.
for wf in "$ALL" "$MISSING"; do
  name="$(basename "$wf")"
  blocks="$TMP/shellblocks-$name"
  rm -rf "$blocks"; mkdir -p "$blocks"
  python3 - "$wf" "$blocks" <<'PYEOF'
import re, sys, yaml
wf, outdir = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(wf))
n = 0
for job_name, job in (doc.get('jobs') or {}).items():
    for step in job.get('steps') or []:
        if not isinstance(step, dict) or not step.get('run'):
            continue
        # A run: block for a non-shell shell (python, pwsh) is not ours to parse.
        if step.get('shell') and 'sh' not in str(step['shell']):
            continue
        script = re.sub(r'\$\{\{[^}]*\}\}', 'PLACEHOLDER', step['run'])
        n += 1
        label = re.sub(r'[^A-Za-z0-9]+', '-', '%s--%s' % (job_name, step.get('name', 'step%d' % n)))[:80]
        open('%s/%03d-%s.sh' % (outdir, n, label), 'w').write(script)
PYEOF
  bad=0
  for f in "$blocks"/*.sh; do
    [ -e "$f" ] || continue
    if ! err="$(bash -n "$f" 2>&1)"; then
      fail "$name: $(basename "$f") is not valid shell: $(printf '%s' "$err" | head -1)"
      bad=$((bad+1))
    fi
  done
  [ "$bad" -eq 0 ] && ok "$name: every run: block parses as shell"
done

echo
if [ "$fails" -eq 0 ]; then
  echo "workflow-logic: everything holds."
else
  echo "workflow-logic: $fails check(s) FAILED."
fi
exit $(( fails > 0 ))
