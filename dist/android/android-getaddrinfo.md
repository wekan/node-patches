# android-getaddrinfo

Resolves `localhost` for IPv6 on Android. Android's resolver answers
`localhost` only for IPv4, so a lookup with `family: 6` failed and servers
binding `::1` by name could not start (termux/termux-packages#10277). A small
`getaddrinfo` wrapper, compiled into the binary when `__TERMUX__` is defined,
asks the system libc for `ip6-localhost` instead and passes every other lookup
through unchanged. `node.gyp` adds `src/getaddrinfo.c` to the build and treats
`OS=="android"` like Linux for the clang-only flags. From Termux's
src-getaddrinfo and node.gyp patches.

**Files:** `src/getaddrinfo.c` (new), `node.gyp`  
**Platforms:** android-arm64, android-armv7, android-x64, android-x86 (`dist/android/`).  
**Applies to:** upstream Node.js 26.x (verified against `v26.11.1`).
