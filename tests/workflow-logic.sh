#!/usr/bin/env bash
# What the release workflows do, checked WITHOUT a runner and without the
# network. The build itself takes hours on sixteen platforms, so the failures
# worth catching here are the ones that kill a job in its first seconds - and
# that is exactly what the first run's failure was: every one of the builds -
# thirteen of them at the time, fourteen since armv6 - died three seconds after
# cloning, on a `mv` that could never work, and
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
# The publish job reads the RELEASE's asset names (every build attaches its own
# files) and turns them back into a list of platforms. Everything on the release
# is an asset, so the filter has to drop what is NOT a platform binary: the
# .sha256sum files, and the Windows .lib import library, which otherwise became
# a platform of its own called `win32.lib`. And a binary without its checksum is
# not a complete platform - the same rule release-all-missing.yml applies.
echo
echo "The publish job's asset list is turned into platform names:"

sed -n '/^          present="\$(/,/sort -u)"/p' "$ALL" | sed 's/^          //' > "$TMP/present.sh"
if grep -q 'sort -u' "$TMP/present.sh" && grep -q 'assets.txt' "$TMP/present.sh"; then
  ok "the filter was found in release-all.yml, and it reads the release's assets"
else
  fail "could not extract the asset filter (reading assets.txt) from release-all.yml"
fi

rm -rf "$TMP/pub"; mkdir -p "$TMP/pub"
printf '%s\n' \
    node-x64 node-x64.sha256sum \
    node-mac-arm64 node-mac-arm64.sha256sum \
    node-win32.exe node-win32.sha256sum node-win32.lib node-win32.lib.sha256sum \
    node-armhf > "$TMP/pub/assets.txt"
got="$( cd "$TMP/pub" && set -euo pipefail && . "$TMP/present.sh" && printf '%s\n' "$present" | tr '\n' ' ' )"
want="mac-arm64 win32 x64 "
if [ "$got" = "$want" ]; then
  ok "binaries become platforms, checksums and the .lib do not"
else
  fail "expected platforms [$want] but got [$got]"
fi
case " $got " in *" win32.lib "*) fail "the Windows import library is still counted as a platform" ;;
                 *) ok "node-win32.lib is not a platform called win32.lib" ;; esac
# NEGATIVE: node-armhf is on the release without node-armhf.sha256sum - a
# half-attached platform, which must be reported missing, not present.
case " $got " in *" armhf "*) fail "a binary without its checksum counted as a complete platform" ;;
                 *) ok "a binary without its .sha256sum is not a complete platform" ;; esac

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

[ "$(printf '%s\n' "$matrix" | wc -l | tr -d ' ')" = 23 ] \
  && ok "the matrix contains all 23 release targets" \
  || fail "expected 23 release targets (20 + openbsd-x64, openbsd-arm64, netbsd-x64)"
grep -A 5 -E '^ +- platform: win-arm64$' "$ALL" | grep -q 'vcbuild_arch: arm64' \
  && ok "Windows ARM64 uses the upstream arm64 vcbuild target" \
  || fail "Windows ARM64 is not wired to vcbuild arm64"
grep -q 'uses: vmactions/freebsd-vm@f0552d3b69211736abd97f02ff3d4674c56b73b1' "$ALL" \
  && ok "FreeBSD uses an immutable pinned VM action" \
  || fail "FreeBSD VM action is absent or not commit-pinned"
# OpenBSD and NetBSD (dist/openbsd, dist/netbsd): pinned VM actions, and the
# two things each OS needs before V8 can run the code it generates.
grep -q 'uses: vmactions/openbsd-vm@5f7b2c933b8846a138361d6843c52af4bef5d945' "$ALL" \
  && ok "OpenBSD uses an immutable pinned VM action" \
  || fail "OpenBSD VM action is absent or not commit-pinned"
grep -q 'uses: vmactions/netbsd-vm@c8a0d7ddb84619a7a8cc4e652efa7950b3fd9f92' "$ALL" \
  && ok "NetBSD uses an immutable pinned VM action" \
  || fail "NetBSD VM action is absent or not commit-pinned"
