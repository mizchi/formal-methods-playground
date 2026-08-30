/-!
Lean -> C -> freestanding WebAssembly probe.

Run `just test-lean-wasm` inside `nix develop`.  A pass verifies this module,
generates C, links `lean_wasm_add`, and passes three WebAssembly execution
cases.  As a negative control, replacing the addition with subtraction makes
the theorems or the execution cases fail.

The exported boundary deliberately uses only UInt32.  Lean's C ABI maps it
directly to uint32_t, allowing the generated scalar function to be linked
without the Lean heap/runtime: the matching fixed-width primitive is inline in
Lean's C header.  General Nat, String, Array, IO, or closures do not satisfy
that restriction and require a WebAssembly build of the Lean runtime.
-/

namespace LeanWasm

/-- Addition modulo 2^32, matching UInt32 and WebAssembly i32 semantics. -/
def add (left right : UInt32) : UInt32 :=
  left + right

theorem add_zero (value : UInt32) : add value 0 = value := by
  simp [add]

theorem zero_add (value : UInt32) : add 0 value = value := by
  simp [add]

@[export lean_wasm_add]
def addExport (left right : UInt32) : UInt32 :=
  add left right

theorem addExport_spec (left right : UInt32) :
    addExport left right = left + right := by
  rfl

example : add 20 22 = 42 := by
  native_decide

end LeanWasm
