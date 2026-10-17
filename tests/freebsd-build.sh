#!/usr/bin/env bash
# Execute the actual FreeBSD workflow block. The build commands stand in for
# the hours-long Node build; configure and gmake verify the exported toolchain,
# and the latter compiles and runs a real C++20 executable with it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/out/Release"
python3 - "$ROOT/.github/workflows/release-all.yml" "$work/build.sh" <<'PY'
import re, sys, yaml
workflow = yaml.safe_load(open(sys.argv[1]))
steps = workflow['jobs']['build']['steps']
step = next(s for s in steps if s.get('name') == 'Build natively in FreeBSD')
script = step['with']['run']
assert '${{ matrix.configure_flags }}' in script
open(sys.argv[2], 'w').write(script.replace('${{ matrix.configure_flags }}', ''))
PY
cat > "$work/configure" <<'SH'
#!/bin/sh
set -eu
[ "$CC" = cc ] && [ "$CXX" = c++ ] || exit 42
command -v "$CC"
command -v "$CXX"
"$CC" -E -P -x c /dev/null > /dev/null
SH
cat > "$work/bin/gmake" <<'SH'
#!/bin/sh
set -eu
[ "$CC" = cc ] && [ "$CXX" = c++ ] || exit 43
[ "$*" = '-j2' ]
# FreeBSD's cc links a non-PIE unless told otherwise; -no-pie first stands in
# for that default, and the workflow's CXXFLAGS/LDFLAGS come after it.
# shellcheck disable=SC2086
"$CXX" -no-pie -std=c++20 ${CXXFLAGS:-} ${LDFLAGS:-} -x c++ -o out/Release/node - <<'CPP'
#include <array>
struct Buffer { const void* data; unsigned long len; };
int main() {
  std::array<int, 2> values{1, 2};
  Buffer b{.data = values.data(), .len = values.size()};
  return b.len == 2 && b.data != nullptr ? 0 : 1;
}
CPP
SH
cat > "$work/bin/sysctl" <<'SH'
#!/bin/sh
[ "$*" = '-n hw.ncpu' ] || exit 1
printf '2\n'
SH
chmod +x "$work/configure" "$work/bin/gmake" "$work/bin/sysctl"
(
 cd "$work"
 export PATH="$work/bin:$PATH"
 export CC=missing-freebsd-gcc CXX=missing-freebsd-g++
 sh build.sh
 ./out/Release/node
 # A regression to inherited/default gcc/g++ must fail, not merely produce
 # a successful compile using the host's coincidentally installed compiler.
 sed '/export CC=cc CXX=c++/d' build.sh > broken.sh
 if sh broken.sh > negative.log 2>&1; then
   echo 'FAIL: removing native compiler selection was not detected' >&2
   exit 1
 fi
 # The single-file injection needs a PIE here (WeKan v12.51 freebsd-x64):
 # building without the PIE flags must be caught by the workflow's own check.
 LC_ALL=C readelf -h out/Release/node | grep -q 'Type:[[:space:]]*DYN '
 sed '/export CFLAGS=-fPIE CXXFLAGS=-fPIE LDFLAGS=-pie/d' build.sh > nopie.sh
 grep -q "Type:\[\[:space:\]\]\*DYN " nopie.sh
 if sh nopie.sh > nopie.log 2>&1; then
   echo 'FAIL: a non-PIE FreeBSD node was not detected' >&2
   exit 1
 fi
 grep -q 'is not a PIE' nopie.log
)
echo 'freebsd-build: workflow exports native C/C++ toolchain; C++20 compile/run and negative regression pass.'
