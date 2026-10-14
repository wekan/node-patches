# netbsd-openssl-config

Makes Node's bundled OpenSSL build for NetBSD x86-64.

Node ships OpenSSL pre-configured per platform under
`deps/openssl/config/archs/`, and two things choose which one a build uses:

- 63 dispatcher headers in `deps/openssl/config/` (`bn_conf_asm.h`,
  `configuration_asm.h`, ...), which pick the platform's headers from the
  compiler's macros. FreeBSD and OpenBSD x86 and x86-64 are there
  (`BSD-x86`, `BSD-x86_64`); NetBSD was not, so a NetBSD build fell through
  to a configuration whose `BN_ULONG` is 32 bits. The x86-64 inline assembly
  in `crypto/bn/asm/x86_64-gcc.c` then failed: "incorrect register `%eax'
  used with `q' suffix".
- `openssl_asm.gypi`, `openssl_asm_avx2.gypi` and `openssl_no_asm.gypi`,
  which pick the matching sources by gyp `OS`. These now give `netbsd` the
  same `BSD-x86`/`BSD-x86_64` sources as `freebsd`, so headers and sources
  agree.

The change is `defined(__NetBSD__)` beside `defined(__OpenBSD__)` in each
dispatcher, and `OS in ("freebsd", "netbsd")` in the three gyp files: NetBSD
is built exactly as FreeBSD and OpenBSD already are. pkgsrc does not need
this, because it builds Node against the system OpenSSL
(`--shared-openssl`); node-patches builds the bundled one, so that the
binary does not depend on the OpenSSL of the machine it runs on.
