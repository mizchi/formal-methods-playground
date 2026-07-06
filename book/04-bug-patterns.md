# 5. 形式手法で記述できるバグパターン

この章は、論文や実務事例から「形式手法で書ける問い」の型を抜き出す。
全部をこの repo で実装する必要はない。目的は、アプリケーションエンジニアが
「これはモデル化できる」と気づけるパターンを持つことである。

研究の読み方として、自然言語の要求をいきなり形式言語に翻訳しない。
まず次の形に落とす。

```text
対象:
  何を観測するか。入力、状態、イベント、権限、trace、メモリ、鍵など。

claim:
  allowed / forbidden / eventually / never / equivalent / reachable /
  preserves invariant のどれか。

witness:
  反例が出たとき、ドメインの人に見せる最小の入力・関係・trace・ログ。

lock:
  バグなら回帰ガードにする。意図なら仕様として明文化する。
```

## 早見表

| パターン | 形式化する claim | 見つかるバグ | 主な道具 |
| --- | --- | --- | --- |
| config / policy の無矛盾性 | `exists bad input?` / `old == new?` | dead config、過許可、変更差分 | Z3 / SMT |
| 認可・関係モデル | `forbidden reachable?` | tenant 越境、role 例外漏れ、deny-all | Alloy / SMT |
| 分散・並行 state machine | `always invariant` / `eventually` | crash/retry race、lost update、stuck | TLA+ |
| event-driven protocol | `every event handled` / monitor safety | unhandled event、永遠に deferred、順序依存 | P |
| schedule robustness | `all schedules same observable result` | thread/order 依存、UI/event race | DPOR / model checking |
| log / trace conformance | `observed trace refines model` | 実装がモデル外の順序を出す、仕様漏れ | TLA+ / P / LTL mining |
| code-level contract | `pre -> post` / no panic | off-by-one、overflow、panic、loop invariant 不足 | Dafny / MoonBit prove / Verus |
| C/C++ bounded safety | `assert never fails within bound` | buffer overflow、pointer error、UB、assert violation | CBMC / Kani |
| model-code equivalence | `implementation == executable model` | parser/validator/authorizer の意味ズレ | Lean/Dafny + differential testing |
| security protocol | secrecy / authentication / freshness | replay、MITM、鍵漏れ、認証すり替え | Tamarin / ProVerif |

## 1. Config / policy の無矛盾性

自然言語の形:

```text
この設定で、意図しないユーザーが許可される入力は存在するか?
このポリシー変更は、旧ポリシーより許可範囲を広げていないか?
この allow と deny は矛盾していないか?
```

形式化:

```text
exists request:
  oldPolicy(request) == deny
  and newPolicy(request) == allow
```

見つかるバグ:

- missing / parse error / timeout 時だけ fail-open になる
- allowlist と denylist の重ね方で常に dead branch になる
- policy refactor で特定 tenant だけ権限が広がる
- deny-all になる設定を UI が生成できる

転用先:

- feature flag
- campaign eligibility
- RBAC / ABAC policy
- firewall / network policy
- migration 前後の validator equivalence

この型は Z3 / SMT が強い。Cedar Analysis は policy set の equivalence、
more permissive、less permissive、incomparable を SMT で分類する例であり、
「変更で誰の許可が変わったか」を witness として出す発想にそのまま使える。
SELinux RBAC policy を SMT に変換する研究も、over-permissive /
over-restrictive な misconfiguration を検出対象としている。

## 2. 認可・関係モデル

自然言語の形:

```text
ユーザーが所属していない tenant の resource に到達できるか?
Support は Settings を読めるが、write はできないか?
ownership graph に閉路や孤児 resource はないか?
```

形式化:

```text
exists user, resource:
  canRead(user, resource)
  and tenant(user) != tenant(resource)
```

見つかるバグ:

- tenant boundary の抜け
- role hierarchy の逆転
- 例外 role を足したときの write 権限漏れ
- refactor 後に deny rule が効かない

転用先:

- B2B SaaS の org / workspace / project / resource
- 管理画面の screen transition
- IAM policy diff
- user-controlled header / query param を信頼値に昇格する経路

