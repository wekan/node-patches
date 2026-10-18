# openbsd-openssl-config

Makes the bundled OpenSSL's sources agree with its headers on OpenBSD x86
and x86-64.

Two things choose which of Node's pre-configured OpenSSL platforms
(`deps/openssl/config/archs/`) a build uses, and on OpenBSD they disagreed:

- the dispatcher headers in `deps/openssl/config/` (`configuration_asm.h`,
  ...) pick by compiler macro, and already send `__OpenBSD__` to `BSD-x86` and
  `BSD-x86_64`, like `__FreeBSD__`;
- the gyp source lists (`openssl_asm.gypi`, `openssl_asm_avx2.gypi`, and
  `openssl-cl_asm.gypi`/`openssl-cl_asm_avx2.gypi` for `openssl-cli`) pick by
  gyp `OS`, and named only `freebsd`. OpenBSD fell through to the Linux
  sources.

So the library was compiled with BSD-x86_64's `configuration.h`, which leaves
OpenSSL's `/dev/crypto` engine enabled as OpenSSL does on the BSDs, from a
source list that has no `engines/e_devcrypto.c`. v26.12.0's openbsd-x64 build
stopped linking `openssl-cli`: "undefined symbol: engine_load_devcrypto_int".

The change is `OS in ("freebsd", "openbsd")` for `ia32` and `x64` in those
four gyp files, so OpenBSD is built from the sources of the headers it
already uses - as `dist/netbsd/netbsd-openssl-config` does for NetBSD. The
`*_no_asm.gypi` pair is left alone: openbsd-x64 builds with assembly, and
openbsd-arm64's `--openssl-no-asm` entry belongs to `dist/bsd-arm64`, whose
hunks there would overlap these. With them,
openssl-cli links BSD-x86_64's `-lm -pthread`, so `openbsd-ports.patch`'s
removal of `-ldl` now matters only for arm64, which `dist/bsd-arm64` points at
linux-aarch64. OpenBSD ports does not need this, because it builds Node
against the system LibreSSL.

With BSD-x86_64's sources, OpenBSD compiles `engines/e_devcrypto.c`, which
needs the `/dev/crypto` ioctl interface OpenBSD's kernel no longer has: its
`<crypto/cryptodev.h>` declares no `session_op`, `crypt_op` or
`CIOCGSESSION`, so the v26.12.0 rebuild failed with "incomplete definition of
type 'session_op_t'". The same patch therefore gives the `openssl` target in
`openssl.gyp` an `OS=="openbsd"` condition that defines
`OPENSSL_NO_DEVCRYPTOENG` and removes `e_devcrypto.c` from its sources -
what OpenSSL's own `no-devcryptoeng` option does - so `crypto/init.c` no
longer calls `engine_load_devcrypto_int` either. On openbsd-arm64 the
linux-aarch64 sources have no `e_devcrypto.c` to remove, and the define is
already set by that configuration.
