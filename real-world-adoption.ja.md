# 実務導入ガイド

このリポジトリは、形式手法ツールを抽象的に順位付けするためのものではない。
実務で効く問いは次の形になる。

```text
このツールは、既存のどの開発作業を置き換える / 強化するのか?
```

目的は、壊れやすいレビュー会話、手書きのテスト表、曖昧な設計メモを、
反例を返す実行可能な成果物、または回帰防止の契約に置き換えること。

重要なのは、自然言語の仕様を後から形式手法に無理に翻訳することではない。
仕様を考える段階から、述語・関係・状態・遷移・不変条件・反例として
見られる単位に分解する視点を持つこと。

仕様やドキュメントがある場合は、それを期待仕様として置き、コードの実装との
矛盾を探す。仕様がない、または信用できない場合は、コードを de-facto 仕様として
読み、暗黙に決めている挙動を抜き出す。

どちらの場合も、最後は形式手法の結果をドメインの言葉へ戻す。
`sat`、`unsat`、trace、proof failure をそのまま見せるのではなく、
「誰が、何を、どの条件でできるのか」「どの注文が通るのか」
「どの crash 順序で更新が失われるのか」という確認質問に変換する。

英語版: [`real-world-adoption.md`](real-world-adoption.md)

## 何を置き換えるか

| いまの作業 | 置き換え / 強化先 | 主なツール | 出力 |
| --- | --- | --- | --- |
| branch guard / validator / feature flag / policy predicate の目視レビュー | 実装から抜いた述語を直接 solver にかける | Z3 / SMT-LIB | SAT/UNSAT と必要なら witness |
| spreadsheet 的な設定チェック | 矛盾設定、到達不能設定、dead config の網羅検査 | Z3 or Alloy | 不正設定の witness、または有限スコープでの不在証明 |
| RBAC、所有権、tenant、routing、workflow のホワイトボード図 | 関係モデル + 有限スコープ反例探索 | Alloy | バグを示す小さな具体例 |
| 「非同期処理はいつか解決するはず」という設計会話 | safety / liveness を持つ時間モデル | TLA+ | stuck / unsafe / unfair な trace |
| mock だらけの actor / message protocol テスト | 実行可能な state machine model と schedule 探索 | P | 再現可能な event schedule |
| 境界値が多い逐次ロジックの unit test | pre/postcondition と loop invariant | Dafny / MoonBit `moon prove` | 証明済み obligation、または失敗箇所 |
| データ構造の挙動に関する手書きの主張 | 抽象モデル + 表現不変条件 | MoonBit `moon prove`, Dafny, Why3 | 実装が abstract model を保つ API contract |
| 「この refactor は等価なはず」という勘 | old-vs-new の等価性 / 差分 query | Z3, Dafny, MoonBit `moon prove` | 等価性の証明、または差が出る入力 |
| コードや protocol 内の数学的前提 | 開いた帰納的 domain 上の対話的証明 | Lean 4 / Rocq | check 済み proof term を持つ定理 |
| 暗号 / security protocol の非形式的議論 | Dolev-Yao 型の symbolic protocol model | Tamarin / ProVerif | attack trace、または secrecy/authentication 証明 |

導入ルールは、「どの prover が最強か」から始めないこと。
まず、どの手作業が高コスト・曖昧・繰り返し壊れるかを見る。

## Z3 で仕様をモデルに落としてドメインに戻す流れ

注意点: Z3 は TLA+ のような temporal model checker ではない。
ここで言う「モデル検査」は、実装や仕様から抜いた述語を SMT の論理式に落とし、
`sat` / `unsat` / witness を取って検査する、という意味で使う。

流れは次の 7 段になる。

