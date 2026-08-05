# v8-gyp-s390x-mksnapshot

Makes mksnapshot for s390x run single-threaded, so it does not segfault the
big-endian s390x V8 simulator it runs under on the x86_64 host.

mksnapshot for s390x runs the target code under the big-endian s390x V8
*simulator* on the x86_64 host, and that simulator is not thread-safe here — any
background V8 thread segfaults it. So in `tools/v8_gypfiles/v8.gyp`, for s390x:

- `--stress-turbo-late-spilling` (an upstream default in the shared mksnapshot
  flags) is dropped — it is a register-allocator stress flag, not needed for a
  correct snapshot, and it segfaults the simulator;
- s390x is excluded from `--concurrent-builtin-generation`;
- s390x is forced fully `--single-threaded` (builtin generation, turbofan and GC
  all on one thread).

Because this patch is applied ONLY to the s390x build, every other platform keeps
upstream's default flags. The little-endian simulator targets (ppc64le, riscv64,
loong64) build concurrently without trouble, so only s390x needs this. nodejs.org
builds s390x on native Z hardware, with no simulator, so it never hits this. This
is one hunk-split half of the former `v8-gyp-cross-build` patch; the ia32 half is
`ia32/v8-gyp-ia32-push-registers`.

**Files:** `tools/v8_gypfiles/v8.gyp`
**Platforms:** s390x (`dist/s390x/`).
**Applies to:** upstream Node.js 24.x (verified against `v24.19.0`).