# The OpenBSD build itself is releases/build-openbsd.sh, run by the build job
# and by the staged build's resume jobs alike.
OBSD="$ROOT/releases/build-openbsd.sh"
RESUME="$ROOT/.github/workflows/openbsd-resume.yml"
grep -q 'mount -u -o wxallowed "$fs"' "$OBSD" \
  && ok "OpenBSD builds on a wxallowed filesystem (mksnapshot runs JIT code)" \
  || fail "OpenBSD build does not mount its workspace wxallowed"
[ "$(grep -c 'run: sh _patches/releases/build-openbsd.sh ' "$ALL" "$RESUME" | awk -F: '{s+=$2} END {print s}')" = 2 ] \
  && ok "the build job and the resume jobs build OpenBSD with the same script" \
  || fail "an OpenBSD build step does not run releases/build-openbsd.sh"
# Staged openbsd-arm64 (an emulated VM cannot finish within a job): a deadline
# that stops gmake and marks the tree, a save that keeps timestamps, a resume
# that restores with them and skips configure, and a chain the release waits on.
grep -q 'kill -TERM "$make_pid"' "$OBSD" && grep -q 'touch .stage-partial' "$OBSD" \
  && grep -q 'if \[ -f out/Makefile \]; then' "$OBSD" \
  && ok "a staged build stops gmake at its deadline and resumes without configure" \
  || fail "build-openbsd.sh does not stop at STAGE_DEADLINE or resume from out/"
grep -q "tar --zstd -cf stage.tar.zst" "$ROOT/releases/save-build-stage.sh" && grep -q 'tar --zstd -xpf stage.tar.zst' "$RESUME" \
  && ok "a stage is saved and restored with its timestamps" \
  || fail "the staged workspace is not saved and restored with tar"
python3 - "$ALL" <<'PY' && ok "openbsd-arm64 is staged through stages 2-6, the last without a deadline, and publish waits on them" || fail "the openbsd-arm64 stage chain is incomplete"
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
jobs = wf['jobs']
arm = [e for e in jobs['build']['strategy']['matrix']['include'] if e.get('platform') == 'openbsd-arm64'][0]
assert arm.get('staged') is True
prev = 'build'
for n in range(2, 7):
    j = jobs[f'openbsd_arm64_stage_{n}']
    assert j['uses'] == './.github/workflows/openbsd-resume.yml'
    assert prev in j['needs'] and 'always()' in j['if']
    w = j['with']
    assert (w['previous'], w['stage'], w['last']) == (str(n - 1), str(n), n == 6), w
    prev = f'openbsd_arm64_stage_{n}'
assert all(f'openbsd_arm64_stage_{n}' in jobs['publish']['needs'] for n in range(2, 7))
# A stage asks whether there is anything to resume before downloading it, and
# may: actions: read on every link of the chain, from both entry points.
for n in range(2, 7):
    assert jobs[f'openbsd_arm64_stage_{n}']['permissions'].get('actions') == 'read'
import os
root = os.path.dirname(os.path.dirname(sys.argv[1]))
resume = yaml.safe_load(open(os.path.join(root, 'workflows/openbsd-resume.yml')))
assert resume['permissions'].get('actions') == 'read'
steps = resume['jobs']['resume']['steps']
ask = next(s for s in steps if s.get('id') == 'staged')
fetch = next(s for s in steps if s.get('id') == 'fetch')
assert steps.index(ask) < steps.index(fetch) and 'continue-on-error' not in fetch
assert fetch['if'] == "${{ steps.staged.outputs.exists == 'true' }}"
missing = yaml.safe_load(open(os.path.join(root, 'workflows/release-all-missing.yml')))
assert missing['jobs']['build']['permissions'].get('actions') == 'read'
PY
grep -q '/usr/sbin/paxctl +m out/Release/node' "$ALL" && grep -q 'print "\\t/usr/sbin/paxctl +m \$@"' "$ALL" \
  && ok "NetBSD marks mksnapshot, node_mksnapshot and node paxctl +m" \
  || fail "NetBSD build does not paxctl +m its snapshot tools and node"
