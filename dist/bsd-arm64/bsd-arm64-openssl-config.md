# bsd-arm64-openssl-config

Makes Node's bundled OpenSSL build for OpenBSD arm64 (and any other BSD on
arm64, should one be added).

Node ships OpenSSL pre-configured per platform under
`deps/openssl/config/archs/`, and two things choose which one a build uses:

- the source lists, `openssl_asm.gypi` and `openssl_no_asm.gypi`, by gyp
  `target_arch` and `OS`. arm64 has an entry for Linux, Android, OpenHarmony,
  macOS and Windows only; every other arm64 OS falls through to the last entry,
  which is **linux-x86_64**. An OpenBSD arm64 build therefore compiled
  `crypto/bn/asm/x86_64-gcc.c` and failed on its x86-64 inline assembly
  ("invalid output constraint '=a' in asm").
- 31 dispatcher headers in `deps/openssl/config/` (`bn_conf_no-asm.h`,
  `configuration_no-asm.h`, ...), which pick the platform's headers from the
  compiler's macros. For a BSD on aarch64 nothing matched and they fell back to
  the 32-bit **linux-elf** configuration.

The build for openbsd-arm64 is configured `--openssl-no-asm`, so no assembly
of any flavour is involved, and this patch points both at OpenSSL's portable C
configuration for aarch64, `linux-aarch64/no-asm`:

- `openssl_no_asm.gypi`: `freebsd`, `openbsd` and `netbsd` beside `linux`,
  `android` and `openharmony` in the arm64 entry;
- each `*_no-asm.h` dispatcher: a `(__FreeBSD__ || __OpenBSD__ || __NetBSD__)
  && __aarch64__` branch, before the BSD x86 ones, including the header the
  Linux aarch64 branch of that same file includes.

The no-asm C sources and headers carry nothing Linux-specific that OpenBSD
lacks (dlfcn for DSOs, no assembly). FreeBSD and NetBSD on arm64 are not built
here; the patch would serve them the same way if they were.
