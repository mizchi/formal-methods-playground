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