# Node 26 needs clang 19 and a libc++ with std::atomic_ref: OpenBSD's base
# toolchain has them from 7.8 (7.7's clang 16 failed in V8's atomicops.h).
obsd_rel="$(grep -A4 'uses: vmactions/openbsd-vm@' "$ALL" | sed -n "s/.*release: '\([0-9.]*\)'.*/\1/p" | head -n1)"
python3 -c 'import sys; v=tuple(map(int, sys.argv[1].split("."))); sys.exit(0 if v >= (7, 8) else 1)' "${obsd_rel:-0.0}" \
  && ok "OpenBSD builds on $obsd_rel, whose base clang Node 26 accepts" \
  || fail "OpenBSD release '$obsd_rel' is older than 7.8: its base clang cannot build V8"
# NetBSD's bundled OpenSSL must pick the BSD x86-64 configuration, not fall
# through to a 32-bit one (x86_64-gcc.c then fails to assemble).
grep -q 'defined(__OpenBSD__) || defined(__NetBSD__)) && defined(__x86_64__)' "$ROOT/dist/netbsd/netbsd-openssl-config.patch" \
  && grep -q 'target_arch==\"x64\" and OS in (\"freebsd\", \"netbsd\")' "$ROOT/dist/netbsd/netbsd-openssl-config.patch" \
  && ok "NetBSD's bundled OpenSSL uses the BSD x86-64 configuration" \
  || fail "dist/netbsd/netbsd-openssl-config.patch does not route NetBSD to BSD-x86_64"
# openbsd-arm64 also takes dist/bsd-arm64 (Node's OpenSSL has no BSD arm64
# configuration); openbsd-x64 does not.
[ "$(bash "$ROOT/releases/dist-dirs-for.sh" openbsd-arm64 | tr '\n' ' ')" = "all openbsd bsd-arm64 " ] \
  && [ "$(bash "$ROOT/releases/dist-dirs-for.sh" openbsd-x64 | tr '\n' ' ')" = "all openbsd " ] \
  && [ "$(bash "$ROOT/releases/dist-dirs-for.sh" netbsd-x64 | tr '\n' ' ')" = "all netbsd " ] \
  && ok "the apply-map gives OpenBSD and NetBSD their patch sets" \
  || fail "dist-dirs-for.sh does not map openbsd/netbsd to their sections"
# OpenBSD arm64's OpenSSL: no assembly, and the no-asm sources and headers of
# linux-aarch64 instead of the linux-x86_64 / linux-elf fall-through.
grep -q 'OS in ("linux", "android", "openharmony", "freebsd", "openbsd", "netbsd")' "$ROOT/dist/bsd-arm64/bsd-arm64-openssl-config.patch" \
  && [ "$(grep -c '^+#elif (defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)) && defined(__aarch64__)' "$ROOT/dist/bsd-arm64/bsd-arm64-openssl-config.patch")" = 31 ] \
  && grep -A4 'platform: openbsd-arm64' "$ROOT/.github/workflows/release-all.yml" | grep -q 'configure_flags: --openssl-no-asm' \
  && ok "OpenBSD arm64 builds OpenSSL without assembly, from linux-aarch64's C configuration" \
  || fail "OpenBSD arm64's OpenSSL still falls through to linux-x86_64 / linux-elf"
# Android binaries carry their C++ library: Termux has libc++_shared.so only
# after pkg install libc++.
grep -q '^export LDFLAGS="-static-libstdc++ ' "$ROOT/releases/build-android.sh" \
  && ok "an Android binary links libc++ statically" \
  || fail "an Android binary still needs libc++_shared.so"
# pull-image.sh: a [ test closed with ] (the missing one made bash say
# "[: missing ']'" on every pull).
bash -n "$ROOT/releases/pull-image.sh" && ! grep -q 'localhost; }' "$ROOT/releases/pull-image.sh" \
  && ok "pull-image.sh closes its [ test" \
  || fail "pull-image.sh has an unclosed [ test"

