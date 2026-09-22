# v8-maglev-float-minmax

Use the public `Float64Min` and `Float64Max` assembler methods from RISC-V
Maglev. The existing calls reference `FloatMinMaxHelper<double>`, whose template
definition is in another `.cc` file and has no exported instantiation. The
host `mksnapshot` link therefore fails with undefined references. The public
methods already delegate to the same helper in its defining translation unit.

**Files:** `deps/v8/src/maglev/riscv/maglev-ir-riscv.cc`  
**Platforms:** riscv64 (`dist/riscv64/`).  
**Applies to:** upstream Node.js 26.x (verified against `v26.9.0`).
