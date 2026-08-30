# Lean から C を経由して WebAssembly を作る

## 結論

Lean 4.31.0 の `lean -c` が生成した C について、次の3段階を実行確認した。

1. `clang --target=wasm32` + `wasm-ld` による 75-byte の freestanding scalar module
2. Emscripten による scalar module（ES module glue + Wasm）
3. Lean runtime を wasm32 に cross-build し、`String` を渡す runtime-backed module

いずれも Node.js 24 から実行できる。ただし3は Lean runtime archive 全体を最終 artifact に
含めるのではなく、link-time optimization で `String` に必要な部分だけを残す。

```text
Lean source --lean -c--> generated C --clang--> wasm32 object
     |                                      |
     +-- kernel check                       +-- wasm-ld --> .wasm

generated C --emcc/em++--> Emscripten JS glue + .wasm
                              ^
                              +-- optional wasm32 Lean runtime archive
```

1と2のscalar経路はLean runtime全体をWebAssembly化したものではない。`UInt32` のように
C ABI上でscalarになる型だけに境界を絞り、到達不能なboxed wrapperとmodule initializerを
linkerのdead-code eliminationで落とす小さい経路である。3もruntime archiveから到達可能な
subsetだけをlinkしており、`IO` application全体の動作確認ではない。

## 実行方法

freestanding toolchain は default shell に固定してある。

```sh
nix develop
just test-lean-wasm
```

成功時の出力は次の形になる。

```text
built .../build/lean-wasm/lean_wasm.wasm (75 bytes)
lean_wasm_add: 3 cases passed
```

個別の task は次の通り。

| task | 内容 |
| --- | --- |
| `just check-lean` | theorem と定義を Lean kernel で検査する |
| `just build-lean-wasm` | 検査、C 生成、wasm32 compile、link を順に行う |
| `just inspect-lean-wasm` | section、signature、export を `wasm-objdump` で見る |
| `just run-lean-wasm` | Wasmtime から `lean_wasm_add 20 22` を呼ぶ |
| `just test-lean-wasm` | Node.js で通常値、0、`UInt32` wraparound を検査する |

生成物は `build/lean-wasm/` に置かれ、Git には含めない。

Emscripten は展開後の dependency が約2 GiBあるため、別 shell に分離した。

```sh
nix develop .#emscripten

# scalar-only Emscripten module
just test-lean-wasm-emscripten

# 初回は Lean runtime と patched libuv の cross-build を含む
just test-lean-wasm-emscripten-runtime
```

| Emscripten task | 内容 |
| --- | --- |
| `just build-lean-wasm-emscripten` | scalar C から `.mjs` + `.wasm` を作る |
| `just test-lean-wasm-emscripten` | Emscripten module factory 経由で加算を検査する |
| `just build-lean-wasm-emscripten-runtime` | Lean runtimeをbuildし、`String` probeをlinkする |
| `just test-lean-wasm-emscripten-runtime` | ASCII・2-byte・日本語UTF-8の3ケースを検査する |
| `just inspect-lean-wasm-emscripten` | 両方のWasm section、import、memoryを見る |

Emscripten 5.0.6 と Lean source commit `68218e8` は `flake.lock` で固定する。runtime build は
libuv v1.48.0 を取得するため、初回だけnetwork accessを必要とする。

## Lean 側の export

対象は [`LeanWasm.lean`](../languages/lean/wasm/LeanWasm.lean) の次の定義である。

```lean
def add (left right : UInt32) : UInt32 :=
  left + right

@[export lean_wasm_add]
def addExport (left right : UInt32) : UInt32 :=
  add left right
```

`@[export lean_wasm_add]` により、生成 C に C ABI の symbol が現れる。`UInt32` は
FFI では `uint32_t` に対応するので、Wasm では `(i32, i32) -> i32` になる。

`lean -c build/lean-wasm/LeanWasm.c ...` の出力の要点は次の形だった。

```c
uint32_t lean_uint32_add(uint32_t, uint32_t);
LEAN_EXPORT uint32_t lean_wasm_add(uint32_t, uint32_t);

LEAN_EXPORT uint32_t lean_wasm_add(uint32_t left, uint32_t right) {
  return lean_uint32_add(left, right);
}
```

実際の生成 C は 2,733 bytes で、scalar export のほかに boxed wrapper と module
initializer も含む。生成 C は inspection 用であり、手編集しない。

## なぜ Lean runtime をリンクせずに済むか

Lean は `UInt32` 加算を runtime primitive `lean_uint32_add` の呼び出しとして生成する。
一見 runtime の link が必要に見えるが、Lean 4.31.0 の `lean/lean.h` は固定幅整数の
primitive を `static inline` で定義している。

