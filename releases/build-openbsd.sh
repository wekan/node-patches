#!/bin/sh
# Build Node.js natively inside the OpenBSD VM (vmactions/openbsd-vm), from
# the patched upstream tree in the current directory.
#
#   sh _patches/releases/build-openbsd.sh <platform> [configure flags...]
#
# Run by release-all.yml's build job and by its resume jobs
# (openbsd-resume.yml), so both build exactly the same way.
#
# STAGED BUILDS. openbsd-arm64 runs an aarch64 VM on an x86-64 runner, so the
# whole machine is emulated, and a Node build takes far longer than the six
# hours a GitHub job may run: the first attempts stopped compiling OpenSSL, and
# then ICU, at the limit. With STAGE_DEADLINE (seconds since the epoch, the VM's
# clock synced) set, gmake is stopped before the deadline instead - GNU make
# passes SIGTERM to the compilers it started and deletes the targets they had
# not finished - and .stage-partial marks the tree for the next job, which
# restores the workspace with its timestamps and runs this again: configure is
# skipped because out/Makefile is there, and make builds only what is missing.
# Without STAGE_DEADLINE the build runs to the end, as for every other platform.
set -eu

platform="$1"
shift

# V8's build runs code it has just written (mksnapshot), which OpenBSD allows
# only from a filesystem mounted wxallowed - the OpenBSD port builds under
# /usr/ports for that reason. Here the workspace's own filesystem is given it.
fs="$(df -P . | awk 'NR==2 {print $6}')"
mount -u -o wxallowed "$fs" || true
# Compiling V8 needs more than the default data size limit.
ulimit -d "$(ulimit -H -d)" || true
# OpenBSD's base Clang, as the port uses (COMPILER = base-clang).
export CC=cc CXX=c++

rm -f .stage-partial
if [ -f out/Makefile ]; then
  echo "Resuming a staged build: out/ is here, configure is skipped."
else
  ./configure "$@"
fi

# Keep gyp's action stamps between make runs. An action with several outputs
# (the libffi headers, the inspector protocol sources, torque) is written as a
# <hash>.intermediate stamp the outputs depend on, declared .INTERMEDIATE, so
# make deletes the stamp when it exits - and the stamp also depends on the
# phony FORCE_DO_CMD, so the next make, finding it gone, counts every input as
# newer and runs the action again. One build never notices; a staged build
# ran all three actions at the start of every stage, and their new headers
# made it compile the same 78 objects again each time - v26.12.1's
# openbsd-arm64 used twelve five-hour stages and still did not link.
# Naming those stamps .SECONDARY keeps them, so a stage resumes where the last
# one stopped; a changed input still regenerates.
#
# Only those stamps. A bare `.SECONDARY:` makes EVERY target secondary, and
# with Node's makefiles GNU make then works out the graph without running a
# single command: v26.13.0's openbsd-x64 printed nothing after
# "gmake -C out" for its whole 340 minutes (v26.12.1's built in 78), and
# every openbsd-arm64 stage compiled nothing. `gmake -n` on that Makefile
# answers in a second without the line and not in ten minutes with it. A
# stage saved with the bare line has it removed here.
grep -vx -e '\.SECONDARY:' -e '# releases/build-openbsd.sh: keep action stamps between staged builds.' \
  out/Makefile > out/Makefile.stage-tmp || true
mv out/Makefile.stage-tmp out/Makefile
stamps="$( (find out -name '*.mk' -exec grep -h '^\.INTERMEDIATE:' {} + || true) | sed 's/^\.INTERMEDIATE://' | tr '\n' ' ')"
if [ -n "$stamps" ] && ! grep -q '^\.SECONDARY: .*\.intermediate' out/Makefile; then
  printf '\n# releases/build-openbsd.sh: keep action stamps between staged builds.\n.SECONDARY:%s\n' "$stamps" >> out/Makefile
fi

jobs="$(sysctl -n hw.ncpuonline)"
if [ -n "${STAGE_DEADLINE:-}" ]; then
  echo "Building until $(date -r "$STAGE_DEADLINE") at the latest; the rest goes to the next job."
  gmake -j"$jobs" &
  make_pid=$!
  while kill -0 "$make_pid" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$STAGE_DEADLINE" ]; then
      echo "This job's time for the build is up: stopping gmake to continue in the next job."
      touch .stage-partial
      kill -TERM "$make_pid" 2>/dev/null || true
      # gmake forwards the signal to the compilers and deletes their targets;
      # give it that time, then make sure nothing is left writing to out/.
      i=0
      while kill -0 "$make_pid" 2>/dev/null && [ "$i" -lt 120 ]; do sleep 1; i=$((i+1)); done
      pkill -KILL -x gmake 2>/dev/null || true
      pkill -KILL -x c++ 2>/dev/null || true
      pkill -KILL -x cc 2>/dev/null || true
      wait "$make_pid" 2>/dev/null || true
      exit 0
    fi
    sleep 30
  done
  # The build finished before the deadline: its own status decides.
  wait "$make_pid"
else
  gmake -j"$jobs"
fi

strip out/Release/node
./out/Release/node _patches/tests/runtime-smoke.cjs "$platform"
