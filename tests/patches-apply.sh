#!/usr/bin/env bash
# Does every platform's patch set still apply to the upstream release the build
# would clone? That is the question this repo lives or dies on: a patch that no
# longer applies fails the build minutes in, on all sixteen platforms at once,
# and the only warning is a `git apply` error in a log nobody is watching.
#
#   ./tests/patches-apply.sh              # the newest upstream v<MAJOR>.x release
#   ./tests/patches-apply.sh v26.9.0     # a particular one
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
# And the files the checks below read although no patch touches them any more:
# upstream took over the histogram fix in v26.11.1, and the i386 check still
# pins it, so a release that brings the 32-bit AVX2 path back is caught.
# The OpenBSD checks below also read c-ares' own ns_* definitions, and compile
# cpu_features.c, which needs zlib's headers.
files="$(printf '%s\n' $files deps/histogram/src/hdr_histogram.c \
  deps/cares/include/ares_nameser.h \
  deps/zlib/cpu_features.h deps/zlib/zutil.h deps/zlib/zlib.h deps/zlib/zconf.h deps/zlib/chromeconf.h \
  | sort -u)"

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
  if [ "$p" = i386 ]; then
    avx2_guard="$(sed -n '/Runtime-dispatched AVX2 path/,/#endif/p' deps/histogram/src/hdr_histogram.c)"
    if printf '%s\n' "$avx2_guard" | grep -q 'defined(__x86_64__)' &&
       ! printf '%s\n' "$avx2_guard" | grep -q 'defined(__i386__)'; then
      ok "ia32 histogram keeps AVX2 dispatch on x64 and off i386"
    else
      fail "ia32 histogram still enables its 64-bit-lane AVX2 path on i386"
    fi
  fi
  # The bundled OpenSSL's headers (deps/openssl/config/*_asm.h) send every BSD
  # on x86-64 to BSD-x86_64 by compiler macro; its source lists must send the
  # same OS there by gyp OS, or the library is compiled from another
  # platform's sources - v26.12.0 openbsd-x64: "undefined symbol:
  # engine_load_devcrypto_int" (dist/openbsd/openbsd-openssl-config.md).
  case "$p" in
    freebsd-x64|openbsd-x64|netbsd-x64)
      os="${p%-x64}"
      mismatch=""
      for g in openssl_asm.gypi openssl_asm_avx2.gypi openssl-cl_asm.gypi openssl-cl_asm_avx2.gypi; do
        line="$(grep -E "'target_arch==\"x64\" and OS" "deps/openssl/$g" | grep -B0 -E 'freebsd' | head -n1)"
        printf '%s\n' "$line" | grep -qE "OS==\"$os\"|OS in \([^)]*\"$os\"" || mismatch="$mismatch $g"
        grep -A1 -F "$line" "deps/openssl/$g" | grep -q 'BSD-x86_64' || mismatch="$mismatch $g(not BSD-x86_64)"
      done
      if [ -z "$mismatch" ]; then
        ok "$p OpenSSL sources are BSD-x86_64's, as its headers are"
      else
        fail "$p OpenSSL headers are BSD-x86_64's but its sources are not:$mismatch"
      fi
      ;;
  esac
  # And OpenBSD has no /dev/crypto, so BSD-x86_64's engines/e_devcrypto.c does
  # not compile there - v26.12.0 openbsd-x64: "incomplete definition of type
  # 'session_op_t'". The library target must configure that engine out.
  if [ "$p" = openbsd-x64 ]; then
    devcrypto_state="$(python3 - <<'PY'
import ast
from pathlib import Path

gyp = ast.literal_eval(Path('deps/openssl/openssl.gyp').read_text())
target = next(t for t in gyp['targets'] if t['target_name'] == 'openssl')
found = any(
    c[0] == 'OS=="openbsd"'
    and 'OPENSSL_NO_DEVCRYPTOENG' in c[1].get('defines', [])
    and 'openssl/engines/e_devcrypto.c' in c[1].get('sources!', [])
    for c in target.get('conditions', [])
)
print('ok' if found else 'missing')
PY
)"
    if [ "$devcrypto_state" = ok ]; then
      ok "openbsd-x64 OpenSSL builds without the /dev/crypto engine"
    else
      fail "openbsd-x64 OpenSSL still compiles engines/e_devcrypto.c"
    fi
  fi
  # OpenBSD ports' cares_wrap.h defines the ns_* enums OpenBSD's
  # <arpa/nameser.h> lacks; Node's bundled c-ares defines them itself unless
  # CARES_HAVE_ARPA_NAMESER_H, so the ports copy must be under that macro or
  # it is a redefinition - v26.12.0 openbsd-x64: "redefinition of '__ns_class'".
  case "$p" in
    openbsd-x64|openbsd-arm64)
      ns_state="$(python3 - <<'PY'
