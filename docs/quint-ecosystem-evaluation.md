# Quint 周辺ツールの実動評価

> Status: hands-on evaluation, 2026-08-05
>
> Subject: Quint LLM Kit、Choreo、Quint Connect、Quint Trace Explorer

## 結論

Quintを個人的なfirst choiceにする判断は維持する。ただし、4つの周辺toolを一括して
「Quintの機能」と評価するのではなく、別々のmaturityとtrust boundaryを持つ部品として採用する。

| tool | 実際に試したこと | 得られた価値 | 判断 |
| --- | --- | --- | --- |
| Quint LLM Kit | 公式review workflowをChoreoの2PC modelへ適用 | witness、action粒度、invariant、実行結果の言い方を揃えられる | checklistとskillを部分採用 |
| Choreo | 公式2PCをtypecheckし、commit scenarioを実行 | distributed protocolのstate、message、effectを共通構造へ載せられる | 通信が主役のmodelで選択的に使う |
| Quint Connect | 公式2PCのRust実装と、OrderCheckoutのMoonBit runtime adapterで正常・破壊実装をreplay | 両言語でspecと実装のstate driftを検出し、MoonBitではtrace生成・複数trace・named testまで接続した | Rustでは公式library、他言語では明示的なruntime adapterを候補にする |
| Trace Explorer | ChoreoのITF traceをTUIで開き、差分表示を操作 | 次stateで変わったbranchを追いやすい | local debug用の任意tool |

今回もっとも強い結果はQuint Connectである。正常実装は通り、participantが`Commit`を受けた後に
誤って`Aborted`へ進むよう変更した実装は、specの`Committed`とのstate divergenceとして失敗した。
「便利そう」ではなく、意図した誤りに対する識別力をpositive/negative controlで確認できた。
同じ考え方をMoonBitでも試し、`cancelCart`の`Cancelled`対`Refunded`を検出できた。

## 再現方法

```sh
nix develop -c just evaluate-quint-ecosystem
```

このtaskは公式ecosystem側について次を順に実行する。

1. pinしたLLM Kitのreview contractを確認する
2. Choreoの公式2PCをtypecheckする
3. deterministicな`commitTest`を実行し、8 stateのITFを出力する
4. `consistency` invariantを20 step、1,000 sampleで探索する
5. Quint Connectで正常なRust実装をreplayする
6. [`broken-connect.patch`](../experiments/quint-ecosystem/broken-connect.patch)を適用し、失敗を要求する
7. 同じITFをTrace Explorerで開き、pseudo-terminalから正常終了できることを確認する

Rust dependencyの初回取得とbuildを含むため、通常の`check-ci`からは意図的に分離している。
source revisionは`flake.lock`で固定しているが、crate cacheがなければnetwork accessが必要になる。

MoonBit adapterは独立repo側の通常checkに含めて再現する。ghq上で両repoが隣接している場合は次で実行できる。

```sh
cd ../quint-connect-moonbit
nix develop -c just check
```

## 評価条件

4 repositoryの`main`を追わず、次のrevisionで実験を固定した。

