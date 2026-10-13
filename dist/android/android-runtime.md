# android-runtime

Small source fixes for running on Android's bionic libc, from Termux's
nodejs package: libuv does not call `setgroups`/`setuid`/`setgid` when a child
process asks for a uid or gid (an Android app user cannot, and the call made
spawning fail); libuv's `FICLONE` ioctl and a duplicate definition are kept
off Android; uvwasi and `node_internals.h` stop excluding Android from the
POSIX paths they share with Linux; `debug_utils.cc` uses the Linux backtrace
code under Termux; `node_report.cc` writes an empty `cpus` array when the CPU
list cannot be read (Android restricts `/proc`); V8's trap handler is
disabled on Android, where it cannot install its signal handler
(nodejs/node#36287).

**Files:** `deps/uv/src/unix/process.c`, `deps/uv/src/unix/fs.c`,
`deps/uv/src/unix/sysinfo-memory.c`, `deps/uvwasi/src/uvwasi.c`,
`deps/v8/src/trap-handler/trap-handler.h`, `src/node_internals.h`,
`src/debug_utils.cc`, `src/node_report.cc`  
**Platforms:** android-arm64, android-armv7, android-x64, android-x86 (`dist/android/`).  
**Applies to:** upstream Node.js 26.x (verified against `v26.11.1`).
