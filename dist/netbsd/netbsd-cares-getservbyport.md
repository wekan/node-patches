# netbsd-cares-getservbyport

Lets c-ares build on NetBSD: it looks a port's service name up with
`getservbyport`, as on every system without a usable `getservbyport_r`.

Node's `deps/cares/config/netbsd/ares_config.h` (which `netbsd-pkgsrc` makes
the NetBSD build use) says NetBSD has a 4-argument `getservbyport_r`. NetBSD
declares it only under `_NETBSD_SOURCE`, which the c-ares build does not
define, so `ares_getnameinfo.c` stopped with "implicit declaration of
function 'getservbyport_r'". And NetBSD's 4-argument form returns a
`struct servent *`, while c-ares's 4-argument branch treats any non-zero
return as a failure - so even declared, every service name would have been
dropped.

The config now leaves `HAVE_GETSERVBYPORT_R` and `GETSERVBYPORT_R_ARGS`
undefined, and c-ares takes its own fallback, `getservbyport`. c-ares calls it
only for `getnameinfo` with a service lookup, and only from its own thread.

**Files:** `deps/cares/config/netbsd/ares_config.h`
**Platforms:** netbsd-x64 (`dist/netbsd/`).
**Applies to:** upstream Node.js 26.x (verified against `v26.11.1`).