| 段階 | やること | 成果物 |
| --- | --- | --- |
| 1. ドメイン文を抜く | 「デジタル注文は email が空なら無効」のように、業務語で主張を書く | 自然言語の claim |
| 2. 入出力を決める | 判定に必要な値だけを残す。DB、HTTP、UI、framework は捨てる | `kind`, `email_len`, `total` など |
| 3. 純粋述語にする | 入力から `Bool` を返す `valid(...)` にする | 実装から抽出した decision function |
| 4. bad case を否定形で聞く | 「この悪い入力が valid になることはあるか?」を `assert` する | `check-sat` query |
| 5. 境界の positive case も聞く | 全部 `unsat` だとモデルが強すぎる可能性があるので、通るべき値も確認する | sanity witness |
| 6. broken variant を入れる | わざと guard を外した述語が `sat` になることを確認する | 検査が load-bearing である証拠 |
| 7. ドメイン語に戻す | `sat` / `unsat` を「誰が何をできる / できない」に言い換える | issue / 仕様確認 / regression contract |

この repo の `languages/z3/checkout_form.smt2` なら、実装から抜いた主張はこうなる。

```text
valid checkout:
  total > 0
  and (
    physical order requires shipping
    or digital order requires non-empty email
  )
  and unknown kind is rejected
```

Z3 には、業務語をそのまま渡さず、判定に必要な値だけを渡す。

```text
kind         : Int   -- 0 = physical, 1 = digital
has_shipping : Bool
email_len    : Int
total        : Int
```

SMT-LIB 側の核は `valid_checkout(...) -> Bool` になる。

```smt2
(define-fun valid_checkout
  ((kind Int) (has_shipping Bool) (email_len Int) (total Int))
  Bool
  (and
    (> total 0)
    (or
      (and (= kind physical_kind) has_shipping)
      (and (= kind digital_kind) (> email_len 0)))))
```

ここで大事なのは、「期待する仕様」を直接 `assert` するのではなく、
**破れてほしくない状況が存在するか** を聞くこと。

例: 「digital order は empty email で valid になってはいけない」なら、
Z3 には逆向きに聞く。

```smt2
(assert (valid_checkout digital_kind has_shipping email_len total))
(assert (<= email_len 0))
(check-sat)
```

結果の読み方:

| Z3 の答え | ドメイン語での意味 |
| --- | --- |
| `unsat` | empty email で valid になる digital order は存在しない。email guard は守られている |
| `sat` | empty email なのに valid になる入力が存在する。witness は bug report の材料 |
| `unknown` | この query では solver が答えられない。model を単純化するか、別の encoding にする |

`unsat` だけでは不十分。モデルを間違えて、どんな注文も通らない述語を書いても
bad case は全部 `unsat` になる。だから positive boundary も入れる。

```smt2
(assert (valid_checkout digital_kind false 1 1))
(check-sat)
```

これは domain 語では「email 長 1、total 1 の digital order は valid になれる」
という到達性確認になる。

さらに broken variant を入れる。

```smt2
; broken: digital branch accidentally accepts any digital order
(define-fun broken_checkout
  ((kind Int) (has_shipping Bool) (email_len Int) (total Int))
  Bool
  (and
    (> total 0)
    (or
      (and (= kind physical_kind) has_shipping)
      (= kind digital_kind))))
```

これに対して bad case が `sat` になれば、検査は実際に guard の欠落を捕まえる。
常に green になるだけの飾りではない、と確認できる。

最後に、solver の答えを domain owner に戻す。

| 機械の結果 | domain への言い換え | 次の扱い |
| --- | --- | --- |
| unknown kind valid が `unsat` | 未知の注文種別は fail-close している | 仕様として lock |
| digital empty email valid が `unsat` | デジタル注文は email 必須 | 仕様として lock |
| digital `email_len = 1` が `sat` | 最小の valid digital 注文は到達可能 | sanity case |
| broken variant が `sat` | email guard を消すと壊れる | 検査が効いている証拠 |
| extracted vs broken difference が `sat` | 現実装と壊した実装は観測可能に違う | refactor guard にできる |

会話にするとこうなる。