import re
from pathlib import Path

def guards(path):
    # Each `typedef enum __ns_*` with the #if conditions around it.
    stack, found = [], {}
    for line in Path(path).read_text().splitlines():
        d = line.strip()
        if re.match(r'#\s*if', d):
            stack.append(d)
        elif re.match(r'#\s*endif', d):
            stack and stack.pop()
        m = re.match(r'typedef enum (__ns_\w+)', d)
        if m:
            found[m.group(1)] = list(stack)
    return found

wrap = guards('src/cares_wrap.h')
cares = guards('deps/cares/include/ares_nameser.h')
bad = [n for n in wrap if not any(g.startswith('#ifdef CARES_HAVE_ARPA_NAMESER_H') for g in wrap[n])]
own = [n for n in wrap if not any(g.startswith('#ifndef CARES_HAVE_ARPA_NAMESER_H') for g in cares.get(n, []))]
print('ok' if wrap and not bad and not own else 'bad:' + ' '.join(bad + own))
PY
)"
      if [ "$ns_state" = ok ]; then
        ok "$p cares_wrap.h defines ns_* only where c-ares does not"
      else
        fail "$p cares_wrap.h redefines c-ares' ns_* enums ($ns_state)"
      fi
      ;;
  esac
  # zlib's NEON/CRC32 callers run cpu_check_features(), which cpu_features.c
  # defined for no OpenBSD - v26.12.0 openbsd-arm64: "undefined symbol:
  # cpu_check_features". Compiled as OpenBSD aarch64 with zlib.gyp's NEON
  # defines, the object must define it.
  if [ "$p" = openbsd-arm64 ]; then
    cc_bin="$(command -v cc || command -v gcc || command -v clang || true)"
    if [ -z "$cc_bin" ] || ! command -v nm >/dev/null; then
      echo "  skip openbsd-arm64 cpu_check_features (no C compiler or nm here)"
    elif "$cc_bin" -c -w -U__linux__ -D__OpenBSD__ -D__aarch64__ -D__ARM_NEON -D__ARM_NEON__ \
         -DCRC32_ARMV8_CRC32 -DDEFLATE_SLIDE_HASH_NEON -Ideps/zlib \
         -o "$TMP/cpu_features.o" deps/zlib/cpu_features.c 2>"$TMP/cpu_features.err" &&
       nm "$TMP/cpu_features.o" | grep -qE ' T _?cpu_check_features$'; then
      ok "openbsd-arm64 zlib defines cpu_check_features"
    else
      fail "openbsd-arm64 zlib does not define cpu_check_features: $(head -3 "$TMP/cpu_features.err" | tr '\n' ' ')"
    fi
    rm -f "$TMP/cpu_features.o" "$TMP/cpu_features.err"
  fi
  if [ "$p" = armv6 ]; then
    armv6_yield_state="$(python3 - <<'PY'
from pathlib import Path

pending = None
bad = False
good_isb = False
good_mcr = False

lines = Path('deps/v8/src/base/platform/yield-processor.h').read_text().splitlines()
i = 0
while i < len(lines):
    line = lines[i].strip()
    if '__ARM_ARCH >= 7' in line:
        pending = 'arm7'
        i += 1
        continue
    elif '__ARM_ARCH >= 6' in line:
        pending = 'arm6'
        i += 1
        continue
    elif line.startswith('#define YIELD_PROCESSOR'):
        body = line
        while body.endswith('\\') and i + 1 < len(lines):
            i += 1
            body += lines[i].strip()
        if pending == 'arm6' and '__volatile__("isb"' in body:
            bad = True
        if pending == 'arm7' and '__volatile__("isb"' in body:
            good_isb = True
        if pending == 'arm6' and 'mcr p15, 0, %0, c7, c5, 4' in body:
            good_mcr = True
        pending = None
    elif line.startswith('#endif'):
        pending = None
    i += 1

if bad:
    print('bad')
elif good_isb and good_mcr:
    print('ok')
else:
    print('missing')
PY
)"
    if [ "$armv6_yield_state" = "bad" ]; then
      fail "armv6 still routes YIELD_PROCESSOR through the ARMv7 isb mnemonic"
    elif [ "$armv6_yield_state" = "ok" ]; then
      ok "armv6 keeps isb on ARMv7+ and uses CP15 ISB below that"
    else
      fail "armv6 did not leave the expected pre-ARMv7 yield-processor split"
    fi
  fi
done
git checkout -q . && git clean -qfd

echo
if [ "$fails" -eq 0 ]; then
  echo "patches-apply: every section applies to $V."
else
  echo "patches-apply: $fails failure(s) against $V."
fi
exit $(( fails > 0 ))