# ── 3b. What the armv6 target's compiler flags have to say ───────────────────
#
# Two runs died on these, each on something that is not armv6 code at all, and
# each after long enough that a check costing nothing is worth having.
#
# -marm. Debian's arm-linux-gnueabihf gcc defaults to THUMB. On ARMv7 that is
# Thumb-2, which supports the hard-float VFP ABI; ARMv6 has only Thumb-1, for
# which GCC has never implemented that ABI. The combination is refused inside
# glibc's own headers - every static inline in stdio.h and stdlib.h - so the
# error names no file of ours and reads like a broken toolchain:
#
#   /usr/arm-linux-gnueabihf/include/bits/stdio.h:40:1: sorry, unimplemented:
#   Thumb-1 'hard-float' VFP ABI
#
# That killed the first run 82 seconds in, on the first four files it compiled.
#
# -mcpu=arm1176jzf-s, not -march=armv6. The Raspberry Pi 1 and Zero are
# ARM1176JZF-S, which is ARMv6KZ, and ARMv6K is where LDREXD/STREXD - the 64-bit
# exclusive load/store - arrived. V8 needs them:
#
#   deps/v8/src/common/segmented-table.h:124: static assertion failed
#   static_assert(std::atomic<FreelistHead>::is_always_lock_free);
#
# FreelistHead is two uint32s, so that is an 8-byte atomic; on the plain ARMv6
# baseline it is not lock-free, the assertion is false, and V8's JS dispatch
# table does not compile. That killed the second run 74 minutes in.
echo
echo "The armv6 target builds in ARM mode, for the CPU those boards have:"
armv6_flags="$(awk '/^ +- platform: armv6$/,/^ +timeout_minutes:/' "$ALL" | grep -E '^ +extra_cflags: ' || true)"
if [ -z "$armv6_flags" ]; then
  ok "no armv6 target in the matrix (nothing to check)"
else
  case "$armv6_flags" in
    *-marm*) ok "-marm: ARM mode, so the hard-float VFP ABI can be used" ;;
    *) fail "the armv6 target has no -marm:${armv6_flags#*extra_cflags:}" ;;
  esac
  case "$armv6_flags" in
    *-mcpu=arm1176jzf-s*|*armv6k*|*armv6z*)
      ok "an ARMv6K CPU, so 8-byte atomics are lock-free and V8 compiles" ;;
    *) fail "the armv6 target asks for a CPU without LDREXD; V8's segmented-table static_assert will fail:${armv6_flags#*extra_cflags:}" ;;
  esac
  case "$armv6_flags" in
    *-mfloat-abi=hard*) ok "hard-float, which is what those boards run" ;;
    *) fail "the armv6 target is not hard-float:${armv6_flags#*extra_cflags:}" ;;
  esac
fi

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
#   sha256sum: 'example.patch'$'\r': No such file
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

if python3 "$ROOT/tests/runtime-workflow.py"; then
  ok "cross-qemu target snapshots and JavaScript failure gate"
else
  fail "cross-qemu runtime validation regression"
fi

# ── 10. Every build attaches its OWN files, as soon as it is done ────────────
#
# The binaries used to reach the release only in a final job, after every build
# had finished, so a platform built in twenty minutes waited hours for the
# slowest one - and was never published at all when a slow one was cancelled.
# releaseUpload.test.py pins the new shape (each build's last step attaches its
# files; the final job only checks and writes notes) with negative tests for the
# old one, and runs releases/upload-release-assets.sh against a fake gh.
if python3 -B "$ROOT/tests/releaseUpload.test.py"; then
  ok "each build attaches its own binary and checksum the moment it is done"
else
  fail "per-build release upload regression"
fi

