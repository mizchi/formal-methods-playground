# 6. いつ差し込むか — タイミングから選ぶ

ここまでの章は 2 つの軸を扱った。

- [5 章](04-bug-patterns.md): **何を書けるか**（パターン）
- [3 章](02-purpose-to-tool.md) / [得意不得意マップ](tool-fit-map.md): **どのツールか**

残っている軸が **いつ** である。同じ claim でも、開発のどの時点で問うかで、
入力にできるもの、返ってくる情報、失敗したときの意味、許される実行時間が
すべて変わる。ツール選定を間違えるより、タイミングを間違えるほうが
「やったけど続かなかった」に直結しやすい。

産業事例の総括でも、形式手法の投資対効果は「どの手法か」より
「どの段階で不一致を見つけたか」で説明されることが多い
（Bernardi et al., [arXiv:2506.13821](https://arxiv.org/abs/2506.13821)）。
一方で採用の障壁は仕様の**記述と維持**のコストであり
（Bosch のユーザ調査, [arXiv:2304.08950](https://arxiv.org/pdf/2304.08950)）、
これは「一度証明する」より「どの頻度で走らせるか」の設計の話である。

## タイミングの分類

| | タイミング | 入力にできるもの | 出す成果物 | 許容実行時間 | 主なツール |
| --- | --- | --- | --- | --- | --- |
| T0 | 設計中（コードがまだ無い） | 設計文書、ホワイトボード、RFC | 反例 trace、設計判断の記録 | 数分〜数時間（人間が待てる） | FizzBee / Quint / TLA+ / Alloy / P |
| T1 | 実装中（関数を書きながら） | 書きかけの関数、型、契約 | 失敗した proof obligation | 数秒（エディタ内） | Dafny / MoonBit prove / Verus / F* |
| T2 | PR / CI gate | 差分、モデル、期待結果ファイル | 赤 / 緑と witness | 1 分以内（現実には 30 秒） | Z3 / Alloy / TLC（小 scope） |
| T3 | 変更・移行（差分そのものが対象） | 旧実装と新実装、旧 policy と新 policy | equivalence / more-permissive 判定 | 数分 | Z3 / SMT / differential testing |
| T4 | リリース・ロールアウト | config、manifest、IaC、flag | デプロイ前の到達可能性判定 | 数十秒 | Alloy / Z3 |
| T5 | 運用・実行時 | 本番 trace、監査ログ、DB history | 違反した実行の witness | オンライン or 日次バッチ | runtime verification / trace conformance / isolation checker |
| T6 | インシデント後 | 事故 trace、postmortem | 再現モデルと回帰 lock | 数日（一度きり） | 事故に対応する任意のツール |

この表の一番大事な列は **許容実行時間** である。
T0 の TLC は 30 分回してよいが、T2 の TLC が 30 分かかるなら、それは T2 の
仕事ではない。scope を削って T2 に置き、大きい scope は nightly（T0 相当）に
逃がす。CI に置いた検査が遅くて無視されるようになるのが、この分野で
一番よくある失敗で、産業での継続的形式検証の提案が繰り返し指摘するのも
そこである（[arXiv:1904.06152](https://arxiv.org/pdf/1904.06152)）。

## T0 — 設計中

**問いの形**: 「この設計は、どの順序で壊れるか」

コードが無い段階でしか払えないコストであり、同時にコードが無い段階でしか
得られない自由がある。実装に引きずられないので、抽象度を自分で選べる。

AWS の TLA+ 事例が有名なのは、通常のレビューやテストでは踏めない長い trace の
バグを **設計段階で** 出したからで、T2 に置いていたら scope が入らない。

この repo での例:

- [`usecases/idempotency-key/`](../usecases/idempotency-key/) — 二重課金するのは
  「provider 呼び出しと key 行の書き込みの順序」であって、実装の細部ではない。
  順序を決める前に問うのが一番安い。
- [`usecases/write-skew-seat-limit/`](../usecases/write-skew-seat-limit/) —
  isolation level は設計判断であり、ORM の default に流れると T5 まで見えない。

**T0 のアンチパターン**: いきなり実装に近い粒度で書く。
T0 のモデルは「実装できるほど詳しくない」のが正常で、
詳しくしたくなったらそれは T1 の仕事である。

## T1 — 実装中

**問いの形**: 「この関数は全入力で契約を守るか」

エディタ内で数秒で返ることが条件になる。返らないなら契約が大きすぎるか、
関数が大きすぎる。

この repo での例:
[`languages/dafny/`](../languages/dafny/)、
[`languages/moonbit/checkout_form/`](../languages/moonbit/checkout_form/)。

LLM に事前条件・事後条件の候補を出させる研究が増えているが
（SpecGen [arXiv:2401.08807](https://arxiv.org/html/2401.08807v5)、
[arXiv:2601.12845](https://arxiv.org/pdf/2601.12845)）、
生成された契約は **仮説** であり、承認するのは人間である
（[0 章](00-modeling-mindset.md)の役割分担）。
T1 で AI に任せてよいのは「候補を出す」ところまでで、
「これを契約にする」は T2 に lock する時点の人間の判断になる。

## T2 — PR / CI gate

**問いの形**: 「この差分で、以前 lock した性質はまだ成り立つか」

T2 に置けるのは、**速くて、決定的で、ドメイン語に戻せる** 検査だけである。
この repo の `just check-ci` がその形で、各 probe は期待結果
（`unsat` / `UNSAT` / `no error`）を持ち、ずれたら落ちる。

T2 に置くときの必須条件が、この repo の
[dual-check discipline](../extraction-playbook.md) —
緑の check と、それを壊す breaking variant を必ずペアで置く。
緑しか出さない検査は、いつ効かなくなったか分からない。

T2 に載せるための現実的な削り方:

| 重すぎる時 | 逃がし方 |
| --- | --- |
| TLC の scope が大きい | worker 2、Cap 1 など最小 scope を T2、大 scope を nightly |
| Alloy の scope が大きい | `for 6` を T2、`for 10` を nightly |
| proof が遅い | proof は T1 で済ませ、T2 では再検査せず artifact を検証 |
| tool の install が重い | path filter で該当ファイルが変わった PR だけ走らせる |

## T3 — 変更・移行

**問いの形**: 「この変更は、誰の結果を変えたか」

T3 は他のタイミングと質的に違う。検査対象が **プログラムではなく差分** である。
「新しい実装が正しいか」ではなく「旧と新で答えが変わる入力は何か」を聞く。
witness がそのまま影響範囲の説明になるので、ドメインの人に一番通じやすい。

Cedar は policy set を SMT で比較して
equivalent / more permissive / less permissive / incomparable に分類する
（[arXiv:2407.01688](https://arxiv.org/html/2407.01688v1)）。
これは authorization に限った話ではなく、
validator、料金計算、targeting 条件、schema など「述語として書けるもの」すべてに
そのまま移せる型である。

この repo での例:
[`usecases/schema-evolution/`](../usecases/schema-evolution/) —
rolling deploy 中は新旧が同時に動くので、互換性は両方向に問う必要がある。
片方向しか見ないのが定番の事故であり、これは T3 に置いて初めて防げる。

## T4 — リリース・ロールアウト

**問いの形**: 「この config を適用したら、何に到達できるようになるか」

コードは変わらず config だけ変わる領域。IaC、manifest、feature flag、
security group、binding。**apply する前** に聞けることが価値で、
apply した後は T5 の話になる。

この repo での例:
[`usecases/terraform-reachability/`](../usecases/terraform-reachability/)、
[`usecases/cloud-config-verification/`](../usecases/cloud-config-verification/)。

Kubernetes 領域は事例が厚い。Anvil は controller の liveness
（"eventually stable reconciliation"）を Verus 上で証明し、
検証済み controller を実際にデプロイ可能な形で示した
（[OSDI '24](https://www.usenix.org/conference/osdi24/presentation/sun-xudong)）。
operator の cross-namespace 参照が権限境界を越える問題は
config 到達可能性そのものである
（[arXiv:2507.03387](https://arxiv.org/html/2507.03387v3)）。

## T5 — 運用・実行時

**問いの形**: 「実際に起きた実行は、モデルが許す実行か」

T0-T4 はすべて「起こりうること」を扱う。T5 だけが **起きたこと** を扱う。
本番でしか出ない前提（実際の isolation level、実際の clock 精度、実際の retry
間隔）が入るので、T0 のモデルの仮定を検算する場所でもある。

3 つの形がある。

| 形 | 入力 | 何が分かる |
| --- | --- | --- |
| runtime verification / monitor | 実行中のイベント列 | 性質を破った瞬間に止める・警報する |
| trace conformance | 収集済みの trace | 実装がモデル外の順序を出していないか |
| history checking | DB の read/write history | 宣言した isolation を本当に満たしているか |

runtime verification はモデルが無くても使える点が T0-T4 と違う
（Bollig, [arXiv:2604.26753](https://arxiv.org/abs/2604.26753)、
stream-based monitoring の入門は
[arXiv:2501.15913](https://arxiv.org/pdf/2501.15913)）。
実装コストの現実的な水準は、Python 向け RV システムの大規模評価が参考になる
（[arXiv:2509.06324](https://arxiv.org/pdf/2509.06324)）。

DB の isolation は T5 の代表例で、**主張と実測が食い違う**ことが分かっている
領域である。Elle は履歴から cycle を見つけて G0 / G1a / G1b / G1c /
G-single / G2 の異常を短い witness として出す
（Kingsbury & Alvaro, [arXiv:2003.10554](https://arxiv.org/abs/2003.10554)）。
後続は同じ問いを高速化する方向に進んでいる
（Vbox [arXiv:2503.05163](https://arxiv.org/abs/2503.05163)、
mini-transactions [arXiv:2504.02344](https://arxiv.org/html/2504.02344v1)）。

つまり [`usecases/write-skew-seat-limit/`](../usecases/write-skew-seat-limit/) の
T0 モデルは「SERIALIZABLE なら安全」と言うが、
「本番が本当に SERIALIZABLE で動いているか」は T5 でしか答えられない。
**T0 の結論は T5 の観測とセットで初めて主張になる。**

本番トラフィックを記録して再構成し、oracle で検証するという方向も出てきている
（Cast, [arXiv:2602.00972](https://arxiv.org/html/2602.00972)）。

## T6 — インシデント後

**問いの形**: 「この事故は、モデル上で起こりうる実行だったか」

答えが 2 通りあり、どちらでも収穫がある。

- **起こりうる**: モデルは正しかった。invariant を書いていなかったか、
  CI に置いていなかった。→ T2 に lock する。
- **起こりえない**: モデルが実装とずれている。→ ずれている箇所が分かる。
  こちらのほうが価値が高い。

T6 は「一度きり、数日かけてよい」唯一のタイミングなので、
普段は重くて使えない道具を使ってよい。ただし成果物を T2 に落とさないと、
次の事故で同じ作業を繰り返すことになる。
[drift ledger](templates/drift-ledger.md) はそのための台帳である。

trace から性質を掘るアプローチ（LTL specification mining,
[arXiv:2501.16274](https://arxiv.org/abs/2501.16274)）は T6 と相性がよい。
事故 trace は「あってはならない実行」のラベル付きサンプルそのものだからである。

## パターン × タイミング

[5 章のバグパターン](04-bug-patterns.md)を、この軸で並べ直す。
◎ = ここで払うのが一番安い / ○ = 有効 / — = 向かない。

| パターン | T0 設計 | T1 実装 | T2 CI | T3 変更 | T4 config | T5 運用 | T6 事故後 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| config / policy 無矛盾性 | ○ | — | ◎ Z3 | ◎ Z3 | ◎ Z3 | ○ | ○ |
| 認可・関係モデル | ◎ Alloy | — | ○ Alloy | ◎ Z3 | ○ | ○ 監査ログ | ○ |
| 分散・並行 state machine | ◎ TLA+/Quint | — | ○ 小 scope | — | — | ○ trace | ◎ |
| event-driven protocol | ◎ P | — | ○ | — | — | ○ monitor | ○ |
| schedule robustness | ○ | — | ○ | — | — | ◎ replay | ◎ |
| log / trace conformance | — | — | ○ | — | — | ◎ | ◎ |
| code-level contract | — | ◎ Dafny 等 | ○ 再検査 | ○ | — | — | ○ |
| bounded memory safety | — | ○ | ◎ CBMC | ○ | — | ○ sanitizer | ○ |
| model-code equivalence | — | ○ | ◎ differential | ◎ | — | ○ | ○ |
| security protocol | ◎ Tamarin | — | — | ○ | ○ | ○ | ○ |
| drift guard | — | — | ◎ | ○ | ○ | ○ | ◎ |

読み方は 1 行ずつではなく **1 列ずつ** が実用的である。
「うちの CI に今置けるものは何か」は T2 の列を見る。
「設計レビューで聞くべきことは何か」は T0 の列を見る。

## 同じ不変条件を時間軸で追う

抽象論を避けるため、[`write-skew-seat-limit`](../usecases/write-skew-seat-limit/) の
「席数はプラン上限を超えない」を 1 本の線として通す。

| | やること | 道具 | 出るもの |
| --- | --- | --- | --- |
| T0 | isolation level を設計判断として扱い、SI で write skew が起きる trace を見る | TLA+ | 2 管理者が同時に招待する trace |
| T1 | `canInvite(org, count)` の述語を関数契約にする | Dafny / MoonBit prove | 境界（`count = limit`）の検証 |
| T2 | SERIALIZABLE 版を緑、SI 版を breaking variant として固定 | TLC 小 scope | isolation を戻す変更が赤になる |
| T3 | プラン変更で上限計算を書き換えたとき、旧新で判定が変わる入力を出す | Z3 | 「どの org の挙動が変わるか」 |
| T4 | 接続プールの isolation 設定を config claim として検査 | Z3 / 起動時 assert | 設定と設計の一致 |
| T5 | 本番の DB history に異常が無いか確認する | Elle 系 history checker | 実測した isolation |
| T6 | 超過が起きたら、その trace がモデル上で許されるか確かめる | 同じ TLA+ モデル | 「モデルの穴」か「lock 漏れ」か |

T0 と T5 が対になっていることに注意する。T0 は「SERIALIZABLE なら安全」を示し、
T5 は「本番が SERIALIZABLE か」を示す。片方だけでは主張が閉じない。

## タイミングを間違える典型

| 症状 | 実際の原因 | 直し方 |
| --- | --- | --- |
| CI が遅く、みんな無視するようになった | T0 相当の scope を T2 に置いた | 最小 scope を T2、大 scope を nightly |
| モデルは緑なのに本番が壊れた | T0 の仮定を T5 で検算していない | 仮定を明示し、観測できる形にする |
| 事故のたびに同じモデルを書き直している | T6 の成果物を T2 に落としていない | breaking variant として lock する |
| 仕様を書いたが誰も読まない | T0 の成果物が反例ではなく文書だった | 反例 trace を成果物にする |
| 移行後にだけバグが出る | T3 を飛ばして T2 だけ見ていた | 旧新 equivalence を差分の検査として置く |
| 「証明した」のに実装が違う | model-code gap を放置している | trace conformance か differential testing で接続する（[arXiv:2405.06074](https://arxiv.org/abs/2405.06074)） |

## AI にどこを任せるか（タイミング別）

LLM は仕様を書く方向で急速に実用域に入りつつあるが、
どの段階でも「候補生成」であって「承認」ではない。
TLA+ の生成品質はモデル間で大きく開き
（[arXiv:2606.05792](https://arxiv.org/pdf/2606.05792)）、
生成した仕様の model-code gap を埋めることが本質的な難しさとして残っている
（Specula, [arXiv:2607.25333](https://arxiv.org/html/2607.25333)）。
評価も syntax ではなく trace conformance と invariant correctness で行う方向に
動いている（SysMoBench, [arXiv:2509.23130](https://arxiv.org/pdf/2509.23130)）。

| タイミング | AI に任せてよいこと | 人間が決めること |
| --- | --- | --- |
| T0 | 危険な型（retry、認可、順序）の候補列挙、モデルの叩き台 | どの性質が事故になるか、どこまで抽象化するか |
| T1 | pre/postcondition の候補生成 | それを契約として承認するか |
| T2 | 期待結果ファイルの更新差分の説明 | 期待結果を変えてよいかの判断 |
| T3 | 旧新差分の witness をドメイン語に翻訳 | その差分が意図かバグか |
| T5 | trace からの性質候補の mining | mined property を仕様に昇格させるか |
| T6 | 事故 trace のモデル化と再現 | 何を回帰 lock にするか |

## 参考文献

タイミング軸で新たに参照したもの（パターン軸の文献は[5 章](04-bug-patterns.md)）。

- G. Bernardi, A. Francalanza, M. Peressotti, M. R. Mousavi,
  "Software is infrastructure: failures, successes, costs, and the case for
  formal verification", [arXiv:2506.13821](https://arxiv.org/abs/2506.13821).
  40 年分の障害事例と産業成功例から、どこで払うかのコスト論を整理する。
- "Boost the Impact of Continuous Formal Verification in Industry",
  [arXiv:1904.06152](https://arxiv.org/pdf/1904.06152).
  CI / DevOps に載せる形での低コスト化。T2 の設計論。
- Bosch でのユーザ調査,
  [arXiv:2304.08950](https://arxiv.org/pdf/2304.08950).
  採用障壁が usability と learnability にあること。
- "Empirical Formal Methods: Guidelines for Performing Empirical Studies on
  Formal Methods", [arXiv:2208.05266](https://arxiv.org/pdf/2208.05266).
  「効果があった」を主張するための評価設計。
- CERN-GSI PLC verification as a service,
  [arXiv:2502.19150](https://arxiv.org/abs/2502.19150).
  検証を社内スキルではなくサービスとして差し込む形。
- X. Sun et al., "Anvil: Verifying Liveness of Cluster Management Controllers",
  [OSDI '24](https://www.usenix.org/conference/osdi24/presentation/sun-xudong).
  Kubernetes controller の liveness を Verus で証明し、実運用可能な形で配布。
- "Breaking the Bulkhead: Cross-Namespace Reference Vulnerabilities in
  Kubernetes Operators",
  [arXiv:2507.03387](https://arxiv.org/html/2507.03387v3). T4 の到達可能性。
- B. Bollig, "Runtime Verification: Monitoring, Knowledge, and Uncertainty",
  [arXiv:2604.26753](https://arxiv.org/abs/2604.26753). T5 の基礎。
- "A Tutorial on Stream-based Monitoring",
  [arXiv:2501.15913](https://arxiv.org/pdf/2501.15913). 実装寄りの monitor 入門。
- "A Generic and Efficient Python Runtime Verification System and its
  Large-scale Evaluation",
  [arXiv:2509.06324](https://arxiv.org/pdf/2509.06324). T5 の実コスト。
- K. Kingsbury, P. Alvaro, "Elle: Inferring Isolation Anomalies from
  Experimental Observations",
  [arXiv:2003.10554](https://arxiv.org/abs/2003.10554).
  DB history から isolation 異常を witness 付きで検出する。
- "Vbox: Efficient Black-Box Serializability Verification",
  [arXiv:2503.05163](https://arxiv.org/abs/2503.05163) /
  "Boosting End-to-End Database Isolation Checking via Mini-Transactions",
  [arXiv:2504.02344](https://arxiv.org/html/2504.02344v1). 同じ問いの高速化。
- "Cast: Automated Resilience Testing for Production Cloud Service Systems",
  [arXiv:2602.00972](https://arxiv.org/html/2602.00972).
  本番トラフィックを記録・再構成して oracle にかける。
- V. B. F. Gomes et al., "Verifying Strong Eventual Consistency in Distributed
  Systems", [arXiv:1707.01747](https://arxiv.org/abs/1707.01747).
  op-based CRDT の SEC を Isabelle/HOL で、network model 込みで証明。
  [`offline-sync-convergence`](../usecases/offline-sync-convergence/) の
  bounded な Alloy 検査の、unbounded 側の対応物。
- "Specula: Scaling formal specifications for autonomous model checking of
  system code", [arXiv:2607.25333](https://arxiv.org/html/2607.25333) /
  "Can LLMs Write Correct TLA+ Specifications?",
  [arXiv:2606.05792](https://arxiv.org/pdf/2606.05792).
  AI 生成仕様の現在地と、残る model-code gap。
- D. Fett, R. Küsters, G. Schmitz, "A Comprehensive Formal Security Analysis of
  OAuth 2.0", [arXiv:1601.01229](https://arxiv.org/abs/1601.01229) /
  "The Web SSO Standard OpenID Connect: In-Depth Formal Security Analysis and
  Security Guidelines", [arXiv:1704.08539](https://arxiv.org/pdf/1704.08539).
  T0 でしか払えないコストの典型例（プロトコル設計時の攻撃者モデル）。