| source | revision |
| --- | --- |
| [Quint LLM Kit](https://github.com/quint-co/quint-llm-kit/tree/cc75369f741af7d490936f82002c2d28e3b3d78d) | `cc75369f741af7d490936f82002c2d28e3b3d78d` |
| [Choreo](https://github.com/quint-co/choreo/tree/000cf4eed315187dc6f216a148781cff7dde6521) | `000cf4eed315187dc6f216a148781cff7dde6521` |
| [Quint Connect](https://github.com/quint-co/quint-connect/tree/4f018f54fc7dd4cef341d10111427bab59d3b307) | `4f018f54fc7dd4cef341d10111427bab59d3b307` |
| [Quint Trace Explorer](https://github.com/quint-co/quint-trace-explorer/tree/d6b3d1fddea79f93bb8cca9fbc70b508e49e8e48) | `d6b3d1fddea79f93bb8cca9fbc70b508e49e8e48` |

題材はこのrepositoryに新しいtoy modelを作らず、ChoreoとConnectがそれぞれ公式exampleとして持つ
two-phase commitに揃えた。両者は概念上同じprotocolだが、ConnectがChoreoから出力したITFを直接
読むわけではない。model authoring、実装replay、trace reviewの各工程を比較し、境界を評価した。

## Quint LLM Kit

### どう使ったか

LLM Kitに新しいmodelを生成させるのではなく、pinした
[`review.md`](https://github.com/quint-co/quint-llm-kit/blob/cc75369f741af7d490936f82002c2d28e3b3d78d/quint-llm-kit-plugin/skills/quint-modeling/guidelines/review.md)
をそのままreview contractとして使い、Choreoの公式2PCを検査した。新規model生成workflowは、
型と状態のsketchを人間が承認してから実装へ進む設計なので、既存modelの評価に無理に混ぜなかった。

| review項目 | 結果 | 根拠 |
| --- | --- | --- |
| thin action | おおむね良い | transitionがcoordinator、participant、message処理へ分かれている |
| enumでdomainを閉じる | 良い | nodeとstageが有限のvariantとして表現される |
| stateをrecordでまとめる | 良い | Choreoのsystem stateに集約される |
| meaningful invariant | 良い | coordinatorとparticipantの終端状態を結ぶ`consistency`がある |
| positive scenario | 良い | commit pathを固定した`commitTest`が8 stateで完走する |
| per-action witness | 不足 | `wit_commit`はあるが、全actionを個別に到達させるwitness setではない |
| runtime resultの表現 | 要注意 | sample実行で反例がないことをproofと書かない |

### 評価

LLM Kitの価値は、LLMがQuint syntaxを生成することより、model reviewの順序と結果の語彙を固定する
点にある。特に「反例を観測した」「実行したsampleでは反例を観測しなかった」「証明した」を
分ける規則は、このrepositoryのpositive/negative control方針と一致する。

一方、checklist自体はcorrectness oracleではない。今回も公式exampleにper-action witnessの不足を
見つけたが、これはprotocolが誤っているという意味ではない。LLM Kitは設計・review skillとして使い、
合否は`quint typecheck`、`test`、`run`、必要に応じて`verify`へ委ねる。

## Choreo

### 観測した結果

- 公式two-phase commit modelは現行Quintでtypecheckできた
- `commitTest`は1 testを通過し、初期stateを含む8 stateのITFを生成した
- `consistency`は20 step、1,000 sampleの範囲で反例を観測しなかった
- これはsimulation結果であり、全状態空間に対する証明ではない

### 良かった点

message soup、node local state、global environment、effectという語彙が最初から用意されている。
2PCのように「誰がどのmessageを受け、どのlocal stageへ移るか」が主語になるmodelでは、projectごとに
network semanticsを発明せずに済む。実装接続に必要なaction名と状態の境界も読み取りやすい。

### 気になった点

traceのstateは`choreo` frameworkのsystem、messages、extensionsなどを含み、plain Quintより深くなる。
小さいapplication workflowではdomain logicよりframeworkの構造が目立つ。公式2PCにも全transitionの
per-action witnessはないため、libraryを使うだけでcoverageが得られるわけではない。

採用基準は「distributedであるか」ではなく、「message deliveryとnode local stateのscaffoldingが
modelの相当部分を占めるか」とする。2PC、consensus、replication、leader electionには合うが、
現在の`OrderCheckout`はplain Quintの方がよい。

## Quint Connect

### Positive control

pinした公式two-phase commit exampleに含まれる2 testを実行した。named commit scenarioと
simulation traceの双方で、Quint stateとRust実装から射影したstateが一致した。

### Negative control

Rust participantの次のtransitionだけを壊した。

```text
receive Commit: Committed  ->  Aborted
```

同じConnect testは`Specification and implementation states diverge`および
`State invariant failed`として失敗した。build failureや無関係なpanicではなく、狙った
`Committed`対`Aborted`の差を検出したこともlog patternで確認している。

### 評価

Connectは4 tool中、既存のverification workflowへ最も具体的な追加価値を持つ。modelの反例探索だけで
終わらず、review済みscenarioを実装へreplayしてspec driftをregression testにできる。

ただし、今回比較したobservable stateは各nodeの`stage`である。message queue、clock、外部I/Oなど、
`State::from_driver`で射影しない状態は比較されない。また`Driver::step`のaction mapping自体が誤れば
testの意味も変わる。この2つをAPI contractとしてreviewする必要がある。公式版はRust libraryなので、
Rust実装があり、domain stateを安定して射影できるuse caseから採用する。

### MoonBit adapter probe

公式Rust APIのattribute macroを移植せず、Quint processを起動してITFを生成・replayするruntime
adapterを独立repo [`mizchi/quint-connect-moonbit`](https://github.com/mizchi/quint-connect-moonbit)の
MoonBit package `mizchi/quint_connect`として作った。
generic部分はrun / test設定、process runner、ITF decode、replay loopに、domain部分はaction mappingと
state projectionに分けた。seed、複数trace、traceごとのfresh driver、nested state path、custom
sum-type action path、stateless replayもcontractとして実装した。

固定seed `0x1234` で`OrderCheckout.qnt`から生成した8 traces / 34 statesは正常driverですべて一致した。
named `cancelTest`もnested stateとcustom actionを使って1 trace / 2 statesが一致した。対して、MoonBit側の
`cancelCart`だけを`Refunded`へ変える負例は、どちらの経路でも期待した`Cancelled`との差を
`StateDiverged`として検出した。これにより、Connectのruntime patternはRust固有ではなく、process起動と
ITFを扱える言語なら再構成できると判断した。

ただし公式Connectと同等ではない。MoonBit版はattribute macro、derive / Serde相当のtyped conversion、
trace shrinkingを持たず、実network、clock、concurrent I/Oを含むdriverも未評価である。またQuint 0.32の
Rust backendでmulti-traceの初期action名が不安定になるケースを観測したため、再現taskではTypeScript
backendをdefaultにした。

## Quint Trace Explorer

### 観測した結果

Choreoの`commitTest`が生成した8 stateのITFを実際にTUIで開いた。通常表示ではChoreo由来の
入れ子が深いものの、side-by-side diffでstate 1からstate 2へ進むと、変化した`messages`と
participant `p1`のbranchに表示が絞られた。CLIのJSONや全state dumpより「このstepで何が変わったか」
を読む負荷は低い。

自動probeはpseudo-terminalで同じITFを開き、`q`で正常終了できるところまでを確認する。
画面の読みやすさは人間による観測であり、snapshot testにはしていない。

### 評価

反例が長い場合のlocal debug UIとして有用である。一方、terminal前提でCI artifactとして共有しにくく、
README自身もtoy projectと位置づけている。canonical ITF parserや検査結果の判定には使わず、壊れても
Quint coreの検査を妨げないoptional toolにする。単独の`nix run`はRust dependencyを含む大きな初回buildに
なったため、日常利用ではdev shellのCargo cacheかbinary distributionの有無も評価対象になる。

## 採用方針

優先順位は次のように更新する。

1. Quint coreとnamed scenario、negative controlを先に安定させる
2. Rust実装では公式Quint Connect、他言語では明示的なruntime adapterを小さく導入する
3. message中心の新規modelだけChoreoで始める
4. LLM Kitのreview・witness規律をagent workflowへ取り込む
5. Trace Explorerは長い反例を読む人が任意で使う

この結果はQuintをfirst choiceにする理由を補強するが、Choreo、Connect、Trace Explorerのmaturityまで
Quint coreと同一視はしない。特にConnectのdriver/state projectionとChoreoのenvironment semanticsは、
domain modelとは別のreview対象としてversionを固定する。

## 今回確認していないこと

- exhaustive model checkingによる2PCの証明
- real network、clock、concurrent I/Oを含むRust / MoonBit implementation
- repository固有のproduction protocolへの適用コスト
- LinuxとmacOSをまたぐTrace Explorerの表示互換性
- LLM Kitの各host、MCP server、Docker imageの比較
- upstream更新時のmigration cost

したがって、これは採用可否を決める最小probeであり、production readinessの認定ではない。

## Decision ledger

| 項目 | 記録 |
| --- | --- |
| source | pinした4つの公式repository |
| observation | Choreoの8 stateをTrace Explorerで開き、Rust公式2PCをreplayした。MoonBitでは生成8 traces / 34 statesとnamed test 1 trace / 2 statesをreplayした |
| negative control | Rustでは`Committed`を`Aborted`へ、MoonBitではgenerated / named両経路で`Cancelled`を`Refunded`へ壊すとspec driftを検出した |
| sampled claim | `consistency`は20 step、1,000 sampleで反例を観測しなかった |
| proof claim | 今回は2PCのexhaustive verificationを実行していない |
| decision | Rustでは公式Connectを優先し、他言語では明示的なruntime adapterを評価する。ChoreoとLLM Kitは選択的採用、Trace Explorerは任意debug toolにする |
| trust boundary | LLM review、Choreo semantics、Connect mapping/projection、ITF viewer |
