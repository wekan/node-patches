# v8-turboshaft-template-disambiguator

Adds the `template` disambiguator to a dependent member template call in V8's
Turboshaft int64 lowering, so stricter compilers accept it.

`__ Tuple<Word32, Word32>(...)` calls a member template on a dependent type
(`__` expands to an assembler reference). Some compilers this repo builds with
require the `template` keyword there — `__ template Tuple<Word32, Word32>(...)` —
or they parse `<` as less-than and fail. Upstream's build compilers do not
require it, and the fix is valid C++ everywhere, so it lives in the **common**
`all/` set applied to every platform.

**Files:** `deps/v8/src/compiler/turboshaft/int64-lowering-reducer.h`
**Platforms:** all (`dist/all/`).
**Applies to:** upstream Node.js 24.x (verified against `v24.19.0`).
