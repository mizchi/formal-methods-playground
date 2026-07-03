# Rocq

Rocq は、成熟した ecosystem を持つ interactive theorem prover である。
この repo では小さい RBAC smoke probe だけを置く。GitBook では
「Lean ではなく Rocq を選ぶ理由」を明確にする章として扱う。

## いつ選ぶか

Rocq を選ぶ理由は、言語そのものより ecosystem の場合が多い。

| 必要なもの | Rocq 側の代表例 |
| --- | --- |
| verified compiler | CompCert |
| concurrent separation logic | Iris |
| proof assistant metatheory | MetaCoq |
| OS / kernel / semantics 系の先行資産 | Rocq ecosystem |

## 最小チュートリアルの方向性

この book で Rocq tutorial を足すなら、次のどちらかに絞る。

1. Lean と同じ RBAC monotonicity を Rocq で書き、記法差分を見せる。
2. Iris を使う前段として、単純な heap invariant / separation logic の入口を置く。

この repo の smoke probe:

```coq
Inductive permission := Read | Write | AdminPerm.
Inductive role := Viewer | Editor | Admin.

Definition permits (r : role) (p : permission) : bool := ...

Theorem viewer_subset_editor :
  forall p, permits Viewer p = true -> permits Editor p = true.
```

実行:

```sh
coqc languages/rocq/Rbac.v
```

## レシピ

### Lean から Rocq へ移すべき場合

条件:

- 使いたい library が Rocq にしかない
- Iris / CompCert / MetaCoq が load-bearing
- proof artifact の長期保守者が Rocq に慣れている

### concurrent data structure の本格証明

通常の app では TLA+ で interleaving を見るだけで十分なことが多い。
Rocq + Iris は、lock-free stack や memory model まで踏み込む場合に使う。

### compiler / interpreter semantics

言語処理系や DSL の意味論を証明するなら Rocq は候補になる。
アプリケーションの config validator には重すぎる。

## 避ける使い方

- 最初の形式手法として導入する
- small-scope counterexample が欲しいだけなのに Rocq を使う
- app engineer 全員に proof script を読ませる前提にする

近い repo 例:

- [`../../languages/rocq/Rbac.v`](../../languages/rocq/Rbac.v)
- Lean の対比として [`../../languages/lean/Rbac.lean`](../../languages/lean/Rbac.lean)
