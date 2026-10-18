# openbsd-ports

Builds Node.js 26 on OpenBSD (amd64, arm64). Node.js lists OpenBSD as a
platform but releases nothing for it, and does not build it in CI. The OpenBSD
port, [`lang/node`](https://github.com/openbsd/ports/tree/master/lang/node)
(maintained by Volker Schlecht), carries 52 patches for Node 24.21.0. This is
that set, rebased onto Node 26 and applied after `dist/all`. 37 of them are
carried for an amd64/arm64 build with Node's bundled dependencies:

- **V8 on OpenBSD:**
  - `v8config.h`, `v8-internal.h` and `api.cc` know OpenBSD.
  - `platform-openbsd.cc` reads the stack start with `pthread_stackseg_np`.
  - `platform-posix.cc` lets `mmap` randomise addresses.
  - `sys-info.cc` counts online CPUs.
  - The trap handler reads OpenBSD's `sigcontext`.
  - The embedded builtins go into a page-aligned `.openbsd.mutable`
    section, and `isolate.cc` makes them read+execute after start-up.
  - `perf-jit` and `atomicops.h` build there, and `cpu.cc` assumes an FPU.
    That hunk adds an OpenBSD branch to the RISC-V `#if V8_OS_LINUX`; Node 26
    nests a glibc `#if`/`#else` inside it, so it is placed on the OUTER
    `#endif` - on the inner one it read "#elif after #else", which the
    preprocessor rejects even in code it skips, and every OpenBSD build failed.
- **No libdl:** OpenBSD's `dlopen` is in libc, and the OpenSSL configuration
  its `openssl-cli` falls through to (linux-x86_64, or linux-aarch64 with
  `dist/bsd-arm64`) links `-lm -ldl -pthread`. `openssl.gyp` removes that item
  for OpenBSD and links `-lm -pthread` instead.
- **W^X and retguard:**
  - `v8_flags` are made immutable (`mimmutable`).
  - Irregexp runs as bytecode (`regexp_interpret_all`), because the regexp
    JIT rewrites a return address, which retguard refuses.
  - `node` is linked `-z wxneeded` (`common.gypi`). The ports tree also adds
    `-Wl,-rpath,${EOPENSSL_LIB}`, for its build against an external OpenSSL;
    that is left out here. This build bundles OpenSSL, the variable is not
    set, and an empty `-rpath,` took the next argument - `--start-group` - as
    its value, so every executable failed to link with "stray --end-group".
- **IBT/BTI:** `toolchain.gypi` and `features.gypi` enable V8's CET/IBT on
  amd64, and `configure.py` enables control-flow integrity on arm64, both of
  which OpenBSD enforces.
- **abseil, highway, ada, llhttp:**
  - abseil reads the CPU count and cycle clock the OpenBSD way.
  - highway detects the compiler.
  - ada renames a `QUERY` macro that clashes with an OpenBSD header.
  - llhttp's gyp knows OpenBSD.
- **Node:**
  - `cares_wrap.h` gets the `ns_*` names OpenBSD's `<arpa/nameser.h>`
    lacks - only when c-ares includes that header
    (`CARES_HAVE_ARPA_NAMESER_H`, a system c-ares as in ports). Node's
    bundled c-ares defines them itself in `ares_nameser.h`, and a second
    definition stopped openbsd-x64: "redefinition of '__ns_class'".
  - `env.cc`, `lib/net.js` and the CommonJS loader carry the port's OpenBSD
    behaviour.

Left out, as not needed here:

- the riscv64 and i386 code generation patches;
- the npm and node-gyp patches (`--without-npm`);
- the test-runner, gcmole and pledge-Makefile patches;
- `include/node/common.gypi`, which is an installed file;
- the `configure` Python list;
- the jump-table and `macros.h` patches, which are upstream in Node 26 or no
  longer apply to its code.

The embedded-section hunk is re-placed by hand, at the outer `#if` level of
both alignment functions.

At run time, the `node` binary must sit on a filesystem mounted `wxallowed`,
as `/usr/local` is by default on OpenBSD, because V8 writes and runs machine
code. The build (`release-all.yml`, mode `openbsd`) mounts the workspace that
way for `mksnapshot`, and uses OpenBSD's base Clang as the port does.

Source: OpenBSD ports `lang/node`, Node 24.21.0, 2026-09-16. The OpenBSD
patches are under the ISC license.
