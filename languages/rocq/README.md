# Rocq use cases

この directory には、Rocq の2つの位置づけを分けて置く。

| probe | 問い | 位置づけ |
| --- | --- | --- |
| [`Rbac.v`](Rbac.v) | role hierarchy の単調性を普遍的に証明できるか | Lean との最小構文比較 |
| [`StackCompiler.v`](StackCompiler.v) | source evaluator と compiled stack machine は全入力で同じ結果になるか | mechanized semantics / compiler correctness の具体的 use case |
| [`BrokenStackCompiler.v`](BrokenStackCompiler.v) | operand 順を逆転すると証明が落ちるか | load-bearing な negative control |

## Compiler correctness を Rocq で扱う理由

対象は、自然数の literal、加算、減算を持つ小さな式言語である。
`eval` が source semantics、`step` / `exec` が stack machine semantics、
`compile` が両者を接続する。

証明する契約は次の1行である。

```coq
Theorem compile_correct :
  forall e s,
    exec (compile e) s = Some (eval e :: s).
```

これは有限個の式をテストする主張ではない。任意の深さの式 `e` と任意の初期 stack `s` に
対し、compiled code が underflow せず、source evaluator と同じ値を stack の先頭へ積むことを
構造帰納法で証明する。

`BrokenStackCompiler.v` は左右の operand を逆順に compile する。加算だけなら見えないが、
減算 `5 - 2` は stack machine 上で `2 - 5 = 0` になり、期待値 `3` との不一致を Rocq が拒否する。

## 実行

```sh
nix develop
just check-rocq
```

期待する結果:

```text
Rocq positive checks passed: RBAC monotonicity and compiler correctness
Rocq negative control passed: reversed subtraction produced Some [0], expected Some [3]
```

個別に正例だけ確認する場合:

```sh
cd languages/rocq
rocq compile StackCompiler.v
```

## 適用できる領域

この例から実案件へ伸ばしやすいのは次の領域である。

- compiler / interpreter / query planner の意味保存
- DSL の operational semantics と optimizer rewrite の健全性
- bytecode verifier や protocol parser の soundness
- Iris など Rocq ecosystem を使う concurrent heap / low-level semantics
- 抽出可能な certified function

一方、config の矛盾や短い workflow trace を素早く探す用途には重い。有限の構造は Alloy、
時間順序は Quint、一般的な数学や型の定理はまず Lean を使い、Rocq 固有の ecosystem または
mechanized semantics が load-bearing な場合に Rocq を選ぶ。

Leanとの境界、native codata、extraction、ecosystem、proof boundaryについては
[`../../docs/rocq-vs-lean-program-verification.md`](../../docs/rocq-vs-lean-program-verification.md)
に整理している。

公式の入口:

- [A Tour of Rocq](https://rocq-prover.org/docs/tour-of-rocq)
- [Batch compilation with `rocq compile`](https://rocq-prover.org/doc/V9.1.1/refman/practical-tools/coq-commands.html)
- [Rocq Platform](https://rocq-prover.org/platform)
- [Program extraction](https://rocq-prover.org/doc/V9.1.1/refman/addendum/extraction.html)