# ── 11. A container image is pulled even when Docker Hub does not answer ─────
#
# One run lost all eight Linux container builds in their first seconds: six
# timed out getting a token from auth.docker.io, two hit Docker Hub's
# unauthenticated pull limit, and `docker run` pulls once. releases/pull-image.sh
# retries and falls back to mirror.gcr.io and Amazon ECR Public. Here it runs
# against a fake `docker` that plays each registry's part.
PULL="$ROOT/releases/pull-image.sh"
FAKE="$TMP/fakedocker"; mkdir -p "$FAKE"
cat > "$FAKE/docker" <<'DOCKER'
#!/usr/bin/env bash
# Every call is logged; a pull succeeds only for a reference listed in $UP,
# and a Docker Hub pull answers "toomanyrequests" when $LIMIT is set.
echo "$*" >> "$CALLS"
case "$1" in
  pull)
    ref="${@: -1}"
    for up in $UP; do [ "$ref" = "$up" ] && exit 0; done
    case "$ref" in mirror.gcr.io/*|public.ecr.aws/*) ;; *)
      [ -n "${LIMIT:-}" ] && { echo "toomanyrequests: You have reached your unauthenticated pull rate limit."; exit 1; } ;;
    esac
    echo "Error response from daemon: context deadline exceeded"; exit 1 ;;
  tag) exit 0 ;;
esac
exit 1
DOCKER
chmod +x "$FAKE/docker"
pull_case() { # name, expected exit, expected calls (grep -c lines) ... ; env: UP LIMIT
  CALLS="$TMP/calls"; : > "$CALLS"
  PATH="$FAKE:$PATH" CALLS="$CALLS" PULL_IMAGE_SLEEP=0 bash "$PULL" "$@" > "$TMP/pull.out" 2>&1
}
UP="i386/debian:bookworm" LIMIT= pull_case i386/debian:bookworm linux/386 \
  && [ "$(grep -c '^pull' "$TMP/calls")" -eq 1 ] && ! grep -q '^tag' "$TMP/calls" \
  && ok "pull-image: Docker Hub answering is used as it is, with nothing re-tagged" \
  || fail "pull-image: a working Docker Hub pull was not used directly"
UP="mirror.gcr.io/i386/debian:bookworm" LIMIT= pull_case i386/debian:bookworm linux/386 \
  && [ "$(grep -c '^pull --platform linux/386 i386/debian:bookworm' "$TMP/calls")" -eq 2 ] \
  && grep -q '^tag mirror.gcr.io/i386/debian:bookworm i386/debian:bookworm' "$TMP/calls" \
  && grep -q 'came from mirror.gcr.io' "$TMP/pull.out" \
  && ok "pull-image: a Docker Hub timeout is retried, then the mirror's copy is used under the build's name" \
  || fail "pull-image: timeout fallback to mirror.gcr.io"
UP="mirror.gcr.io/tonistiigi/binfmt:latest" LIMIT=1 pull_case tonistiigi/binfmt:latest \
  && [ "$(grep -c '^pull tonistiigi/binfmt:latest' "$TMP/calls")" -eq 1 ] \
  && ok "pull-image: the pull limit is not asked twice; the mirror serves binfmt" \
  || fail "pull-image: the pull limit was retried, or binfmt not taken from the mirror"
UP="public.ecr.aws/docker/library/debian:bookworm" LIMIT= pull_case i386/debian:bookworm linux/386 \
  && grep -q '^pull --platform linux/386 public.ecr.aws/docker/library/debian:bookworm' "$TMP/calls" \
  && grep -q '^tag public.ecr.aws/docker/library/debian:bookworm i386/debian:bookworm' "$TMP/calls" \
  && ok "pull-image: i386/debian comes from ECR Public as the official debian's linux/386 image" \
  || fail "pull-image: ECR fallback for i386/debian"
UP="public.ecr.aws/docker/library/debian:trixie" LIMIT= pull_case debian:trixie linux/amd64 \
  && grep -q '^tag public.ecr.aws/docker/library/debian:trixie debian:trixie' "$TMP/calls" \
  && ok "pull-image: an official image without a namespace maps to library/ on the mirrors" \
  || fail "pull-image: library/ mapping"
if UP= LIMIT= pull_case debian:trixie linux/amd64; then
  fail "pull-image: negative - nothing answering still reported success"
elif grep -q '::error::Could not pull debian:trixie' "$TMP/pull.out" && [ "$(grep -c '^pull' "$TMP/calls")" -eq 8 ]; then
  ok "pull-image: negative - with every source down it fails, after 2 + 3 + 3 attempts"
else
  fail "pull-image: negative - wrong failure: $(tail -1 "$TMP/pull.out")"
fi
if UP= LIMIT= pull_case tonistiigi/binfmt:latest && false; then :; elif grep -q 'public.ecr.aws' "$TMP/calls"; then
  fail "pull-image: negative - a non-official image was looked for on ECR's library"
else
  ok "pull-image: negative - only official images are looked for on ECR Public"
fi
# And the workflow pulls every image it runs, before it runs it.
pull_step="$(python3 - "$ALL" <<'PYEOF'
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))['jobs']
for job in steps.values():
    names = [s.get('name', '') for s in job.get('steps', [])]
    if 'Pull the build container images' in names:
        i = names.index('Pull the build container images')
        later = [n for n in names[i + 1:] if 'qemu-user' in n or n.startswith('Build (')]
        step = job['steps'][i]
        print('ok' if later and 'pull-image.sh tonistiigi/binfmt:latest' in step['run']
              and 'matrix.image' in step['run'] and "cross-container" in step['if'] else 'bad')
PYEOF
)"
[ "$pull_step" = ok ] \
  && ok "the build pulls binfmt and its container image through pull-image.sh before any docker run" \
  || fail "the pull step is missing, misplaced or does not cover every container mode ($pull_step)"

if bash "$ROOT/tests/freebsd-build.sh"; then
  ok "FreeBSD selects the native compiler for configure and make"
else
  fail "FreeBSD compiler selection regression"
fi

# i386 is linked as a non-PIE, as nodejs.org links Linux: an i386 PIE carries
# R_386_32 relocations LIEF cannot adjust when it injects a single executable
# application (WeKan v12.51's i386 single file). The flags reach the build,
# and the build refuses a binary of any other ELF type.
i386_pie="$(python3 - "$ALL" <<'PYEOF'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
build = wf['jobs']['build']
i386 = next(m for m in build['strategy']['matrix']['include'] if m['platform'] == 'i386')
step = next(s for s in build['steps'] if s.get('name') == 'Build (in a container of the target architecture)')
run = step['run']
good = (i386.get('pie_cflags') == '-fno-pie' and i386.get('pie_ldflags') == '-no-pie' and i386.get('elf_type') == 'EXEC'
        and '-e CFLAGS="${{ matrix.pie_cflags }}" -e CXXFLAGS="${{ matrix.pie_cflags }}"' in run
        and '-e LDFLAGS="${{ matrix.pie_ldflags }}"' in run
        and 'readelf -h out/Release/node | grep -q "Type:[[:space:]]*$want "' in run
        and run.index('strip out/Release/node') < run.index('readelf -h'))
print('ok' if good else 'bad')
PYEOF
)"
[ "$i386_pie" = ok ] \
  && ok "i386 is built as a non-PIE and the build checks its ELF type" \
  || fail "i386 PIE flags or the ELF type check are missing ($i386_pie)"

echo
echo "BSD link and c-ares fixes:"
# The OpenBSD ports tree's -Wl,-rpath,${EOPENSSL_LIB} is for an external
# OpenSSL; empty here, it took --start-group as its value ("stray
# --end-group", every executable, v26.11.1).
if ! grep -q 'rpath,\${' "$ROOT/dist/openbsd/openbsd-ports.patch"; then
  ok "openbsd-ports.patch adds no rpath from an unset ports variable"
else
  fail "openbsd-ports.patch adds an rpath from a ports variable"
fi
# NetBSD declares getservbyport_r only under _NETBSD_SOURCE, and returns a
# pointer where c-ares expects 0 for success: c-ares uses getservbyport.
if grep -q '^+/\* #undef HAVE_GETSERVBYPORT_R \*/' "$ROOT/dist/netbsd/netbsd-cares-getservbyport.patch" \
   && (cd "$ROOT/dist/netbsd" && sha256sum -c --status netbsd-cares-getservbyport.sha256sum); then
  ok "NetBSD c-ares does not use getservbyport_r"
