# Dafny

Dafny は、code-like な関数に precondition / postcondition /
loop invariant を付け、SMT で証明する言語である。

逐次ロジック、validator、parser、normalizer、計算ルールに向く。

## 最小チュートリアル

predicate で仕様を書く。

```dafny
datatype Kind = Physical | Digital

datatype Form = Form(kind: Kind, hasShipping: bool, emailLen: int, total: int)

predicate IsValid(f: Form) {
  f.total > 0 &&
  match f.kind
    case Physical => f.hasShipping
    case Digital => f.emailLen > 0
}
```

method に contract を付ける。

```dafny
method MakeDigital(emailLen: int, total: int) returns (f: Form)
  requires emailLen > 0
  requires total > 0
  ensures IsValid(f)
{
  f := Form(Digital, false, emailLen, total);
}
```

loop には invariant を置く。

```dafny
method Sum(xs: seq<int>) returns (total: int)
  requires forall x :: x in xs ==> x >= 0
  ensures total >= 0
{
  total := 0;
  var i := 0;
  while i < |xs|
    invariant 0 <= i <= |xs|
    invariant total >= 0
  {
    total := total + xs[i];
    i := i + 1;
  }
}
```

実行例:

```sh
dafny verify languages/dafny/checkout_form.dfy
```

## Dijkstra: 実装と最短路証明

[`languages/dafny/dijkstra.dfy`](../../languages/dafny/dijkstra.dfy) は、
非負重み付き有向グラフに対する実行可能な Dijkstra 実装である。

- `NoEdge | Weighted(nat)` で辺なしと重みを分離する
- `Infinity | Finite(nat)` で固定長の infinity sentinel を避ける
- 各有限距離と同じコストを持つ具体的な path witness を返す
- 処理済み頂点から出る辺の triangle inequality を loop invariant にする
- triangle inequality を任意長の path に帰納し、返却距離が全経路以下だと証明する
- path witness と組み合わせ、返却値が真の最短距離だと証明する

同じ証明範囲を持つ実装を 2 種類置いている。

| method | 実行時 state | path の扱い | 用途 |
| --- | --- | --- | --- |
| `Dijkstra` | immutable `seq` | 全 path を返す | 仕様を読みやすくする参照実装 |
| `DijkstraArray` | mutable `array` | ghost path は消去し、predecessor のみ返す | JS / Go 生成向け実装 |

`DijkstraArray` も単なるテスト一致ではなく、任意の有効 path に対して
返却距離が最短であることを証明する。実行時 predecessor についても、
到達済みの非 source 頂点なら graph 内の実在する辺を指すことを保証する。
証明用の sequence snapshot は ghost なので生成コードには残らない。
現時点の公開 contract は predecessor chain の停止性と ghost path との一致までは
保証しない。path 再構築 API を公開するなら settled 順位も ghost state に持たせて
chain が必ず source へ近づく証明を追加する必要がある。

検証と生成:

```sh
just check-dafny
just translate-dafny-dijkstra
```

生成物は `build/dafny/` 以下に置かれる。実行例:

```sh
just run-dafny-dijkstra-js
just run-dafny-dijkstra-go
just benchmark-dafny-dijkstra-js
```

両ターゲットで、頂点0からの距離と witness path は次になる。

```text
distances = [Distance.Finite(0), Distance.Finite(7), Distance.Finite(9), Distance.Finite(20), Distance.Finite(20), Distance.Finite(11)]
paths = [[0], [0, 1], [0, 2], [0, 2, 3], [0, 2, 5, 4], [0, 2, 5]]
array distances = [Distance.Finite(0), Distance.Finite(7), Distance.Finite(9), Distance.Finite(20), Distance.Finite(20), Distance.Finite(11)]
predecessors = [Predecessor.NoPredecessor, Predecessor.Previous(0), Predecessor.Previous(0), Predecessor.Previous(2), Predecessor.Previous(5), Predecessor.Previous(2)]
```

## JS / Go 生成物の品質

生成物の構造、JS bundle size、Go binary size、mutable 化の benchmark、
Rust backend の現状、`{:nativeType}` / `{:extern}` / CI の注意点は
[`docs/dafny-code-generation.md`](../../docs/dafny-code-generation.md) を正本とする。

要約すると、JS は圧縮後約 12–13 KB の runtime 固定費があり、browser の小さな
initial chunk には重い。一方、mutable array 版は V=200 の worst-case 型 graph で
immutable sequence 版より約 18 倍速く、追加分は圧縮後 0.5 KB 未満だった。
生成向けには runtime state を `array`、proof state を ghost `seq` に分ける。

## 出力の読み方

| 出力 | 意味 |
| --- | --- |
| verified | すべての proof obligation が通った |
| postcondition might not hold | `ensures` を満たせない path がある |
| invariant might not be maintained | loop body 後に invariant が壊れる |
| precondition might not hold | 呼び出し側が callee の `requires` を満たしていない |

## レシピ

### validator の contract 化

置き換える作業:

- 境界値 unit test の表

モデル:

- input record
- predicate `IsValid`
- constructor / normalizer method

検査:

```text
valid を返す path は必ず IsValid を満たす
```

### parser の安全性

検査:

```text
parse success なら AST は well-formed
parse failure なら partial AST を返さない
```

### pricing / discount 計算

検査:

```text
discounted total は負にならない
cap を超えない
丸め規則が old/new で一致する
```

### loop algorithm

検査:

```text
binary search が返す index は key を指す
None のとき key は存在しない
```

## 避ける使い方

- distributed protocol を Dafny で無理に書く
- production code 全体を移植しようとする
- invariant を書かずに loop が自動で証明されると期待する
- non-linear arithmetic を無制限に投げる

近い repo 例:

- [`../../languages/dafny/checkout_form.dfy`](../../languages/dafny/checkout_form.dfy)
- [`../../languages/dafny/rbac_screens.dfy`](../../languages/dafny/rbac_screens.dfy)
- [`../../languages/dafny/dijkstra.dfy`](../../languages/dafny/dijkstra.dfy)