```text
実装から読む限り、注文種別は 0=physical, 1=digital です。
Z3 では「未知の kind が valid になる入力」は unsat でした。
つまり現実装は unknown kind を fail-close しています。
これは意図した API 契約ですか?

また、digital order で email_len <= 0 かつ valid になる入力も unsat でした。
一方で email_len = 1, total = 1 は sat なので、digital order 自体を
全拒否しているわけではありません。
```

この言い換えが重要。Z3 の成果物は `unsat` ではなく、
「未知の注文種別は fail-close する」「デジタル注文は email 必須」という
ドメイン契約である。意図なら仕様として残す。意図でなければ bug として直す。

## アプリケーションエンジニア向け具体例

### ネットワークの並行モデル

よくある現場の形:

```text
HTTP API -> DB transaction -> outbox table -> queue -> worker -> external API
```

レビューでよく出る主張は「retry しても二重決済しない」「DB に保存した注文は
いつか worker に届く」「payment が成功していない注文は ship されない」。
この手の主張は unit test では踏みにくい。ネットワークは message を落とす、
遅延させる、重複させる、順序を入れ替えるから。

モデルにするもの:

| 実装上の概念 | モデル上の state / action |
| --- | --- |
| request id / idempotency key | `requestId`, `seenRequests` |
| orders table | `orders[id] = Pending / Paid / Shipped / Cancelled` |
| outbox table | `outbox[id] = NotWritten / Written / Published` |
| queue | `queue` に message がある / ない |
| worker | `ReceiveMessage`, `CallExternal`, `Ack`, `Retry` |
| crash / restart | `CrashBeforePublish`, `RecoverAndScanOutbox` |

証明したい性質:

```text
AtMostOnceCharge       == 同じ requestId で外部決済が 2 回成功しない
NoShipWithoutPayment   == Paid でない order は Shipped にならない
CommittedEventuallyOut == DB commit 済み outbox は fairness の下でいつか publish される
```

使うツール:

| 問い | ツール |
| --- | --- |
| retry / timeout / crash / queue delivery の全順序を見たい | TLA+ |
| service を actor / state machine として実装に近く書きたい | P |
| service A から service B に到達できるか、SG / route / ACL の構造だけ見たい | Alloy |

出てほしい反例の例:

```text
1. API が DB commit する
2. outbox publish 前に crash
3. retry request が別 worker に入り、idempotency check が stale read
4. external charge が 2 回呼ばれる
```

この trace が出たら、対策は「conditional write」「idempotency key を決済側にも渡す」
「outbox は level-trigger scan にする」など、普通のアプリ設計の言葉で議論できる。

### スレッドモデルの説明

よくある現場の形:

```text
request handler threads + shared in-memory cache + background refresher
```

または:

```text
read current count -> check count < limit -> increment count
```

レビューでよく出る主張は「この lock で守られている」「atomic counter だから大丈夫」
「refresh 中の cache を request が読んでも問題ない」。ここで曖昧なのは、
どの read と write が一つの原子的操作なのか、どの値が stale でも許されるのか。

モデルにするもの:

| 実装上の概念 | モデル上の state / action |
| --- | --- |
| mutex / rwlock | `lock = Free / HeldBy(thread)` |
| shared counter | `count` |
| cache snapshot | `snapshotVersion`, `publishedSnapshot` |
| refresh 中の一時 map | `buildingSnapshot` |
| request thread | `Read`, `Check`, `Write`, `ServeFromCache` |
| background thread | `BuildSnapshot`, `PublishSnapshot` |

証明したい性質:

```text
NeverOverLimit == count <= limit
NoTornRead     == request が読む snapshot は常に単一 version
NoLostUpdate   == 2 thread の increment が片方消えない
```

使うツール:

| 問い | ツール |
| --- | --- |
| read/check/write の interleaving で race があるか | TLA+ |
| thread ではなく message actor に寄せられるか | P |
| lock 内の純粋な更新関数が invariant を保つか | Dafny / MoonBit `moon prove` |
| lock-free data structure や memory model まで証明したい | Rocq + Iris など。通常の app では重い |

出てほしい反例の例:

