# 個人的な形式手法ツール選択基準

> Status: personal default policy, 2026-08-05

これはツールの一般的な優劣ではなく、この repository で新しい問題に取り組むときの
個人的なファーストチョイスを決めるための方針である。

中心に置くのは **Alloy 6、Quint、Lean 4** の3つ。

> Alloyで構造を探索し、Quintで振る舞いを探索し、Leanで安定した法則を証明する。

## 3つの役割

| 問いの形 | ファーストチョイス | 主な成果物 | 典型例 |
| --- | --- | --- | --- |
| entity / relation / graph / finite world | Alloy 6 | 小さい具体 instance | RBAC、tenant、ownership、routing、有限 workflow |
| state transition / ordering / fairness / liveness | Quint | action 名付きの反例 trace | retry、timeout、crash、queue、outbox、distributed protocol |
| unbounded theorem / induction / durable law | Lean 4 | kernel が検査する proof term | permission lattice、帰納的 datatype、再利用する数学的補題 |

この3つは同じ問題を競合して解く道具ではない。

- Alloy 6 は、有限スコープの中で「悪い関係や構造が存在するか」を素早く探す。
- Quint は、「操作がどの順序で起きても安全か」「公平性の下でいつか進むか」を探す。
- Lean は、有限スコープに依存しない法則を、明示的な前提の下で証明する。

## 選択順序

1. claim を `allowed / forbidden / reachable / invariant / eventually / equivalent` の
   どれかで1文にする。
2. entity と relation が主語なら Alloy 6 を使う。
3. 状態、順序、retry、crash、fairness が主語なら Quint を使う。
4. bounded exploration では足りず、将来追加される値も含めて成立させたい法則だけ
   Leanへ持ち上げる。
5. 反例または証明結果をドメインの言葉へ戻し、CIのregression guardにつなぐ。

Leanは最初のbug huntingには使わない。まずAlloyまたはQuintで仕様の穴と仮定を探索し、
ドメイン判断が安定してから、長く残す価値のある法則をLeanで固定する。

## 境界で迷った場合

### Alloy 6 と Quint

短い有限traceで、relationの変化を見たいだけならAlloy 6に留める。
retry、crash、queue、stuttering、fairness、livenessが本質になったらQuintへ移る。

Alloy 6がtemporal operatorを持つからといって、すべての状態機械をAlloyで書く必要はない。
逆に、順序が不要なRBACやownership graphをQuintへ移す必要もない。

### Quint と Lean

Quintは、具体的な状態空間とtraceを探索して設計bugを見つける道具として使う。
Leanは、次の条件を満たす場合に使う。

- 有限boundに依存しないことが必要
- 帰納法や再帰的datatypeが主語
- theoremを別実装から再利用したい
- proof artifactを長期間維持する価値がある

Quint model全体をLeanへ機械的に写すことは目標にしない。Leanへ移すのは、modelから
抽出した小さく安定した法則だけにする。

## Escape hatch

3つのファーストチョイスに問題を無理に押し込まない。次の場合は専用ツールを使う。

| 問い | 選択肢 | 理由 |
| --- | --- | --- |
| pure predicate、config矛盾、old/new equivalence | Z3 | 時間を含まないSAT/UNSATとwitnessが最短 |
| 実装関数のpre/postcondition、loop invariant | Dafny、MoonBit prove、Verusなど | production languageまたはcode-like contractに近い |
| TLAPS、高度なrefinement、PlusCal、既存module | TLA+ | 成熟したTLA+ ecosystemを直接使う |
| Python風の設計擬似コード、role/RPC、図、fault injection、MBT | FizzBee | distributed design documentを正本にしやすい |
| typed actor/message handler、code generation | P | 実装形状がactor state machineそのもの |
| executable semantics、native codata、extraction、Irisなどの既存資産 | Rocq | 証明対象そのものを実行・観測・抽出する、またはRocq固有ecosystemが主語 |
| secrecy、authentication、攻撃者model | Tamarin / ProVerif | symbolic security protocol専用の意味論がある |

Escape hatchは敗北ではない。問いの形に対して最小の道具を選ぶための通常の分岐である。

## 運用ルール

- 最初のmodelは、1つのclaimと1つの小さい反例に絞る。
- positive sanity caseと、意図的に壊したnegative controlを置く。
- `SAT`、`UNSAT`、trace、proof successだけを成果物にしない。
- 反例を「誰が何をできるか」「どの順序で壊れるか」というドメイン語へ翻訳する。
- modelと実装の対応元を記録し、driftをCIまたはmodel-based testingで検出する。
- ツール間で仕様を重複させる場合は、どれをsource of truthにするか明記する。

## このrepositoryでの入口

- [ツールの得意不得意マップ](../book/tool-fit-map.md)
- [QuintとTLA+のOrderCheckout比較](../languages/quint/README.md)
- [Quint LLM Kit、Choreo、Connect、Trace Explorerの整理](quint-ecosystem.md)
- [Quint周辺ツールを公式2PCで動かした評価](quint-ecosystem-evaluation.md)
- [FizzBee、Quint、TLA+の比較](../languages/fizzbee/README.md)
- [Alloyの例](../languages/alloy/README.md)
- [Leanの例](../languages/lean/Rbac.lean)
- [Rocqのcompiler correctness例](../languages/rocq/README.md)
- [RocqとLeanをprogram verificationで選ぶ基準](rocq-vs-lean-program-verification.md)

この方針の目的は、使うツールを3つだけに制限することではない。
普段の思考と学習の中心を3つに絞り、例外条件を明示して選択コストを下げることにある。