else
  fail "NetBSD c-ares config patch missing or changed"
fi

echo
echo "Android (Termux) builds:"
for p in android-arm64 android-x64; do
  [ "$(bash "$ROOT/releases/dist-dirs-for.sh" "$p" | tr '\n' ' ')" = "all android " ] \
    && ok "$p applies dist/all then dist/android" || fail "$p apply-map is wrong"
done
# 32-bit x86: dist/ia32's V8, ICU and zlib fixes, as i386 and win32 take them.
[ "$(bash "$ROOT/releases/dist-dirs-for.sh" android-x86 | tr '\n' ' ')" = "all ia32 android " ] \
  && ok "android-x86 also takes dist/ia32 (32-bit x86)" || fail "android-x86 apply-map is wrong"
# gyp and V8 say ia32 for 32-bit x86; with x86, V8 built no code generator and
# mksnapshot failed to link (v26.11.1). The NDK's name stays x86.
if grep -q 'android-x86)   cpu=ia32  gyp_arch=ia32 ' "$ROOT/releases/build-android.sh" \
   && grep -q '\[ "\$gyp_arch" = ia32 \] && android_arch=x86' "$ROOT/releases/build-android.sh" \
   && grep -q 'android_target_arch=\$android_arch' "$ROOT/releases/build-android.sh"; then
  ok "android-x86 builds V8 for ia32, with the NDK's x86 ABI"
