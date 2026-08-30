/-!
Lean -> C -> Emscripten probe that requires the Lean heap/runtime.

Unlike the scalar-only `LeanWasm` module, this export accepts a `String`, whose
C ABI representation is `lean_object*`.  The C bridge constructs the Lean
value and transfers ownership to this function.

Run `just test-lean-wasm-emscripten-runtime` inside
`nix develop .#emscripten`.  As a negative control, omitting the wasm32
`libleanrt.a` makes the link fail on `lean_mk_string` and object-management
symbols.
-/

namespace LeanWasmRuntime

/-- UTF-8 byte length, narrowed modulo 2^32 at the exported ABI boundary. -/
def utf8Length (value : String) : UInt32 :=
  value.utf8ByteSize.toUInt32

@[export lean_wasm_utf8_length]
def utf8LengthExport (value : String) : UInt32 :=
  utf8Length value

theorem empty_utf8Length : utf8Length "" = 0 := by
  rfl

theorem utf8LengthExport_spec (value : String) :
    utf8LengthExport value = value.utf8ByteSize.toUInt32 := by
  rfl

example : utf8Length "Lean" = 4 := by
  native_decide

end LeanWasmRuntime