```text
limit = 1, count = 0
1. Thread A reads count = 0
2. Thread B reads count = 0
3. Thread A checks 0 < 1 and writes count = 1
4. Thread B checks 0 < 1 and writes count = 1
5. 2 requests were accepted, but count says 1
```

この反例は「counter の最終値が limit 以下」だけでは不十分で、
「accept した回数」と「record した count」が一致する必要がある、という
仕様の抜けを見せる。

### 認証・認可の健全性

よくある現場の形:

```text
JWT/session -> user -> org membership -> role -> resource ownership -> action
```

または multi-tenant SaaS:

```text
GET /orgs/:orgId/projects/:projectId
```

レビューでよく出る主張は「admin だけ settings を開ける」「別 tenant の resource は
読めない」「billing admin は invoice だけ読める」。この領域のバグは、実装の
if 文よりも、role / tenant / ownership / override の組み合わせで出る。

モデルにするもの:

| 実装上の概念 | モデル上の relation / predicate |
| --- | --- |
| users | `User` |
| organizations / tenants | `Org` |
| membership | `memberOf: User -> Org` |
| role | `role: User -> Org -> Role` |
| resource owner | `owner: Resource -> Org` |
| API action | `ReadProject`, `WriteProject`, `ReadInvoice`, `AdminSettings` |
| policy function | `allowed(user, action, resource)` |

証明したい性質:

```text
NoCrossTenantRead  == user が所属しない org の resource は読めない
AdminOnlySettings  == Admin 以外は settings action を実行できない
BillingIsScoped    == BillingAdmin は invoice は読めるが project write はできない
OwnerOverrideSafe  == owner override が tenant 境界を壊さない
```

使うツール:

| 問い | ツール |
| --- | --- |
| role / tenant / resource の組み合わせに穴があるか | Alloy |
| 実装から抜いた `allowed(...)` が特定の bad case を許すか | Z3 |
| policy 関数を code-level contract として lock したい | Dafny / MoonBit `moon prove` |
| permission lattice の単調性を将来の permission 追加後も証明したい | Lean |

出てほしい反例の例:

```text
User u is BillingAdmin in Org A
Project p belongs to Org B
Policy says BillingAdmin can ReadProject
Policy forgot owner(p) == currentOrg
=> u can read Org B project
```

ここで Alloy は `u`, `Org A`, `Org B`, `p` を持つ小さい world を出す。
そのまま issue に貼れる。「この override は意図か?」と domain owner に聞ける。

### config の無矛盾性

よくある現場の形:

```text
feature flag + rollout rule + allowlist + denylist + environment override
```

または:

```text
pricing rule / campaign rule / routing rule / alert threshold
```

レビューでよく出る主張は「この campaign は配信される」「prod ではこの endpoint に
route されない」「denylist は allowlist より強い」。config は code より変更頻度が高く、
しかも review が薄いので、形式検査の ROI が高い。

モデルにするもの:

| 実装上の概念 | モデル上の predicate |
| --- | --- |
| enabled flag | `enabled(config)` |
| environment | `env == Prod / Staging / Dev` |
| rollout percentage | `0 <= rollout <= 100` |
| allowlist / denylist | `user in allow`, `user in deny` |
| targeting condition | `country`, `plan`, `appVersion`, `createdAt` |
| priority | `denyWins`, `envOverrideWins` |

証明したい性質:

```text
NoDeadConfig       == 有効な config には少なくとも 1 つ対象 user が存在する
DenyWins           == allowlist と denylist の両方にいても deny される
NoProdDebugRoute   == prod traffic は debug backend に route されない
EquivalentRefactor == 新旧 config evaluator は全入力で同じ判定を返す
```

使うツール:

| 問い | ツール |
| --- | --- |
| 条件の矛盾、dead config、差分影響を witness 付きで見たい | Z3 |
| config が graph / relation 型で、到達性や ownership が重要 | Alloy |
| evaluator 実装そのものを contract として証明したい | Dafny / MoonBit `moon prove` |

