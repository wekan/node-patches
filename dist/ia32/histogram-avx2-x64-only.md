# histogram-avx2-x64-only

Node.js v24.20.0 enabled hdr-histogram's runtime AVX2 implementation for both
64-bit and 32-bit x86. That implementation extracts two 64-bit lanes with
`_mm_extract_epi64`; GCC accepts the source under `-m32`, but the intrinsic has no
32-bit implementation and leaves unresolved references when `node_mksnapshot`
links.

Keep runtime AVX2 dispatch on x86_64 and use the existing scalar implementation
on ia32. The scalar path is already the portable fallback for every CPU without
AVX2, so this changes performance only for 32-bit x86 and restores a valid link.
