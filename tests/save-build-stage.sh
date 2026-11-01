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
# v26.13.0: a stage that finished its build was still saved as partial,
# because .stage-partial came back with the restored workspace and the VM's
# removal of it never reached the runner. The marker is not saved...
[ ! -e "$work/restored/.stage-partial" ] || { echo 'FAIL: the saved stage carries .stage-partial' >&2; exit 1; }
# ...and a restore - of an archive from before this fix, too - removes it.
RESUME="$ROOT/.github/workflows/openbsd-resume.yml"
restore="$(awk '/- name: Restore the workspace/{f=1} f&&/run: \|/{r=1; next} r&&/^      - /{exit} r' "$RESUME")"
grep -q 'tar --zstd -xpf stage.tar.zst' <<<"$restore"
mkdir "$work/old"
touch "$work/old/.stage-partial" "$work/old/.stage-env"
(cd "$work/old" && tar --zstd -cf "$work/stage.tar.zst" .)
mkdir "$work/resumed"
cp "$work/stage.tar.zst" "$work/resumed/"
(
  cd "$work/resumed"
  export GITHUB_ENV="$work/env2"
  bash -euo pipefail -c "$(sed -e '/^ *echo "Resuming/d' -e 's/\${{[^}]*}}/x/g' <<<"$restore")"
)
[ ! -e "$work/resumed/.stage-partial" ] || { echo 'FAIL: a restored stage keeps .stage-partial' >&2; exit 1; }
# Negative: whether tar notices the directory changing is a race (it did on
# every v26.12.0 runner), so the shape is pinned instead - the archive tar
# writes while reading . is never a file in . itself.
if grep -nE 'tar [^|]*-c[a-z]*f +"?(\./)?stage\.tar\.zst' "$ROOT/releases/save-build-stage.sh"; then
  echo 'FAIL: save-build-stage.sh writes the archive into the directory it archives' >&2
  exit 1
fi
grep -q 'archive="${RUNNER_TEMP:-' "$ROOT/releases/save-build-stage.sh"
echo 'save-build-stage: the stage is saved outside the workspace, restored with its timestamps, does not contain itself, and neither the save nor the restore keeps .stage-partial.'