```c
static inline uint32_t lean_uint32_add(uint32_t a1, uint32_t a2) {
  return a1 + a2;
}
```

そのため clang の `-O3` 後は call が直接 Wasm の `i32.add` になり、手書き shim も
Lean runtime archive も不要だった。disassembly は次の4命令だけになる。

```text
local.get 1
local.get 0
i32.add
end
```

この性質はすべての Lean 値に一般化できない。elan が配布する runtime archive は host
platform 用であり、`lean_object*` を使う生成 code を wasm32 へ link するには runtime
自体の cross build が必要である。

compile 時に `-ffunction-sections -fdata-sections`、link 時に `--gc-sections` を指定し、
export から到達しない boxed code と初期化 code を除く。さらに `--strip-all` で name などの
custom section を除き、今回の `.wasm` は 75 bytes になった。

## Wasm の出力形状とサイズ

`just inspect-lean-wasm` では次の構造を確認できる。

```text
Type[1]:
 - type[0] (i32, i32) -> i32
Function[1]:
 - func[0] sig=0 <lean_wasm_add>
Memory[1]:
 - memory[0] pages: initial=2
Export[2]:
 - memory[0] -> "memory"
 - func[0] <lean_wasm_add> -> "lean_wasm_add"
Code[1]:
 - func[0] size=7 <lean_wasm_add>
```

75 bytes は download / bundle 上の binary size である。一方、`wasm-ld` が定義する初期
linear memory は 2 pages、つまり 128 KiB ある。artifact size と instance 時の memory
footprint は分けて評価する必要がある。また、JavaScript は Wasm の `i32` result を signed
number として返すので、host wrapper では `result >>> 0` により `UInt32` に戻している。

## Emscripten scalar module

同じ [`LeanWasm.lean`](../languages/lean/wasm/LeanWasm.lean) を Emscripten に渡すと、直接
instantiateするWasmではなく、module factoryをexportするES moduleとWasmの組になる。

```js
import createModule from "./LeanWasm.mjs";

const module = await createModule();
const answer = module._lean_wasm_add(20, 22) >>> 0;
```

build optionは `MODULARIZE`、`EXPORT_ES6`、`ENVIRONMENT=node,web`、`FILESYSTEM=0` とし、
公開関数を `_lean_wasm_add` だけに制限した。repositoryで固定したEmscripten 5.0.6の結果は
次の通り。

| artifact | raw | gzip -9 |
| --- | ---: | ---: |
| `LeanWasm.mjs` | 7,886 B | 2,649 B |
| `LeanWasm.wasm` | 354 B | 257 B |
| 合計 | 8,240 B | 2,906 B |

Wasm code自体は小さいが、Emscriptenのlifecycle、load、error処理がJS glueに入る。また初期
memoryは258 pages、約16.1 MiBである。scalarだけなら75-byte版の方が明らかに小さく、
Emscriptenを選ぶ理由はbrowser/Node共通のloaderや、後からruntime機能を足す余地にある。

## Emscripten runtime-backed module

[`LeanWasmRuntime.lean`](../languages/lean/wasm/LeanWasmRuntime.lean) は `String` を受け取り、
UTF-8 byte lengthを `UInt32` で返す。

```lean
def utf8Length (value : String) : UInt32 :=
  value.utf8ByteSize.toUInt32

@[export lean_wasm_utf8_length]
def utf8LengthExport (value : String) : UInt32 :=
  utf8Length value
```

`String` の C ABI は `lean_object*` なので、JavaScript stringを直接渡せない。
[`lean_wasm_runtime_bridge.c`](../languages/lean/wasm/lean_wasm_runtime_bridge.c) が Emscripten の
UTF-8 C stringからowned Lean Stringを作り、生成関数へownershipを渡す。

```c
uint32_t lean_wasm_utf8_length_utf8(const char *value) {
  return lean_wasm_utf8_length(lean_mk_string(value));
}
```

runtime archiveはLean 4.31.0 sourceの `leanrt` targetをEmscriptenでcross-buildする。host用の
elan archiveは流用しない。中間 `libleanrt.a` は915,100 bytesだが、LTOとdead-code
elimination後の配布物は次の大きさになった。

| artifact | raw | gzip -9 |
| --- | ---: | ---: |
| `LeanWasmRuntime.mjs` | 27,547 B | 8,447 B |
| `LeanWasmRuntime.wasm` | 165,971 B | 61,635 B |
| 合計 | 193,518 B | 70,082 B |