Alloy は小さい world の関係 witness を出すのに向く。
Z3 / SMT は policy が関数や述語として書ける場合に向く。

## 3. 分散・並行 state machine

自然言語の形:

```text
どの crash / retry / network delay / reorder が起きても、二重処理しないか?
commit 済みデータは失われないか?
request を受けたらいつか応答するか?
```

形式化:

```text
NoDoubleCharge ==
  forall requestId:
    Cardinality({c in charges: c.requestId = requestId}) <= 1

EventuallyProcessed ==
  queued(job) => <> processed(job)
```

見つかるバグ:

- read-modify-write race
- outbox 書き込みと publish の分離による lost event
- retry 後の二重 external charge
- crash recovery で lock / lease が残る
- liveness をチェックしていないため stuck する

転用先:

- payment retry
- queue / worker
- event sourcing
- distributed lock
- leader election
- cache invalidation

AWS の TLA+ 事例では、S3 や DynamoDB などの分散アルゴリズムで、
通常の設計レビューやテストでは踏みにくい長い trace のバグが見つかっている。
この型は「happy path の設計」ではなく「何が常に守られるべきか」を
safety / liveness として先に書くのが要点である。

## 4. Event-driven protocol

自然言語の形:

```text
actor がどの順で message を受けても monitor の safety を破らないか?
ある state で受け取った event が unhandled にならないか?
defer した event が永遠に処理されないことはないか?
```

形式化:

```text
monitor NoAckBeforeCommit:
  observe Ack
  assert committed(requestId)
```

見つかるバグ:

- unhandled event
- ACK と commit の順序逆転
- callback が古い state を読む
- timeout と success が同時に来たときの二重遷移
- deferred event が starvation する

転用先:

- service 間 protocol
- workflow engine
- device / driver / controller
- WebSocket / streaming protocol
- actor runtime

P は actor を state machine と event で書き、model checker で schedule を探索する。
Microsoft の P 事例では USB driver stack の設計・実装に使われ、
event handling と responsiveness を検査対象にしている。

## 5. Schedule robustness

自然言語の形:

```text
同じ入力でも thread / event / callback の起動順で結果が変わらないか?
UI の保存順、broadcast 順、clone 順で可視結果が変わらないか?
```

形式化:

```text
forall scheduleA, scheduleB:
  sameInputs(scheduleA, scheduleB)
  => observableResult(scheduleA) == observableResult(scheduleB)
```

見つかるバグ:

- thread 起動順依存
- shared mutable state の last writer wins
- UI event handler の順序依存
- batch job の並列実行順で集計結果が変わる

転用先:

- React / UI event
- background job
- pub/sub handler
- spreadsheet-like calculation
- low-code / no-code workflow

SchedCheck は Scratch のような block-based event-driven program に対し、
実行順の違いで観測結果が変わる schedule-sensitive behavior を検出する。
この考え方は、アプリでも「同じ操作ログを別 schedule で replay して同じ結果か」
という回帰テストに転用できる。

## 6. Log / trace conformance

自然言語の形:

```text
本番ログに出た event 列は、モデル上で許される trace か?
incident trace は invariant violation の witness か?
テストから、まだ仕様化されていない LTL 性質を仮説として掘れるか?
```

形式化:

```text
observedTrace in Behaviors(Model)
```

見つかるバグ:

- モデルが実装の実順序を許していない
- 実装がモデル外の side effect を起こしている
- incident trace を再現できないため、モデルが役に立っていない
- mined spec が domain rule と違う

転用先:

- incident postmortem
- queue / saga / workflow trace
- API audit log
- migration replay
- model-code drift guard

LTL specification mining の survey は、desired / undesired traces から
temporal property を学習する研究を整理している。SysMoBench も、
AI 生成モデルの品質を syntax だけでなく、実装 trace への conformance と
invariant correctness で評価している。

## 7. Code-level contract

自然言語の形:

```text
この関数は全入力で postcondition を満たすか?
この loop は invariant を保つか?
この normalizer は idempotent か?
```

形式化:

```text
requires validInput(x)
ensures normalize(normalize(x)) == normalize(x)
ensures output in allowedRange
```

