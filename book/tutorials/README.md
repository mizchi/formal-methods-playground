# 6. 言語別チュートリアルとレシピ

この章は、各ツールを「どう書き始めるか」と「それで何を検査できるか」に分けて整理する。

各ページは同じ型に揃える。

```text
1. 何を検査する言語か
2. 最小チュートリアル
3. 出力の読み方
4. 実務レシピ
5. 避ける使い方
```

## 読む順番

| 目的 | 入口 |
| --- | --- |
| 実装から抜いた純粋述語を検査したい | [Z3 / SMT-LIB](z3.md) |
| RBAC、tenant、ownership など関係を検査したい | [Alloy](alloy.md) |
| retry、queue、crash、eventual を検査したい | [TLA+](tla.md) |
| actor / message protocol を実装に近く書きたい | [P](p.md) |
| 逐次関数と loop invariant を証明したい | [Dafny](dafny.md) |
| MoonBit 実装の contract を証明したい | [MoonBit prove](moonbit-prove.md) |
| bounded ではない普遍定理を証明したい | [Lean 4](lean.md) |
| 既存の成熟 proof ecosystem を使いたい | [Rocq](rocq.md) |

## レシピの読み方

レシピは「このツールで作る成果物」の単位で読む。

```text
レシピ名:
  置き換える作業
  モデルにする入力
  検査する性質
  期待する出力
  repo 内の近い例
```

実務では、最初から大きい model を作らない。
1つの claim、1つの反例、1つの CI exit code から始める。
