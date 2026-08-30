# Dafny code generation: 出力形状、設計上の工夫、運用境界

## 結論

Dafny のコード生成は、人手で書いた JavaScript / Go の代替というより、
**検証済み core を対象言語へ移植する仕組み**として使うのがよい。

- Dafny の `requires` / `ensures` / loop invariant / ghost state は検証に使われ、
  ghost 部分は生成コードから消える
- 生成物には Dafny runtime、unbounded integer、datatype、collection の表現が入る
- source は読めるが、対象言語の idiom、公開 API、bundle 最小性は自動では得られない
- hot path では `seq` と `array` の選択が性能を大きく左右する
- FFI と target-language wrapper は Dafny の証明境界外なので、薄く保ち別途テストする

この repository では Dafny 4.11.0 から JS / Go を生成し、
[`languages/dafny/dijkstra.dfy`](../languages/dafny/dijkstra.dfy) の
immutable sequence 版と mutable array 版を比較した。

## 何が証明され、何が証明されないか

Dafny が直接検証するのは Dafny source とその contract の整合である。
公式 reference も、Dafny 由来の部分だけが検証対象であると説明している。

| 層 | 状態 | 扱い |
| --- | --- | --- |
| Dafny method と contract | 検証対象 | verifier の Green を CI に置く |
| ghost variable / lemma / specification | 検証時のみ | compiler が実行コードから消去する |
| Dafny compiler の意味保存 | toolchain への信頼 | version を pin し、生成物も実行テストする |
| Dafny runtime | trusted runtime | dependency と配布サイズに含める |
| `{:extern}` 実装 | contract を仮定 | wrapper test、negative test、review が必要 |
| JS bundler / Go compiler / OS | 証明外 | 通常の build、test、security review を行う |
| application shell、I/O、DB、network | 通常は証明外 | Dafny core との境界を型で固定する |

したがって「Dafny が verified」と「最終 bundle / binary 全体が正しい」は同義ではない。
一方で、core の precondition、postcondition、memory/index safety、termination、
algorithm invariant を machine-checked にできる価値は残る。

公式資料:

