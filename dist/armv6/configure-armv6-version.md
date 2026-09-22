# configure-armv6-version

Set `arm_version` to 6 when the cross compiler targets ARMv6. Upstream
`configure.py` leaves it at `default`; V8's gyp toolchain treats that value as
ARMv7, while `--with-arm-fpu=vfp` selects VFPv2. The host snapshot compiler then
defines `CAN_USE_ARMV7_INSTRUCTIONS` without `CAN_USE_VFP3_INSTRUCTIONS` and
stops at a feature consistency assertion. An explicit version 6 keeps the
ARMv6/VFPv2 feature set coherent.

**Files:** `configure.py`  
**Platforms:** armv6 (`dist/armv6/`).  
**Applies to:** upstream Node.js 26.x (verified against `v26.9.0`).
