# android-termux-paths

Points Node.js at Termux's directories instead of ones an Android app cannot
use. `os.tmpdir()` falls back to `/data/data/com.termux/files/usr/tmp`, not
`/tmp`, which does not exist on Android; `child_process` runs shell commands
with Termux's `/data/data/com.termux/files/usr/bin/sh`, not
`/system/bin/sh`; libuv's temporary directory and V8's `--perf-basic-prof` and
`--gc-fake-mmap` paths move to the same `tmp`. From Termux's own nodejs
package (termux/termux-packages, packages/nodejs: lib-os.js, lib-child_process.js,
deps-uv-src-unix-core.c and deps-v8-src-flags-flag-definitions.h patches), with
`@TERMUX_PREFIX@` written out.

**Files:** `lib/os.js`, `lib/child_process.js`, `deps/uv/src/unix/core.c`,
`deps/v8/src/flags/flag-definitions.h`  
**Platforms:** android-arm64, android-armv7, android-x64, android-x86 (`dist/android/`).  
**Applies to:** upstream Node.js 26.x (verified against `v26.11.1`).
