#!/usr/bin/env bash
# Run releases/save-build-stage.sh on a workspace like a staged build's, and
# restore it as openbsd-resume.yml does. v26.12.0: the save failed every time
# with "tar: .: file changed as we read it", because the archive was written
# into the directory being archived.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ws="$work/ws"
mkdir -p "$ws/out/Release/obj" "$work/runner_temp"
for i in $(seq 1 3000); do echo "$i" > "$ws/out/Release/obj/f$i.o"; done
touch -d '2026-01-02 03:04:05' "$ws/out/Release/obj/f1.o"
touch "$ws/.stage-partial"
(
  cd "$ws"
  export RUNNER_TEMP="$work/runner_temp" GITHUB_ENV="$work/env" GITHUB_STEP_SUMMARY="$work/summary" VERSION=v0 UPSTREAM_COMMIT=abc
  bash "$ROOT/releases/save-build-stage.sh" > "$work/save.log" 2>&1 || { cat "$work/save.log"; echo 'FAIL: the stage was not saved' >&2; exit 1; }
)
grep -q '^STAGED_PARTIAL=true$' "$work/env"
[ -f "$ws/stage.tar.zst" ] && [ ! -e "$work/runner_temp/stage.tar.zst" ]
mkdir "$work/restored"
(cd "$work/restored" && tar --zstd -xpf "$ws/stage.tar.zst")
[ "$(find "$work/restored/out/Release/obj" -name '*.o' | wc -l)" -eq 3000 ]
[ "$(stat -c %Y "$work/restored/out/Release/obj/f1.o")" = "$(stat -c %Y "$ws/out/Release/obj/f1.o")" ]
grep -q '^VERSION=v0$' "$work/restored/.stage-env"
[ ! -e "$work/restored/stage.tar.zst" ] || { echo 'FAIL: the archive contains itself' >&2; exit 1; }
# Negative: whether tar notices the directory changing is a race (it did on
# every v26.12.0 runner), so the shape is pinned instead - the archive tar
# writes while reading . is never a file in . itself.
if grep -nE 'tar [^|]*-c[a-z]*f +"?(\./)?stage\.tar\.zst' "$ROOT/releases/save-build-stage.sh"; then
  echo 'FAIL: save-build-stage.sh writes the archive into the directory it archives' >&2
  exit 1
fi
grep -q 'archive="${RUNNER_TEMP:-' "$ROOT/releases/save-build-stage.sh"
echo 'save-build-stage: the stage is saved outside the workspace, restored with its timestamps, and does not contain itself.'