- [Dafny Reference Manual: compilation と trust boundary](https://dafny.org/dafny/DafnyRef/DafnyRef#sec-compilation)
- [Supported features by target language](https://dafny.org/dafny/DafnyRef/DafnyRef#sec-supported-features-by-target-language)
- [Installation and target compiler requirements](https://dafny.org/latest/Installation)

## 推奨 workflow

### 1. 検証する

```sh
dafny verify languages/dafny/dijkstra.dfy
```

### 2. target source を生成する

```sh
dafny translate js languages/dafny/dijkstra.dfy \
  -o build/dafny/dijkstra.js \
  --include-runtime

dafny translate go languages/dafny/dijkstra.dfy \
  -o build/dafny/dijkstra.go \
  --include-runtime
```

`dafny translate` は通常 verification も実行する。CI ですでに同一 source を検証済みなら、
重複を避けるため生成段階だけ `--no-verify` にできる。ただし、未検証 source に対して
単独で `--no-verify` を実行する task は作らない。

この repository の [`justfile`](../justfile) は次の順序を依存関係にしている。

```text
check-dafny
  -> translate js --no-verify
  -> translate go --no-verify
  -> target runtime test / benchmark
```

実行コマンド:

```sh
just translate-dafny-dijkstra
just run-dafny-dijkstra-js
just run-dafny-dijkstra-go
just benchmark-dafny-dijkstra-js
```

### 3. target 側でも検査する

最低限、次を行う。

- canonical example の実行
- Dafny reference implementation との differential test
- target compiler / bundler の build
- artifact size budget
- public wrapper の型と error behavior の test
- Dafny / runtime / target toolchain version の pin

## 生成されるもの

### 共通

生成 source には、おおむね次が現れる。

- Dafny datatype を表す class / struct / tagged value
- `seq`、`set`、`map`、`array` などを実装する runtime type
- unbounded `int` / `nat` の多倍長整数表現
- Dafny module / method 名を target 名へ変換した wrapper
- `Main` があれば target の entry point

一方、次は生成されない。

- `requires` / `ensures`
- proof-only assertion と lemma
- `ghost var`
- verification 用の quantifier と invariant

「複雑な証明を書いたので bundle も同じだけ大きくなる」とは限らない。
今回の mutable Dijkstra は最短性証明のため full path を ghost state に持つが、
生成 JS / Go は distance、visited、predecessor だけを操作する。

## JavaScript target

### 出力形状

Dafny 4.11.0 の今回の出力は、次の形だった。

- 全 Dafny module と、`--include-runtime` 指定時の runtime が 1 個の `.js` に入る
- Dafny module は IIFE と class/static method に変換される
- datatype は tag と field を持つ class になる
- `int` / `nat` は `bignumber.js` の `BigNumber` を使う
- `Main` は Node.js の `process.argv` と `process.stdout` を参照する
- Dafny の library API をそのまま ESM export する形にはならない

そのため、browser library として使う場合は `Main` を含めない core と、
手書きの export adapter を分ける。Node 用 entry point をそのまま browser bundler に
渡さない。

### collection の実際

今回の生成 JS では、Dafny source の選択が次の差になった。

| Dafny | 生成 JS | 性質 |
| --- | --- | --- |
| `seq<T>` update | `_dafny.Seq.update(...)` | `slice()` を使った immutable copy |
| `seq<T>` concat | `_dafny.Seq.Concat(...)` | path / sequence を新規生成 |
| `array<T>` update | `values[index] = value` | in-place update |
| ghost `seq<seq<nat>>` | 出力なし | proof witness は runtime allocation なし |

algorithm 上は同じ O(V²) Dijkstra でも、relaxation ごとに `seq` 全体を更新すると、
copy cost により dense graph で実質 O(V³) に近づく。hot state は mutable `array`、
proof は ghost sequence snapshot という分離が有効だった。

### bundle size

測定条件は Dafny 4.11.0、Node.js 24、`bignumber.js` 11.1.5、
esbuild 0.28.2、Node platform bundle である。

| artifact | minified | gzip -9 | brotli -q 11 |
| --- | ---: | ---: | ---: |
| empty Dafny program | 35,596 B | 12,846 B | 11,745 B |
| immutable Dijkstra のみ | 40,683 B | 13,958 B | 12,739 B |
| immutable + mutable Dijkstra | 44,819 B | 14,449 B | 13,133 B |

mutable implementation、predecessor datatype、表示例を加えた差分は、
gzip 491 B / brotli 394 B だった。問題は個別 algorithm の増分より、
圧縮後約 12–13 KB の runtime 固定費である。

判断:

- 複数の verified function で runtime を共有するなら許容しやすい
- browser initial chunk に数 KB 単位の制約がある場合は重い
- route 単位の lazy chunk / worker / server-side 利用と相性がよい
- 小関数を 1 個ずつ別 bundle にすると runtime 固定費が重複する

### performance

[`scripts/benchmark-dafny-dijkstra-js.mjs`](../scripts/benchmark-dafny-dijkstra-js.mjs)
は、毎回多くの relaxation が発生する dense graph で両実装を比較し、返却距離の
一致も検査する。Node.js 24、各 3 回の中央値:

| V | immutable `seq` | mutable `array` | speedup |
| ---: | ---: | ---: | ---: |
| 50 | 10.20 ms | 1.53 ms | 6.69x |
| 100 | 59.76 ms | 6.34 ms | 9.43x |
| 150 | 243.59 ms | 12.51 ms | 19.47x |
| 200 | 409.98 ms | 22.52 ms | 18.21x |

絶対値は machine に依存する。ここで見るべきなのは、同じ生成 backend でも
Dafny 側の representation 選択で桁違いの差が出る点である。

## Go target

### 出力形状

今回の `-o build/dafny/dijkstra.go` は次を生成した。

```text
build/dafny/dijkstra-go/src/
  dijkstra.go
  dafny/dafny.go
  dafny/dafnyFromDafny.go
  System_/System.go
```

特徴:

- application source と Dafny runtime が別 `.go` file / package になる
- Dafny `int` は `_dafny.Int` になり、多倍長整数を使う
- `seq<T>` は `_dafny.Sequence`
- `array<T>` は `_dafny.Array`
- mutable update は `ArraySet1`、read は `ArrayGet1` になる
- 現在の公式手順と生成 layout は GOPATH ベースで、通常の Go module へそのまま
  組み込むより adapter / build task を置く方が扱いやすい

この repository では次で実行する。

```sh
cd build/dafny/dijkstra-go
GO111MODULE=off GOPATH="$PWD" go run src/dijkstra.go
```

### size

combined Dijkstra の測定値:

| artifact | size |
| --- | ---: |
| application Go source | 27,726 B |
| Dafny Go runtime source | 109,381 B |
| stripped binary | 1,992,658 B |
| stripped binary gzip -9 | 825,169 B |

Go では JS の initial chunk ほど bundle size が直接問題にならないことが多い。
それでも小さな CLI / sidecar に 2 MB の固定費を許容するか、native shell と
verified core の配置を review する。

## Rust target の現在地

Dafny 4.11.0 の `dafny translate --help` には `rs` backend が存在する。
公式 installation page も Rust を「partial and growing support」としている。
したがって「Dafny から Rust は生成できない」は現在では正確ではないが、
production-ready とも言えない。

この repository の Dijkstra で試した結果:

```sh
dafny translate rs languages/dafny/dijkstra.dfy \
  -o build/dafny/rust-probe/dijkstra.rs \
  --include-runtime \
  --no-verify \
  --enforce-determinism
```

変換は失敗した。Rust backend は `--enforce-determinism` を要求し、
canonical proof 内の ghost assign-such-that (`:|`) も determinism check により
拒否された。ghost code が最終出力から消えることと、backend の source-level
制約を通過できることは別問題である。

[Dafny-to-Rust tracking issue #5561](https://github.com/dafny-lang/dafny/issues/5561)
は 2026-08-30 時点で open、milestone なしで、未解決の correctness、runtime、
datatype、set、performance 項目を追跡している。

現時点の判断:

- small deterministic core の技術検証には使える
- JS / Go と同じ source がそのまま通るとは仮定しない
- generated Rust を production path に置く前に、target test と Miri / sanitizer 相当を行う
- 安定した Rust integration が必要なら、Dafny で contract / reference を保ち、
  Rust 実装との conformance を別に検査する案も比較する

## 生成向け Dafny 設計の工夫

### 1. specification state と runtime state を分ける

```dafny
var distances := new Distance[n](...);       // executable, mutable
ghost var proofDistances := distances[..];  // verification only
```

runtime は target に自然な mutable structure、proof は quantifier を扱いやすい
immutable snapshot にする。この分離により、生成性能と証明安定性の両方を改善できる。

### 2. full result ではなく compact witness を返す

各頂点の full path を runtime で保持すると、更新ごとに concat と copy が発生する。
実行時は predecessor / index / compact certificate を返し、full witness は ghost にする。

ただし contract も意識する。現在の Dijkstra は predecessor が graph 内の実在する辺を
指すことまで保証するが、predecessor chain の停止性と ghost path との一致は未証明である。
path reconstruction を公開 API にするなら、その contract を追加する。

### 3. bounded domain には `newtype` と `{:nativeType}` を検討する

Dafny の `int` / `nat` は unbounded なので、JS / Go では多倍長整数になる。
値域を contract で証明できる場合は、`newtype` と `{:nativeType "uint"}` や
`{:nativeType "number"}` などを検討できる。

```dafny
newtype {:nativeType "uint"} VertexId = x: int | 0 <= x < 0x1_0000_0000
```

注意点:

- overflow しない値域を verifier に証明させる
- target ごとの native type 対応を supported-features table で確認する
- public API 境界で Dafny runtime type と native type の変換を測る
- bundle size と実行速度を実測してから採用する

### 4. `{:extern}` は薄い adapter に限定する

`{:extern}` declaration の contract は Dafny 側で仮定される。target implementation が
嘘をついても verifier は検出しない。

推奨:

- I/O、clock、random、crypto、DB、network を小さな port に集約する
- pure data を受け渡し、Dafny runtime collection を application 全体へ漏らさない
- wrapper の正常・境界・失敗 test を target language で持つ
- extern 名は compiler が妥当性検査しないため、各 target の build を CI で行う

### 5. generated source を直接保守しない

source of truth は `.dfy`、生成物は再生成可能な implementation layer とする。
対象言語から呼びやすい安定 API は手書き wrapper に置く。

```text
application code
  -> handwritten JS/Go adapter
    -> generated Dafny module
      -> Dafny runtime
```

generator version update 時は、生成 diff、size、benchmark、interop test をまとめて review する。

## 採用判断

向いている:

- parser、validator、normalizer、scheduler、graph / crypto algorithm の verified core
- 複数 target で同じ意味を保ちたい pure / sequential logic
- runtime 固定費を複数 function で共有できる service / worker / CLI
- failure cost が高く、contract と proof の保守費を払える部分

向いていない:

- 数 KB が重要な browser initial bundle の小さな utility 1 個
- target idiom、zero-copy native types、細かい allocation 制御が中心の code
- 大量の framework / I/O integration
- generated source を人手で継続改造する運用
- Rust backend の未対応 feature に依存する production path

## CI checklist

- [ ] Dafny version と solver version を pin した
- [ ] `dafny verify` が全 input / dependency に対して通る
- [ ] `--no-verify` translate は verified task に依存している
- [ ] JS / Go / 使用 target の生成が通る
- [ ] canonical runtime test が通る
- [ ] reference implementation との differential test がある
- [ ] generated artifact に ghost state が残っていないことを spot-check した
- [ ] hot path に immutable `seq.update` / concat copy がないか確認した
- [ ] bundle / binary size を budget 化した
- [ ] extern / handwritten adapter を target language で test した
- [ ] compiler / runtime update 時に生成 diff と benchmark を review する

## 関連資料

- [Dafny Reference Manual](https://dafny.org/dafny/DafnyRef/DafnyRef)
- [Compilation and supported target features](https://dafny.org/dafny/DafnyRef/DafnyRef#sec-supported-features-by-target-language)
- [Dafny installation / target requirements](https://dafny.org/latest/Installation)
- [Integrating Dafny and Go code](https://dafny.org/dafny/DafnyRef/integration-go/IntegrationGo)
- [Dafny-to-Rust tracking issue #5561](https://github.com/dafny-lang/dafny/issues/5561)
- [Repository Dafny tutorial](../book/tutorials/dafny.md)
- [Verified Dijkstra source](../languages/dafny/dijkstra.dfy)
- [JS performance benchmark](../scripts/benchmark-dafny-dijkstra-js.mjs)