出てほしい反例の例:

```text
config:
  enabled = true
  country == JP
  country != JP

=> NoDeadConfig が破れる。どの user も対象にならない。
```

別のよくある反例:

```text
user in allowlist
user in denylist
implementation checks allowlist first
=> denyWins が破れる
```

この場合は「allowlist が緊急解除なのか」「denylist が安全装置なのか」を
仕様として決める必要がある。形式検査はその会話を具体化する。

## 目的別に選ぶ

| 目的 | まず採用 | 使う条件 | 避ける条件 |
| --- | --- | --- | --- |
| 純粋述語の bad input を探す | Z3 | 実装にほぼ純粋な decision function があり、witness がほしい | 性質が event order や concurrency に依存する |
| 構造的な整合性を検査する | Alloy | domain が entity と relation: role, owner, tenant, route, graph reachability | 本当のバグが fairness、無限 queue、長時間の time にある |
| 非同期の safety を検査する | TLA+ | あらゆる action 順序で「悪いことが起きない」を見たい | 有限の関係モデルで同じ問題が早く出せる |
| 非同期の liveness を検査する | TLA+ | 「いつか良いことが起きる」と fairness 仮定が本質 | 意味のある progress property がない |
| 実装に近い actor protocol を検査する | P | system が typed message を投げ合う machine として自然に書ける | design-level model で十分 |
| 逐次コードの contract を証明する | Dafny | 関数を Dafny で書く / 写すことができ、pre/post/invariant を付けられる | production code が別言語で、翻訳コストを払えない |
| MoonBit 実装の contract を証明する | MoonBit `moon prove` | 実装が MoonBit で、contract と proof-only model を隣に置ける | Z3 のような model extraction や temporal exploration が必要 |
| 再利用する数学 / 型レベル性質を証明する | Lean 4 | theorem が有限スコープではなく、将来追加される値も含めて普遍的 | bounded counterexample で十分に意思決定できる |
| 成熟した proof ecosystem を使う | Rocq | CompCert, Iris, MetaCoq など Rocq 固有資産が必要 | Lean/mathlib でより低コストに足りる |
| C を書き換えずに検査する | CBMC / Frama-C | C codebase で、bounded check や ACSL annotation が合う | ロジックをもっと綺麗な pure model に切り出せる |
| Rust の ownership を意識して証明する | Verus | Rust 風の code + pre/post/ghost reasoning がほしい | 対象が Rust でない、または verifier subset を受け入れられない |

## 成果物別に選ぶ

| 残したい成果物 | 向くツール | 理由 |
| --- | --- | --- |
| 実 config file に対する CI validator | Z3 | config predicate を直接 encode でき、安定した exit code を返せる |
| design review 用の反例 | Alloy or TLA+ | 会話できる具体 instance / trace が出る |
| pure rule の regression guard | Z3 or Dafny | バグを見つけた後、その rule を lock できる |
| MoonBit code の regression guard | MoonBit `moon prove` | contract と実装を同じ package に置ける |
| 実行可能な protocol model | P | spec 自体が state machine と message になる |
| 実装から独立した長寿命の theorem | Lean 4 or Rocq | 実装を書き換えても proof artifact が残る |
| proof-carrying な data-structure API | MoonBit `moon prove`, Dafny, Why3 | representation を変えても abstract model を固定できる |

## 言語別に何を証明できるか

