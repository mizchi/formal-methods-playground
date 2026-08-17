# Rocq

Rocq は、program、formal specification、proof を同じ言語で記述し、kernel で
proof term を検査する interactive theorem prover である。この repo では
compiler correctness を主例にして、「Lean ではなく Rocq を選ぶ理由」を具体化する。

## いつ選ぶか

Rocq を選ぶ理由は、言語そのものより ecosystem の場合が多い。

| 必要なもの | Rocq 側の代表例 |
| --- | --- |
| verified compiler | CompCert |
| concurrent separation logic | Iris |
| proof assistant metatheory | MetaCoq |
| OS / kernel / semantics 系の先行資産 | Rocq ecosystem |

## 最小チュートリアル: compiler correctness

小さな式言語に source semantics `eval` を定義する。

```coq
Inductive expr : Type :=
| Lit (value : nat)
| Add (lhs rhs : expr)
| Sub (lhs rhs : expr).

Fixpoint eval (e : expr) : nat := ...
```

次に stack machine の命令、1 step、program 実行、compiler を定義する。source と target の
意味をつなぐ契約は次の theorem になる。

```coq
Theorem compile_correct :
  forall e s,
    exec (compile e) s = Some (eval e :: s).
```

`e` は有限 scope 内のサンプルではなく、任意の深さの式である。証明は `e` の構造帰納法を使い、
literal、addition、subtraction の全 constructor を閉じる。任意の初期 stack `s` を保つので、
compiled program が underflow しないことも同じ契約に含まれる。

実行:

```sh
just check-rocq
```

この guard は正しい compiler を check した後、左右の operand を逆転した compiler が
`5 - 2` を `0` にしてしまい、期待値 `3` との不一致で拒否されることも確認する。

個別の正例だけなら次でよい。

```bash
rocq compile languages/rocq/Rbac.v
rocq compile languages/rocq/StackCompiler.v
```

完全な説明は [`../../languages/rocq/README.md`](../../languages/rocq/README.md) を参照する。

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

この repo の例を次の順に拡張できる。

1. source language に変数、分岐、失敗を追加する。
2. optimizer pass ごとに意味保存 lemma を置く。
3. bytecode verifier または target machine の safety と合成する。
4. 必要なら proof 済み compiler function を OCaml / Haskell / Scheme へ extract する。

## 避ける使い方

- 最初の形式手法として導入する
- small-scope counterexample が欲しいだけなのに Rocq を使う
- app engineer 全員に proof script を読ませる前提にする

近い repo 例:

- [`../../languages/rocq/StackCompiler.v`](../../languages/rocq/StackCompiler.v)
- [`../../languages/rocq/BrokenStackCompiler.v`](../../languages/rocq/BrokenStackCompiler.v)
- [`../../languages/rocq/Rbac.v`](../../languages/rocq/Rbac.v)
- Lean の対比として [`../../languages/lean/Rbac.lean`](../../languages/lean/Rbac.lean)
- [Rocq と Lean を program verification で選ぶ基準](../../docs/rocq-vs-lean-program-verification.md)

公式資料:

- [A Tour of Rocq](https://rocq-prover.org/docs/tour-of-rocq)
- [Batch compilation with `rocq compile`](https://rocq-prover.org/doc/V9.1.1/refman/practical-tools/coq-commands.html)
- [Rocq Platform](https://rocq-prover.org/platform)
- [Program extraction](https://rocq-prover.org/doc/V9.1.1/refman/addendum/extraction.html)
