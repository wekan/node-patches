# netbsd-pkgsrc

Builds Node.js 26 on NetBSD. NetBSD is not a platform Node.js releases for,
and `configure.py` has no `netbsd`. NetBSD's own package collection,
[pkgsrc `lang/nodejs`](https://github.com/NetBSD/pkgsrc/tree/trunk/lang/nodejs),
already builds exactly Node 26.11.1, and this is its patch set: the patches
that matter for a build with Node's **bundled** dependencies on x86-64, one
`git diff` applied after `dist/all`.

- **gyp:** `netbsd` added to the OS lists in `common.gypi` (pthread, warnings)
  and `deps/uv/common.gypi`; c-ares takes its `config/netbsd`; the gyp make
  generator uses `lockf` for NetBSD as for FreeBSD; `-larm` for NetBSD/arm.
- **V8:** `platform/memory.h` keeps NetBSD off the `malloc_usable_size` path;
  `platform-posix.cc` gives `mmap` no address hint, which NetBSD answered with
  ENOMEM; `platform-openbsd.cc` (which NetBSD uses) builds for NetBSD/arm;
  `semaphore.cc`, `strings.h`, `globals.h` and abseil's `elf_mem_image.cc`
  include what NetBSD needs.
- **Node:** `wasi_serdes.h`, `compile_cache.cc`, `inspector_agent.cc` and
  `node_postmortem_metadata.cc` build against NetBSD's headers
  (`PTHREAD_STACK_MIN`, `<unistd.h>`, the `uint*_t` macros).

One change from pkgsrc's text: in the NetBSD/arm hard-float check copied from
V8, the `#error` message names V8 issue 2140 instead of carrying its old
`code.google.com` address, so the release's risk audit finds no new URL in the
patch. That code is not compiled for x86-64.

Left out, because they do not apply to this build:

- the SunOS `-lsocket` change;
- the Darwin libtool change;
- the i386 SSE2 hasher change (`dist/all` covers that file);
- OpenSSL 1.1.1 compatibility (OpenSSL is bundled);
- the install-path patches.

Dropped since, because upstream now makes the same change itself (from
v26.12.0 on, where pkgsrc's hunks no longer apply):

- `configure` accepting Python 3.15;
- `memcopy.h` including a limits header (nodejs/node#63146; upstream includes
  `<limits.h>`).

The build itself (`release-all.yml`, mode `netbsd`):

- runs with `GYP_DEFINES=OS=netbsd` and pkgsrc's GCC 14, with libstdc++ linked
  in statically;
- runs `paxctl +m` on `mksnapshot`, `node_mksnapshot` and `node`, because PaX
  MPROTECT would otherwise stop them running the code they generate (the same
  steps pkgsrc takes).

Source: pkgsrc trunk `lang/nodejs`, Makefile 1.362, 2026-10-08. The pkgsrc
patches are under the pkgsrc license (2-clause BSD).