else
  fail "android-x86 must give gyp ia32 and the NDK x86"
fi
[ "$(bash "$ROOT/releases/dist-dirs-for.sh" android-armv7 | tr '\n' ' ')" = "all arm android " ] \
  && ok "android-armv7 also takes dist/arm (32-bit ARM zlib)" || fail "android-armv7 apply-map is wrong"
# Termux's common.gypi patch is not carried: dist/all owns that file.
if ! grep -qh '^+++ b/common.gypi' "$ROOT"/dist/android/*.patch; then
  ok "dist/android leaves common.gypi to dist/all"
else
  fail "dist/android patches common.gypi, which dist/all already patches"
fi
for f in "$ROOT"/dist/android/*.patch; do
  ( cd "$(dirname "$f")" && sha256sum -c --quiet "$(basename "$f" .patch).sha256sum" ) \
    && ok "$(basename "$f") matches its checksum" || fail "$(basename "$f") checksum mismatch"
  [ -f "${f%.patch}.md" ] && ok "$(basename "$f") is documented" || fail "$(basename "$f") has no .md"
done
bash -n "$ROOT/releases/build-android.sh" && ok "build-android.sh parses" || fail "build-android.sh has a syntax error"
grep -q 'ndk="$(cd "$ndk" && pwd)"' "$ROOT/releases/build-android.sh" \
  && ok "build-android.sh makes the NDK path absolute (make runs from out/)" || fail "build-android.sh NDK path may be relative"
grep -q 'NDK_SHA256: [0-9a-f]\{64\}' "$ALL" && ok "the NDK download is pinned by checksum" || fail "the NDK download is not checksum-pinned"
build_line="$(grep -n 'name: Build for Android (NDK cross compile)' "$ALL" | cut -d: -f1)"
smoke_line="$(grep -n 'name: Smoke test inside Termux' "$ALL" | cut -d: -f1)"
name_line="$(grep -n 'name: Name it for the release, and say what it is' "$ALL" | cut -d: -f1)"
[ -n "$build_line" ] && [ -n "$smoke_line" ] && [ "$build_line" -lt "$smoke_line" ] && [ "$smoke_line" -lt "$name_line" ] \
  && ok "an Android binary is smoke-tested in Termux before it is named or attached" \
  || fail "the Android smoke test is missing or runs after naming"

echo
if [ "$fails" -eq 0 ]; then
  echo "workflow-logic: everything holds."
else
  echo "workflow-logic: $fails check(s) FAILED."
fi
exit $(( fails > 0 ))
