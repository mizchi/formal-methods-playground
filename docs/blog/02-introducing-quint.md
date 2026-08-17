# Quintで、実装の前にアプリケーションの振る舞いを書く

空のカートから決済を始めてはいけない。
キャンセルした注文を返金済みにしてはいけない。
決済処理中の注文をいつまでも放置してはいけない。

どれも注文処理では自然な規則だが、実装すると型、条件分岐、データベース更新、worker、timeout の設定へ分散する。
個々の関数が正しく見えても、操作の順序を変えたり、途中で失敗させたりすると、注文全体として矛盾した状態へ入ることがある。

`formal-methods-playground` では、この種の問題を実装前に調べるため、Z3、Alloy 6、TLA+、Quint で同じ題材を書き比べた。
その中で、アプリケーション層のロジックを最も少ない翻訳で書けたのが Quint だった。
注文の状態を型にし、操作の条件を action にし、起きてはいけない事故を Boolean 式にするまで、業務で使っている名前をほぼそのまま保てる。

以下では、一つの注文モデルを三段階で組み立てる。
形式手法や数学の知識は前提にせず、コードが何を許し、どのような反例を返すかから Quint の使いどころを見ていく。

## Quint とは何か

[Quint](https://quint.sh/) は、システムの状態、可能な操作、満たしたい性質を型付きのコードで記述する仕様記述言語である。
書いたモデルは型検査でき、具体的な操作列を実行でき、シミュレータやモデル検査器で多数の操作順序を調べられる。

Quint のモデルはプロダクション実装ではない。
データベースや HTTP を直接操作する代わりに、設計判断に必要な状態と振る舞いだけを取り出す。

言語の基礎には TLA+ と同じ Temporal Logic of Actions がある。
ただし、型、関数に近い定義、`all` や `any` といった構文、CLI と REPL が用意されているため、最初のモデルを書くために TLA+ の記法を先に覚える必要はない。

Quint は Informal Systems の内部プロジェクトとして始まり、blockchain や分散システムの設計に使われたあと、2026年に Informal Systems から独立した。
この出自から公式事例には blockchain が多いが、言語が扱うのは一般的な状態と操作であり、注文や決済にも同じ仕組みを使える。

## 例1：注文の状態と操作を書く

最初に、注文が取りうる状態と、checkout 前後で変化する値を宣言する。

```quint
type OrderState =
  | Cart
  | PaymentPending
  | Paid
  | Shipped
  | Refunded
  | Cancelled

var state: OrderState
var cart: Set[str]
var refunded: bool

action init = all {
  state' = Cart,
  cart' = Set(),
  refunded' = false,
}

action checkout = all {
  state == Cart,
  cart != Set(),
  state' = PaymentPending,
  cart' = cart,
  refunded' = refunded,
}

action paymentSucceeded = all {
  state == PaymentPending,
  state' = Paid,
  cart' = cart,
  refunded' = refunded,
}
```

`OrderState` にない値は `state` へ入らないため、未定義の状態や状態名の綴り間違いは型検査で止まる。
`checkout` は、現在の状態が `Cart` で、カートが空ではない場合にだけ使える。
操作後の状態は `PaymentPending` になり、カートと返金済みフラグは変化しない。

`paymentSucceeded` は `PaymentPending` からだけ `Paid` へ進める。
これにより、「空のカートを checkout できないか」「決済成功を `Cart` から直接呼べないか」という規則が action の入口に現れる。

ここで `state'` は変数への逐次的な代入ではなく、次の状態における `state` を表す。
`all` の中にある式にも上から下への実行順序はなく、すべての条件を満たす現在状態と次状態の組を定義している。

見た目は通常のコードに近いが、書いているのは処理手順ではなく、操作の前後に成り立つ条件である。
この違いだけ理解すれば、型名や action 名にはアプリケーションで使っている語彙をそのまま置ける。

## 例2：キャンセルと返金の取り違えを探す

型が正しくても、業務上ありえない値の組み合わせは作れる。
このモデルでは、返金済みフラグが立っている状態を `Refunded` に限定する。

```quint
val refundedOnlyInRefundedState = refunded implies state == Refunded
```

これは、到達可能な各状態で真であってほしい**不変条件**である。
返金処理の履歴全体ではなく、現在の `refunded` と `state` の組み合わせだけを検査する。

通常のキャンセルでは、`refunded` の値を変えない。

```quint
action cancelCart = all {
  state == Cart,
  state' = Cancelled,
  cart' = cart,
  refunded' = refunded,
}
```

比較のため、キャンセル時に誤って `refunded = true` とする action を用意する。

```quint
action brokenCancelCart = all {
  state == Cart,
  state' = Cancelled,
  cart' = cart,
  refunded' = true,
}

action brokenStep = any {
  step,
  brokenCancelCart,
}
```

`step` は正常な action の選択肢であり、`any` はその選択肢へ破壊版を追加する。
`brokenStep` を検査すると、TLC は次の2状態からなる反例を返す。

```text
Cart(refunded = false)
  -> brokenCancelCart
Cancelled(refunded = true)
```

反例は、型エラーでは表せない業務上の矛盾を、そこへ到達した操作と一緒に示す。
個別の action が `refunded` を正しく扱うことだけに頼らず、注文全体で守りたい条件を独立して置くため、同じ事故が別の action に入っても検出できる。

意図的に壊したモデルが失敗するかを確かめる**負例**は、不変条件が実際に検査対象へ接続されていることも確認する。
正常なモデルが成功することだけを調べると、性質の指定漏れや検査設定の間違いがあっても気づけない。

## 例3：決済処理が止まり続ける実行を探す

例2の不変条件は一つの状態を見れば違反を判定できる。
一方、「決済を始めたらいつか結果が出る」という要件は、現在の状態だけでは判定できない。

**時相論理**は、一つの状態ではなく、初期状態から続く状態の列について性質を記述する。
ここでいう時間は秒や日時ではなく、状態が現れる順序である。
「30秒以内」を扱う場合は、経過時間や残り時間をモデルの状態へ追加する。

この例を読むために押さえておきたい演算子は次の二つである。

| Quint | 読み方 | 状態列に対する意味 |
| --- | --- | --- |
| `eventually(P)` | いつか P | 現在または将来のどこかで P が成り立つ |
| `P leadsTo Q` | P ならいずれ Q | P が現れるたび、その位置以降で Q が成り立つ |

`P leadsTo Q` は、P から Q へ一度だけ移れるという意味ではない。
実行中に P が現れるたび、その後に Q が必要だと述べている。

注文モデルでは、決済処理が解消する条件を次のように書いた。

```quint
val vars = (state, cart, refunded)

temporal paymentResolves =
  and {
    paymentSucceeded.weakFair(vars),
    paymentFailed.weakFair(vars),
    paymentTimeout.weakFair(vars),
  }
    implies (state == PaymentPending leadsTo state.in(Set(Paid, Cart, Cancelled)))
```

右辺は、`PaymentPending` になった注文が、いずれ `Paid`、`Cart`、`Cancelled` のどれかへ移ることを要求する。
左辺の `weakFair` は、各 action が有効なままなら、いつまでも無視され続けないという**弱公平性**を仮定する。

なぜこの仮定が必要なのかを確かめるため、fairness を外した性質も用意した。

```quint
temporal paymentResolvesWithoutFairness =
  state == PaymentPending leadsTo state.in(Set(Paid, Cart, Cancelled))
```

TLA の状態列は、観測している変数が何も変わらない**stuttering**を許す。
そのため、成功、失敗、timeout の action が使える状態でも、どれも選ばず `PaymentPending` に留まり続ける実行が存在する。
TLC はこの実行を反例として返す。

fairness はモデル検査器が実システムへ追加してくれる機能ではない。
アプリケーションで進行を要件にするなら、worker のスケジューリング、message の再送、timeout の発火、監視後の復旧など、それを支える仕組みが実装または運用に必要になる。
Quint では、その運用上の前提も性質の一部としてレビューできる。

## 実際にモデルを検査する

Quint の各 command は、同じモデルに対して異なる問いを扱う。

| command | 調べるもの | 成功結果の意味 |
| --- | --- | --- |
| `quint typecheck` | 名前、型、定義モードの整合性 | モデルが静的な規則を満たす |
| `quint run` | 無作為に選んだ有限本の実行 | 調べた sample では違反を観測しなかった |
| `quint test` | 記述した scenario または非決定的な test | 指定した条件と assertion が通った |
| `quint verify` | backend の範囲にある実行 | 指定した範囲で反例が見つからなかった |

リポジトリでは次のコマンドで型検査、正常モデルの検査、二つの負例をまとめて実行できる。

```sh
nix develop -c just check-quint
```

Quint 0.32.0 と TLC backend を使った実行では、55状態が生成され、重複を除いた20状態を深さ6まで検査した。
正常なモデルでは、例2の不変条件と例3の時相的性質に違反は見つからなかった。

同じ script は、`brokenCancelCart` が不変条件を破ることも確認する。
さらに、fairness を外した時相的性質が `PaymentPending` での stuttering によって破れることも確認する。

成功させたいモデルと失敗させたいモデルを同じ入口から検査することで、モデルと検査設定の両方を回帰テストにできる。

## Quint がアプリケーションロジックを書きやすい理由

三つの例で使った名前は、`Cart`、`PaymentPending`、`checkout`、`refunded` といった注文処理の語彙だった。
専用の数学記号へ置き換えず、型、集合、Boolean、関数に近い見た目で状態と操作を表せる。

モデルのレビューで話したいのは、空のカートを決済できるか、キャンセルと返金が矛盾しないか、決済処理が止まらないかという設計判断である。
Quint の表面では型、action、不変条件が分かれているため、これらの問いが実装の条件分岐や infrastructure の設定に埋もれにくい。

一方、Quint のコードを命令型プログラムとしては読めない。
`all` は論理積、`any` は選択肢、primed variable は次状態の値を表す。
読みやすさは通常のコードと同じ実行規則を持つことではなく、業務の名前を保ったまま現在状態と次状態の関係を書けることから生じる。

Quint が直接検査するのはモデルであり、プロダクション実装全体ではない。
永続化、通信、時刻、並行実行をどこまで状態へ含めたかによって、検査できる範囲が決まる。

反例やシミュレーションの trace は ITF 形式で出力できる。
[Quint Connect](https://github.com/quint-co/quint-connect) を使うと、その trace を実装へ再生し、モデルから取り出した状態とのずれをテストできる。
ただし、比較できるのは driver と state projection が対応づけた範囲であり、実装全体の証明にはならない。

## どんな問題に使えるか

Quint は、状態、可能な操作、操作順序によって起きる事故を有限の語彙へ抽象化できる問題に向いている。
アプリケーション層から分散システムまで、対象の大きさが変わっても書く要素は同じである。

| 対象 | モデルに置くもの | 検査する性質の例 |
| --- | --- | --- |
| 注文、決済、申請 | status、操作条件、cancel、timeout | 禁止された状態遷移を通らない |
| queue と job worker | pending、in-flight、ack、retry | job を失わず、副作用を重複させない |
| saga | payment、inventory、shipping、compensation | 一部だけ確定した終端状態へ入らない |
| service 間 protocol | request、response、retry、cancel | cancel 後に処理を確定しない |
| control plane | desired state、observed state、reconcile | 障害後に矛盾のない状態へ収束する |
| replication と election | log、term、leader、crash、recovery | leader が重複せず、確定値を失わない |

Quint の公式事例に blockchain が多いのは、consensus、replication、message ordering、障害復旧を同時に扱う必要があるためである。
これらの問題は blockchain 固有ではなく、通常の backend や非同期 workflow にも現れる。

対象に時間や操作順序がなければ、別の道具の方が短く書ける。
性能値、UI の使いやすさ、外部 API の実際の信頼性も、対応する状態と遷移を定義しないまま Quint へ渡せる性質ではない。

## TLA+、Alloy 6、Z3との使い分け

`formal-methods-playground` では、最初から Quint だけを試したわけではない。
同じ問題でも、何を探したいかによって適した道具は変わる。

| 問い | 選ぶ道具 | 理由 |
| --- | --- | --- |
| 一つの入力条件や設定に矛盾があるか | Z3 | 判定条件を直接制約として渡せる |
| 利用者、権限、所有の関係に越権できる構造があるか | Alloy 6 | 有限の関係をグラフとして調べやすい |
| 操作順序が安全か、処理がいつか進むか | Quint | 型付きのアプリケーション語彙で状態遷移を書ける |
| 既存の TLA+ module や高度な refinement を扱うか | TLA+ | 既存資産と TLA+ の機能を直接使える |
| 有限探索に依存しない一般的な法則を証明するか | Lean 4 や Rocq | 定理と証明を構成できる |

Quint と TLA+ は、能力が競合する部分が多い。
たとえば例1の `checkout` は TLA+ では次のように書ける。

```tla
Checkout ==
    /\ state = "cart"
    /\ cart # {}
    /\ state' = "paymentPending"
    /\ UNCHANGED <<cart, refunded>>
```

Quint の `all` と TLA+ の `/\` は、どちらも複数の条件が同時に成り立つことを表している。
Quint の action が命令型の関数ではない点も TLA+ と同じである。

私が新しいアプリケーションの状態遷移に Quint を選ぶのは、TLA+ にできない検査があるからではない。
直和型、変数の型、action の区別があり、普段のコードに近い形で業務の名前を読めるからである。

既存の TLA+ module、PlusCal、TLAPS、細かな TLC 設定、高度な refinement が必要なら TLA+ を直接使う。
そのため、Quint を TLA+ の全面的な置き換えとは考えていない。

個人的な最初の選択肢は Alloy 6、Quint、Lean 4 の三つに落ち着いた。
構造を探すなら Alloy 6、振る舞いを探すなら Quint、有限の探索から取り出した法則を証明するなら Lean 4 を使う。

Quint はこの中で、実装へ進む前のアプリケーションの状態遷移を置く場所になる。
最初から大きな仕様を書くのではなく、一つの事故を表す不変条件と、その条件が実際に破れる負例から始めるのがよい。
反例を業務の言葉で説明できたとき、モデルは設計レビューで使える成果物になる。

## 補足：Apalache、TLC、Z3の関係

`quint verify` は、Quint だけで検査を完結させる command ではない。
選んだ backend に応じて Apalache または TLC と連携する。

| 名前 | 役割 |
| --- | --- |
| Quint | `.qnt` を解析し、名前と型を検査して backend へ渡す |
| Apalache | 一定の step 数までの遷移を SMT 制約へ変換する |
| Z3 または CVC5 | Apalache が作った制約を満たす値があるか判定する |
| TLC | 有限化された到達可能状態を列挙し、時相的性質も検査する |

Apalache backend を使う経路は、概念的には次のようになる。

```text
.qnt source
  -> Quint: parse, typecheck, flatten modules
  -> Apalache IR
  -> Apalache: unroll transitions and encode SMT constraints
  -> Z3 or CVC5
  -> result and counterexample trace
```

Quint が作るのは、型を解決したモデルの内部表現である。
Apalache は初期状態、各 step の遷移、どこかで不変条件が破れるという条件を一つの制約へ組み立てる。
Z3 や CVC5 は、そのすべてを満たす状態列が存在するかを判定する。

解があれば、指定した step 数の中に違反する実行があり、各 step の値から反例 trace を復元できる。
解がなければ、その step 数と encoding の範囲には反例がない。
任意の長さの実行やプロダクション実装全体を証明したという意味ではない。

同じ安全性を Apalache で6 step まで調べる command は次のようになる。

```sh
nix develop -c quint verify languages/quint/OrderCheckout.qnt \
  --main OrderCheckout \
  --invariant typeOk,refundedOnlyInRefundedState \
  --max-steps 6
```

一方、TLC backend はこの経路で Z3 を使わない。
Quint のモデルを TLA+ へ変換し、有限化された到達可能状態を列挙する。
この注文モデルのように状態空間が小さく、fairness を含む時相的性質を調べたい場合に使える。

## 参考資料

- [Quint公式サイト](https://quint.sh/)
- [QuintがInformal Systemsから独立した経緯](https://quint.sh/posts/new_era)
- [Quintは何をするか](https://quint.sh/docs/what-does-quint-do)
- [Quintで性質を検査する](https://quint.sh/docs/checking-properties)
- [Quintの言語基礎](https://quint.sh/docs/language-basics)
- [Quintの時相演算子](https://quint.sh/docs/builtin#always)
- [QuintとTLA+の比較](https://quint.sh/faq)
- [Quintのモデル検査器](https://quint.sh/docs/model-checkers)
- [Quint transpilerの処理段階](https://github.com/quint-co/quint/blob/main/docs/content/docs/development-docs/architecture-decision-records/adr001-transpiler-architecture.md)
- [ApalacheとTLCの違い](https://apalache-mc.org/docs/apalache/index.html)
- [Apalacheのassignmentとsymbolic transition](https://apalache-mc.org/docs/apalache/principles/assignments.html)
- [Apalache IR JSON](https://apalache-mc.org/docs/adr/005adr-json.html)
- [`OrderCheckout.qnt`](../../languages/quint/OrderCheckout.qnt)
- [QuintとTLA+の`OrderCheckout`比較](../../languages/quint/README.md)
- [Quint周辺ツールの実動評価](../quint-ecosystem-evaluation.md)
- [個人的な形式手法ツール選択基準](../personal-tool-selection.md)