| 言語 / ツール | 得意な証明 | 実務 target | 反例の質 | repo 内の例 |
| --- | --- | --- | --- | --- |
| Z3 / SMT-LIB | supported theory 上の充足可能性、充足不能性、等価性 | validator, feature flag, eligibility, wire compatibility, config reachability | `get-model` を使うと高い。CI では SAT/UNSAT のみでもよい | `languages/z3/checkout_form.smt2` |
| Alloy 6 | 小さい scope における bounded relational fact と temporal assertion | RBAC, ownership, tenant isolation, workflow reachability, graph-shaped infra | 高い。具体 relation instance と graph visualizer がある | `languages/alloy/app-rbac.als`, `languages/alloy/multi-tenant.als`, `usecases/terraform-reachability/` |
| TLA+ / TLC | state transition と action interleaving 上の safety / liveness | distributed protocol, retry loop, background job, event sourcing, queue | 高い。action 名付きの番号付き trace が出る | `languages/tla/OrderCheckout.tla`, `languages/tla/ActorMailbox.tla` |
| P | actor state machine と message schedule 上の safety | actor protocol, device/service protocol, generated state-machine code | 高い。再現可能な schedule が出る | `languages/p/PingPong/` |
| Dafny | 逐次 program contract、loop invariant、algebraic datatype、ghost state | business-rule function, parser, normalizer, data transformation | 中。source location と failed obligation が出る | `languages/dafny/checkout_form.dfy`, `languages/dafny/rbac_screens.dfy` |
| MoonBit `moon prove` | MoonBit の function contract、loop invariant、`.mbtp` の abstract model、表現不変条件 | MoonBit library, validator, finance/domain operation, data structure | 中。model finder ではなく proof obligation failure が中心 | `languages/moonbit/checkout_form/` |
| Lean 4 | inductive type 上の普遍定理、数学構造、証明付き executable definition | permission lattice, type-level law, 実装より長く残る algorithm theorem | bug hunting には低い。最終 theorem の信頼性は高い | `languages/lean/Rbac.lean` |
| Rocq | 成熟した対話的証明、program semantics、Iris による separation logic、compiler/kernel 級の証明 | compiler correctness, concurrent data structure, mechanized semantics | quick counterexample には低い。proof artifact としては非常に高い | 未 probe |
| Why3 | 複数 prover backend に投げる verification-condition generation | shared verification backend, algorithm proof, hand-written WhyML | 中。backend / prover report に依存 | MoonBit `moon prove` が利用 |
| Verus | Rust 風の program verification と ghost/spec code | ownership-sensitive invariant を持つ Rust module | 中。verifier diagnostic が出る | 未 probe |
| Tamarin / ProVerif | symbolic security protocol の secrecy / authentication | login protocol, key exchange, token flow, adversarial message system | 高い。attack trace が出る | 未 probe |
| CBMC | bounded な C execution path | C function, embedded check, unwind bound 付き memory-safety assertion | 中。bounded trace が出る | 未 probe |

## 置き換えの順序

通常の product codebase を形式検査に寄せるなら、この順番で導入する。

1. pure predicate を抽出し、Z3 で実データに近い query を回す。
2. 構造的な domain rule を Alloy で model 化し、反例を集める。
3. order / fairness / liveness が load-bearing になった場合だけ、
   async protocol を TLA+ に移す。
4. 新しく書く逐次ロジックには Dafny または MoonBit `moon prove` で
   code-level contract を置く。
5. Lean / Rocq は、再利用する theorem や proof ecosystem がコストを
   正当化するときだけ使う。

この順番にすると、最初の成果物が bug class に近い。
多くの product team は、対話的定理証明に触る前に 1 と 2 だけで価値を得られる。

## この repo の読み方

| 問い | 入口 |
| --- | --- |
| 「まずどのツールを試すべきか」 | `verification-tools.md` |
| 「言語ごとの得意不得意を見たい」 | `book/tool-fit-map.md` |
| 「どの手作業を置き換えられるか」 | このファイル |
| 「各 probe から何を学んだか」 | `findings.md` |
| 「MoonBit prove と Z3 はどう違うか」 | `languages/moonbit/MOON_PROVE_CAPABILITIES.md` |
| 「どう実行するか」 | `README.md` と `justfile` |

実プロジェクトでの最終成果物は「証明の山」ではない。
次の ledger である。

```text
期待仕様 / 実装の主張 -> 機械検査 -> 反例または契約 -> domain 判断
```

domain owner が反例を「意図通り」と判断したなら、それは仕様として書く。
意図通りでないならバグとして直す。
