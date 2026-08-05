# crypto-kmac-aggregate-init

Uses brace (aggregate) initialization for `ncrypto::Buffer` in the KMAC code, so
Apple Clang on the macOS runner compiles it.

`ncrypto::Buffer` is an aggregate `{ T* data; size_t len; }`, and
`Buffer<const void>(ptr, len)` is C++20 *parenthesized* aggregate initialization
(P0960), which GCC and modern Clang accept but the macOS runner's Apple Clang
does not — the mac build failed with "no matching constructor for
`ncrypto::Buffer<const void>`". `crypto_kmac.cc` now uses the portable brace form
`ncrypto::Buffer<const void>{.data = key_data, .len = key_size}`, the same style
`crypto_hash.cc` already uses. Only Apple Clang rejects the original, so this is
in the **mac** family (`mac-x64`, `mac-arm64`).

**Files:** `src/crypto/crypto_kmac.cc`
**Platforms:** mac-x64, mac-arm64 (`dist/mac/`).
**Applies to:** upstream Node.js 24.x (verified against `v24.19.0`).
