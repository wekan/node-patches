# s390-simulator-const-cast

Lets the s390 V8 simulator compile: strip `const` before the static
`SetInstructionBits`, which takes a writable pointer.

The s390x cross-build compiles the V8 simulator, and its
`Instruction::SetInstructionBits<T>` const accessor passed a
`const uint8_t*` to the static overload, which writes through its pointer and so
takes a non-`const uint8_t*`. GCC rejected it — "invalid conversion from
`const uint8_t*` to `uint8_t*`". The accessor now `const_cast`s the pointer, the
way V8 patches instructions in place elsewhere. nodejs.org builds s390x natively
and does not compile the simulator, so upstream never hit this.

**Files:** `deps/v8/src/codegen/s390/constants-s390.h`
**Platforms:** s390x (`dist/s390x/`).
**Applies to:** upstream Node.js 24.x (verified against `v24.19.0`).
