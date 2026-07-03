# Lean 4

Lean 4 は、bounded scope ではなく、型に属するすべての値について
定理を証明する interactive theorem prover である。

bug hunting より、長寿命の仕様・数学的 lemma・型レベル性質に向く。

## 最小チュートリアル

domain を inductive type で書く。

```lean
inductive Permission where
  | read
  | write
  | admin
deriving DecidableEq

inductive Role where
  | viewer
  | editor
  | admin
deriving DecidableEq
```

実装に近い関数を書く。

```lean
def permits : Role -> Permission -> Bool
  | .viewer, .read => true
  | .editor, .read => true
  | .editor, .write => true
  | .admin, _ => true
  | _, _ => false
```

証明したい性質を書く。

```lean
theorem viewer_subset_editor :
    forall p : Permission, permits .viewer p = true -> permits .editor p = true := by
  intro p h
  cases p <;> simp [permits] at h ⊢
```

これは「今あるテストケースではなく、`Permission` の全 constructor について」
viewer の許可は editor に含まれる、と証明している。

## 出力の読み方

| 状態 | 意味 |
| --- | --- |
| theorem が通る | proof term が check された |
| unsolved goals | 証明していない goal が残っている |
| type mismatch | statement か proof の型が合っていない |
| simp で進まない | lemma が足りないか、definition の形が悪い |

## レシピ

### permission lattice の単調性

検査:

```text
viewer <= editor <= admin
```

permission が増えたとき、証明が壊れれば policy の見直しが必要だと分かる。

### state machine の到達可能性 lemma

Lean は探索器ではないが、小さい transition relation に対して
「この constructor の組み合わせでは到達できない」を theorem として残せる。

### protocol / algorithm の補助 lemma

TLA+ や Dafny で扱うには重い数学的補題を Lean に切り出す。

例:

```text
ordering relation の transitivity
permission composition の associativity
normalization の idempotence
```

### executable spec

Lean の `def` は実行可能なので、spec function と theorem を同じファイルに置ける。

```text
normalize(normalize(x)) = normalize(x)
```

のような性質を code と theorem の両方で管理する。

## 避ける使い方

- config bug の witness 取得に Lean を使う
- domain owner に proof script を読ませる
- bounded 反例で十分な問題を theorem proving に持ち込む
- 既存の app code を丸ごと Lean に移す

近い repo 例:

- [`../../languages/lean/Rbac.lean`](../../languages/lean/Rbac.lean)
