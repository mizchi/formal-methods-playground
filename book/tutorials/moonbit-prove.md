# MoonBit prove

MoonBit `moon prove` は、MoonBit 実装に `proof_require` /
`proof_ensure` / `proof_invariant` を付け、Why3 と SMT solver で
検証する仕組みである。

MoonBit の実装と contract を同じ package に置けるのが強み。

## 最小チュートリアル

package で proof を有効化する。

```moonbit
options(
  "proof-enabled": true,
)
```

関数に postcondition を付ける。

```moonbit
pub fn max_of_two(a : Int, b : Int) -> Int
where {
  proof_ensure: result => result >= a && result >= b,
} {
  if a >= b { a } else { b }
}
```

実装から抜いた predicate を proof-only helper にする。

```moonbit
#proof_pure
fn checkout_spec(kind : Int, has_shipping : Bool, email_len : Int, total : Int) -> Bool {
  if total > 0 {
    if kind == 0 {
      has_shipping
    } else if kind == 1 {
      email_len > 0
    } else {
      false
    }
  } else {
    false
  }
}
```

public function が spec と一致することを証明する。

```moonbit
pub fn is_valid_checkout(kind : Int, has_shipping : Bool, email_len : Int, total : Int) -> Bool
where {
  proof_ensure: result => result == checkout_spec(kind, has_shipping, email_len, total),
} {
  checkout_spec(kind, has_shipping, email_len, total)
}
```

実行:

```sh
nix develop -c just setup-moonbit-prove-opam
nix develop -c just prove-moonbit
```

## 出力の読み方

| 出力 | 意味 |
| --- | --- |
| `goals proved` | Why3 / SMT で proof obligation が通った |
| timeout | formula が難しい。helper predicate / proof_assert / lemma に分ける |
| no configured provers | Why3 と solver version の組み合わせ問題 |
| `moon prove` が即 0 | package の `proof-enabled` が抜けている可能性 |

## レシピ

### 実装 predicate を contract として lock

置き換える作業:

- 実装を読んで「この validator はこう動くはず」とレビューする作業

検査:

```text
result == spec(input)
```

Z3 で反例を探し、MoonBit prove で実装契約を lock するのが使いやすい。

### domain operation の不変条件

例:

```text
withdraw 後も balance >= 0
mint 後も collateral ratio が下限以上
```

`.mbtp` に domain predicate を置き、public operation に `proof_ensure` を付ける。

### data structure の abstract model

例:

```text
Vector::push 後の model は old.model.append(value)
Vector::pop 後の model は old.model.dropLast
```

runtime representation と proof-only model を分ける。

### loop invariant

例:

```text
binary search の candidate window
count loop の prefix invariant
```

loop には `proof_invariant`、必要なら `proof_assert` を足す。

## 避ける使い方

- Z3 のような witness 取得を期待する
- TLA+ のような interleaving 検査を期待する
- 複雑な boolean formula を一発で投げる
- `.mbtp` の trusted bridge をレビューせず増やす

近い repo 例:

- [`../../languages/moonbit/checkout_form/`](../../languages/moonbit/checkout_form/)
- [`../../languages/moonbit/MOON_PROVE_CAPABILITIES.md`](../../languages/moonbit/MOON_PROVE_CAPABILITIES.md)