見つかるバグ:

- off-by-one
- 空配列 / nil / negative size の panic
- idempotency 破れ
- sort / normalize / encode の表現契約違反
- loop invariant が弱く、境界で壊れる

転用先:

- validator
- parser / serializer
- pricing / discount
- pagination cursor
- crypto wrapper ではない通常の business rule 関数

Dafny、MoonBit prove、Verus、Lean/Rocq はこの型に向く。
SpecGen のような研究は、LLM で候補 pre/postcondition を出し、
verifier と mutation / selection で仕様候補を絞る方向を示している。
ただし生成された仕様は仮説であり、domain owner の承認なしに契約化しない。

## 8. C/C++ / unsafe code の bounded safety

自然言語の形:

```text
この buffer access は bounds 内か?
この pointer は null / dangling にならないか?
この assert に到達する入力はあるか?
```

形式化:

```text
assert(index < len)
assert(ptr != NULL)
assert(!overflow)
```

見つかるバグ:

- buffer overflow
- pointer safety violation
- arithmetic overflow
- uninitialized memory
- bounded depth 内の assertion failure

転用先:

- C/C++ native extension
- Rust `unsafe`
- WASM runtime
- parser / codec
- crypto / compression / image library

CBMC は C program を bit-precise に式へ変換し、assertion violation を
bounded depth で探す。Rust 領域でも Kani のように CBMC backend を使う方向がある。
「bounded である」ことは弱点でもあるため、unwinding assertion や十分な bound を
台帳に残す。

## 9. Model-code equivalence

自然言語の形:

```text
実装 parser と executable model は同じ入力で同じ意味を返すか?
validator の proof は production code に接続されているか?
optimized code は数学仕様と同じ結果を返すか?
```

形式化:

```text
forall input:
  implementation(input) == model(input)
```

見つかるバグ:

- parser と model の enum 解釈違い
- missing application data の扱い違い
- namespace / prefix の正規化ミス
- optimized implementation の境界値ミス

転用先:

- authorization engine
- compiler / transpiler
- migration converter
- serialization format
- business rule engine

Cedar の Verification-Guided Development は、実行可能モデルを証明し、
production code とは differential random testing / property-based testing で
接続する。s2n / AWS-LC のような crypto 実装では、SAW / CBMC / HOL などを
組み合わせ、functional correctness、memory safety、constant-time などを
分けて証明している。

## 10. Security protocol

自然言語の形:

```text
攻撃者が network message を盗聴・改ざん・再送しても secret は漏れないか?
server が認証完了したなら、対応する client の開始 event が存在するか?
同じ nonce / token を replay して session を奪えないか?
```

形式化:

```text
Secrecy:
  never attackerKnows(sessionKey)

Authentication:
  ServerAccepts(client, data)
  => previously ClientStarted(client, data)
```

見つかるバグ:

- replay attack
- man-in-the-middle
- key compromise 後の forward secrecy 不足
- identity misbinding
- token freshness 不足

転用先:

- OAuth / OIDC extension
- webhook signing
- mTLS handshake policy
- device pairing
- invite token / password reset token

Tamarin / ProVerif は Dolev-Yao 型の symbolic attacker を置き、
secrecy、authentication、unlinkability などを trace property として調べる。
2026 年の taxonomy 研究は、ProVerif / Tamarin の最近の研究事例から
security property を分類し、実行可能な modeling pattern として整理している。

## 11. Continuous verification / drift guard

自然言語の形:

```text
この PR で、以前 lock した property はまだ成り立つか?
tool version / parser / expected result の変更で false red になっていないか?
実装が進化したのに model が古いままではないか?
```

形式化:

```text
previousClaim == currentClaim
and checkResult == expectedResult
and observedTrace refines Model
```

見つかるバグ:

- model-drift
- code-drift
- spec-drift
- harness-drift
- expected-result の更新漏れ

転用先:

- GitHub Actions の path filter
- expected SAT/UNSAT file
- incident trace replay
- policy diff bot
- model ledger

継続運用では「証明できた」だけでは足りない。
proof / model check / symbolic analysis を CI に置き、実装や仕様が変わったら
どの claim が変わったかをドメイン語で報告する必要がある。

