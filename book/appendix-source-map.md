# 付録: 既存資料との対応

GitBook 化するときは、既存ファイルを次のように統合する。

| GitBook の章 | 元資料 |
| --- | --- |
| 0. モデル化できる問いとして考える | [`real-world-adoption.ja.md`](../real-world-adoption.ja.md), [`findings.md`](../findings.md) |
| 1. 仕様・実装・ドメインを突き合わせる | [`real-world-adoption.ja.md`](../real-world-adoption.ja.md), [`formal-methods-playbook gist`](https://gist.github.com/mizchi/db7817e6fc077d567c41cd9d41bb1c53) |
| 2. 形式手法を採用するときの考え方 | [`real-world-adoption.ja.md`](../real-world-adoption.ja.md), [`findings.md`](../findings.md) |
| 3. やりたいことからツールを選ぶ | [`verification-tools.md`](../verification-tools.md), [`real-world-adoption.ja.md`](../real-world-adoption.ja.md) |
| 4. ツールごとにできること | [`verification-tools.md`](../verification-tools.md), [`languages/moonbit/MOON_PROVE_CAPABILITIES.md`](../languages/moonbit/MOON_PROVE_CAPABILITIES.md) |
| 4. ツールの得意不得意マップ | [`real-world-adoption.ja.md`](../real-world-adoption.ja.md), [`verification-tools.md`](../verification-tools.md) |
| 5. 実例 | [`languages/z3/`](../languages/z3/), [`languages/alloy/`](../languages/alloy/), [`languages/tla/`](../languages/tla/), `languages/p/`(../languages/p/), [`languages/dafny/`](../languages/dafny/), [`languages/moonbit/`](../languages/moonbit/), [`languages/lean/`](../languages/lean/), [`languages/rocq/`](../languages/rocq/) |
| 6. 言語別チュートリアルとレシピ | [`languages/z3/README.md`](../languages/z3/README.md), [`languages/alloy/README.md`](../languages/alloy/README.md), [`languages/p/PingPong/README.md`](../languages/p/PingPong/README.md), [`languages/moonbit/README.md`](../languages/moonbit/README.md), 各 probe |

## 未整理のまま残すべきもの

次のファイルは book 本文ではなく、実行可能な probe / 実験ログとして残す。

- `*.smt2`
- `*.als`
- `*.tla`
- `*.dfy`
- `*.lean`
- `*.mbt`
- `*.mbtp`
- `*.p`

本文からは、各 probe へのリンクと、読者が読むべき出力の意味だけを説明する。
