# android-gyp-build

Lets V8 and libuv build for `OS=="android"`. V8's gyp files select the Linux
platform sources only for `OS=="linux"`, so an Android build had no platform
implementation; this adds `OS=="android"` to those conditions, makes V8 log
to stdout on Android, and drops `-mbranch-protection=standard` for arm64,
which the NDK's clang rejects for this configuration. libuv's gyp appends its
include directories instead of replacing them and defines `__USE_GNU` on
Android. From Termux's tools-v8_gypfiles-v8.gyp, tools-v8_gypfiles-toolchain.gypi
and deps-uv-uv.gyp patches.

Termux's common.gypi patch is deliberately NOT here: it removes the Android
include path for the NDK's cpufeatures, which only matters for Termux's
node-gyp headers, and dist/all already patches common.gypi.

**Files:** `deps/uv/uv.gyp`, `tools/v8_gypfiles/v8.gyp`, `tools/v8_gypfiles/toolchain.gypi`  
**Platforms:** android-arm64, android-armv7, android-x64, android-x86 (`dist/android/`).  
**Applies to:** upstream Node.js 26.x (verified against `v26.11.1`).
