#include <lean/lean.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t lean_wasm_utf8_length(lean_object *value);

// JavaScript-facing adapter. Emscripten's ccall converts its string argument
// to a temporary UTF-8 C string; this bridge creates the owned Lean String.
uint32_t lean_wasm_utf8_length_utf8(const char *value) {
  // lean_wasm_utf8_length consumes this owned reference.
  return lean_wasm_utf8_length(lean_mk_string(value));
}

#ifdef __cplusplus
}
#endif