初期memoryは256 pages、16 MiBで、最大2 GiBのshared memoryとしてJS側からimportされる。
Lean 4.31.0の公式Emscripten設定に合わせて`-pthread`を使うためである。Nodeでは実行確認したが、
browser配信ではSharedArrayBufferのためのcross-origin isolation（COOP/COEP）も別途検証対象に
なる。browser E2Eは今回のprobeには含めていない。

### Lean 4.31.0 source patch

unmodified sourceの`leanrt` buildは、Emscripten分岐のC++ declaration不一致で失敗した。

- `lean_uv_event_loop_alive`: headerは`uint8_t`、stub実装は`lean_obj_res`
- `lean_uv_os_get_group`: headerとLean externは`UInt64`引数あり、stub実装は引数なし

[`lean-4.31.0-emscripten.patch`](../languages/lean/wasm/lean-4.31.0-emscripten.patch) はABIをLean
宣言に合わせる最小patchである。event loopを持たないEmscripten stubの`alive`は`false`を
返し、`osGetGroup` stubは引数を受け取った上で従来通りunsupported assertionになる。

これはrepository observationであり、Leanのproofではない。Lean公式platform表でも
Emscripten WebAssemblyはTier 2、つまりcross-compile対象だがCI実行されず、releaseが壊れる
可能性があると明記されている。version更新時はpatchを無条件に持ち越さず、まずunmodified
sourceへ適用不要か確認する。

## どこまで使えるか

今回の scalar-only 経路に向くのは次のような core である。

- `UInt8` / `UInt16` / `UInt32` / `UInt64` など固定幅値を受け渡す pure function
- 小さい判定器、bit operation、数値計算
- host 側の I/O と状態から分離できる verified core

次の型や処理をそのまま export するには Lean runtime の wasm32 build、初期化、所有権管理、
host binding が必要になる。

- `Nat`、`Int`、`String`、`Array`、inductive data などの `lean_object*`
- closure、高階関数、例外
- `IO`、filesystem、network、thread

Lean source treeにはEmscripten向けbuild分岐があり、今回`String`に必要なruntime subsetまでは
実行確認できた。しかしLean referenceが一般application向けの安定したWasm backend / packaging
APIを提供しているわけではない。`IO`、module initialization、thread、libuvまで使う完全な
applicationは未検証であり、今回のruntime-backed probeを「Lean application全体が動く」とは
解釈しない。Lean公式FFI referenceもFFIを現時点でunstableとしている。

## 検証範囲と信頼境界

| 層 | この probe で確認したこと | 扱い |
| --- | --- | --- |
| Lean の `add` と theorem | 単位元、export 定義と加算の一致 | Lean kernel が proof term を検査 |
| `lean -c` | source から C が生成される | compiler の意味保存を信頼する |
| Lean C header | fixed-width primitive を inline C として提供 | proof 外。Lean toolchain version に固定する |
| clang / wasm-ld | C ABI を `(i32, i32) -> i32` にする | proof 外。version pin と artifact inspection |
| patched Lean runtime | `String` allocation/deallocationに必要なruntime subset | proof外。upstream差分とversionを固定する |
| Emscripten glue / bridge | JS string、`lean_object*`、ownershipを変換する | proof外。境界testとsize測定を置く |
| Node / Wasmtime / host wrapper | export を load して期待値を返す | proof 外。境界 test を置く |

したがって証明済みなのはLean定義についてのtheoremであり、最終`.wasm` binary全体の
意味保存が形式証明されたわけではない。default CIにはkernel checkとfreestanding artifactの
実行testを置く。重いEmscripten runtime buildは明示taskとして実行し、その間のtrusted
toolchainをpinする。

## 参照

- [Lean: Elaboration and Compilation](https://lean-lang.org/doc/reference/latest/Elaboration-and-Compilation/)
- [Lean: Build Tools and Distribution](https://lean-lang.org/doc/reference/latest/Build-Tools-and-Distribution/)
- [Lean: Foreign Function Interface](https://lean-lang.org/doc/reference/latest/Run-Time-Code/Foreign-Function-Interface/)
- [Lean: Fixed-Precision Integers](https://lean-lang.org/doc/reference/latest/Basic-Types/Fixed-Precision-Integers/)
- [Lean: Supported Platforms](https://lean-lang.org/doc/reference/latest/platforms/)
- [Lean 4.31.0 source: Emscripten-related build configuration](https://github.com/leanprover/lean4/blob/v4.31.0/src/CMakeLists.txt)
- [Emscripten: Interacting with code](https://emscripten.org/docs/porting/connecting_cpp_and_javascript/Interacting-with-code.html)
- [Emscripten: Pthreads support](https://emscripten.org/docs/porting/pthreads.html)
