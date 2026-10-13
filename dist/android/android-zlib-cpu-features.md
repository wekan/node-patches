# android-zlib-cpu-features

Builds the bundled zlib for Android without the NDK's cpufeatures library.
`deps/zlib/zlib.gyp` defines `ARMV8_OS_ANDROID` for Android, which makes
`cpu_features.c` include `<cpu-features.h>` and call `android_getCpuFeatures()`
- but no gyp file builds `cpu-features.c`, so the compile failed ("'cpu-features.h'
file not found") and, with the header found, the link would fail instead. On
Android the file now takes the Linux path: CPU features read with
`getauxval(AT_HWCAP)`, which bionic has had since API 18. Termux never hit
this because it links the system zlib (`--shared-zlib`); this build bundles it.

**Files:** `deps/zlib/cpu_features.c`  
**Platforms:** android-arm64, android-armv7, android-x64, android-x86 (`dist/android/`).  
**Applies to:** upstream Node.js 26.x (verified against `v26.11.1`).