## パターンを案件に転用する手順

1. 仕様文やコードから claim を 1 つ抜く。
2. claim を `allowed / forbidden / eventually / never / equivalent / reachable / invariant`
   のどれかに分類する。
3. witness の形を決める。入力、関係 instance、event trace、log trace、proof failure。
4. 一番小さい道具を選ぶ。predicate なら Z3、関係なら Alloy/SMT、時間なら TLA+/P、
   関数 contract なら Dafny/MoonBit/Verus、security protocol なら Tamarin/ProVerif。
5. 成立を証明したいのか、反例が欲しいのかを決める。
6. machine result をドメイン語に戻す。
7. 意図なら仕様化し、意図しないならバグとして修正し、CI に lock する。

## 参考文献・事例

- Chris Newcombe et al., "Use of Formal Methods at Amazon Web Services", 2014.
  TLA+ / PlusCal による分散システム設計検査の産業事例。
  <https://lamport.azurewebsites.net/tla/formal-methods-amazon.pdf>
- Amazon / Cedar, "How We Built Cedar: A Verification-Guided Approach", arXiv:2407.01688.
  実行可能モデル、証明、differential random testing、property-based testing を組み合わせる事例。
  <https://arxiv.org/html/2407.01688v1>
- AWS Open Source Blog, "Introducing Cedar Analysis", 2025.
  Cedar policy set の equivalence / more permissive / less permissive / conflict 分析。
  <https://aws.amazon.com/blogs/opensource/introducing-cedar-analysis-open-source-tools-for-verifying-authorization-policies/>
- Divyam Pahuja et al., "Automated SELinux RBAC Policy Verification Using SMT", arXiv:2312.04586.
  SELinux RBAC policy を SMT に変換し misconfiguration を検出する例。
  <https://arxiv.org/html/2312.04586v1>
- Ankush Desai et al., "P: Safe Asynchronous Event-Driven Programming", Microsoft Research, 2012.
  async event-driven system を state machine として書き、model checking する事例。
  <https://www.microsoft.com/en-us/research/publication/p-safe-asynchronous-event-driven-programming/>
- Yuan Si and Jialu Zhang, "SchedCheck: Schedule-Robustness Analysis for Event-Driven Block Programs",
  arXiv:2607.00623.
  event-driven program の schedule-sensitive behavior を検出する最新事例。
  <https://arxiv.org/html/2607.00623v1>
- Daniel Neider and Rajarshi Roy, "What is Formal Verification without Specifications?",
  arXiv:2501.16274.
  desired / undesired traces から LTL specification を mining する survey。
  <https://arxiv.org/abs/2501.16274>
- "SysMoBench: Evaluating AI on Formally Modeling Complex Real-World Systems",
  arXiv:2509.23130v3.
  syntax だけでなく trace conformance と invariant correctness を評価する benchmark。
  <https://arxiv.org/pdf/2509.23130>
- Lezhi Ma et al., "SpecGen", arXiv:2401.08807.
  LLM による formal program specification 生成と verifier feedback の研究。
  <https://arxiv.org/html/2401.08807v5>
- Daniel Kroening et al., "CBMC: The C Bounded Model Checker", arXiv:2302.02384.
  assertion violation、memory safety、equivalence などを bounded model checking する基盤。
  <https://arxiv.org/abs/2302.02384>
- João C. Pereira et al., "Protocols to Code", arXiv:2405.06074.
  SCION router で high-level protocol model と production Go code を接続して検証した事例。
  <https://arxiv.org/abs/2405.06074>
- Leonard Tudorache et al., "Bridging Theory and Practice: An Executable Taxonomy of
  Security Properties for ProVerif and Tamarin", arXiv:2605.29465.
  security protocol property の最近の taxonomy。
  <https://arxiv.org/abs/2605.29465>
- "AutoTam: Specifying Secure Protocol Implementations with Tamarin Model Generation",
  arXiv:2606.19937.
  Dolev-Yao attacker、Tamarin、unbounded protocol verification の整理。
  <https://arxiv.org/html/2606.19937v1>
