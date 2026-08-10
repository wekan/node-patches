# v8-gyp-armv6-hwy-emu128

Gives ARMv6 the `HWY_BROKEN_EMU128=0` define that ARMv7 already gets, so V8's
JSON stringifier compiles.

Highway's `HWY_BROKEN_EMU128` defaults to **1** for GCC older than 14 — a GCC bug
([PR106322](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=106322)) that Highway
works around by target, not by version. When it is 1, Highway drops its fallback
target from **EMU128** (16 emulated lanes) to **SCALAR** (1 lane), and
`deps/v8/src/json/json-stringifier.cc` asks for `hw::FixedTag<uint8_t, 16>`
unconditionally on that path. One lane cannot hold sixteen:

```
deps/v8/third_party/highway/src/hwy/ops/shared-inl.h:368:27: error:
static assertion failed: Too many lanes
  note: the comparison reduces to '(16 <= 1)'
deps/v8/src/json/json-stringifier.cc:3356:33: error: no matching function for
call to 'Set(hwy::N_SCALAR::FixedTag<unsigned char, 16>&, int)'
make: *** [Makefile:143: node] Error 2
```

Upstream already carries the workaround for s390x, AIX and 32-bit ARM, but the
ARM condition is an exact `arm_version==7`. An ARMv6 build sets `arm_version` to
`6` — `configure.py`'s `is_arch_armv6()`, from the compiler's own
`__ARM_ARCH_6*__` — so it never matched, and ARMv6 was the one 32-bit ARM target
left on SCALAR. The condition now reads `arm_version==7 or arm_version==6`.

**The 6-versus-7 distinction is not about the GCC bug**, which is a property of
the compiler: the object that failed is a HOST object, built by the same
container's `g++` that builds the armhf and armv7 jobs successfully **with** the
define. The only reason ARMv6 was excluded is that upstream builds no ARMv6.

EMU128 is Highway's pure C++ emulation of 128-bit vectors — no SIMD instructions
are required of the CPU — so enabling it says nothing about what an ARMv6 board
can execute. It is the same code ARMv7 has been compiling all along.

**Files:** `tools/v8_gypfiles/v8.gyp`
**Platforms:** all (`dist/all/`) — the change is inside a
`v8_target_arch=="arm"` condition, so it is a no-op on every other target, and
ARMv6 takes the common set only (`dist/arm` is the NEON patch, and ARMv6 has no
NEON).
**Applies to:** upstream Node.js 24.x (verified against `v24.19.0`).
