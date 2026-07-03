# 1. 仕様・実装・ドメインを突き合わせる

形式手法を実務で使うとき、最初に決めるのはツールではない。
**何を正として置き、何と何の矛盾を探すか** である。

仕様書、設計 docs、ADR、API 契約、テスト、コード、config、運用知識は、
どれも仕様の断片である。ただし、常に同じ重みでは扱わない。

## 2つの入り口

### 仕様や docs がある場合

仕様や docs が信頼できるなら、まずそれを期待仕様として置く。
コードは「その仕様を満たしているはずの実装」として読む。

```text
docs / spec:
  管理者だけが設定画面を開ける

implementation:
  role == Admin or featureFlag("settings_preview")

machine question:
  non-admin が settings に到達する input / trace はあるか?

domain question:
  settings_preview は非 admin にも設定画面を開かせる意図ですか?
```

この場合に探すのは、主に **仕様と実装の矛盾** である。

| 矛盾の型 | 例 | 次の確認 |
| --- | --- | --- |
| 仕様は拒否、実装は許可 | non-admin が設定画面に到達できる | docs が古いのか、実装が bug か |
| 仕様は許可、実装は拒否 | reviewer が draft を読めない | business rule が変わったのか |
| 仕様は必須、実装は任意 | digital order の email が空で通る | API 契約違反か、仕様の書きすぎか |
| 仕様は eventual、実装は lost update 可能 | crash 後に outbox が消える | 復旧保証を下げるのか、実装を直すのか |
| 仕様にない例外を実装が持つ | timeout 時だけ fail-open | 例外仕様として明文化するか |

重要なのは、形式手法の結果だけで「どちらが正しい」と決めないこと。
反例をドメインの言葉へ戻し、仕様を直すのか、コードを直すのか、両方を直すのかを確認する。

### 仕様がない、または信用できない場合

仕様がない場合は、実装を de-facto 仕様として読む。
これは「実装が正しい」と認めることではない。
まず現実に動いている挙動を抽出し、それが意図かどうかを問える形にするという意味である。

```text
implementation:
  empty allowlist は true として扱われる

machine question:
  allowlist が空の rule は全 user に match するか?

domain question:
  空の allowlist は「誰にも許可しない」ですか?
  それとも「制限なし」ですか?
```

この場合に探すのは、主に **実装が暗黙に決めている仕様** である。

| 実装から抜くもの | 例 | 次の確認 |
| --- | --- | --- |
| default | 未設定なら全許可 | 意図した fail-open か |
| error handling | parse 失敗を false に畳む | NOT と組み合わせて match しないか |
| boundary | `count < cap` か `count <= cap` か | cap 到達時に止めるのか |
| priority | deny より allow が先 | override の設計か |
| async timing | 判定後に記録する | 並行時の上限超過を許すか |

仕様がない現場でも、最後は必ずドメイン語へ戻す。
「コードがそうなっている」は仕様ではなく、確認質問の素材である。

## 共通フロー

仕様がある場合もない場合も、最終的な流れは同じである。

```text
1. 対象を選ぶ
   認可、config、queue、retry、state machine など事故になりやすい場所を選ぶ。

2. 正とする入力を決める
   docs を正とするのか、コードを de-facto 仕様として読むのかを明示する。

3. claim を抜く
   「何が許される」「何が禁止される」「いつか起きる」「絶対に起きない」を抜く。

4. モデル上の問いに変換する
   述語、関係、状態、遷移、不変条件、到達可能性、等価性に落とす。

5. 機械に反例を探させる
   Z3 / Alloy / TLA+ / P / Dafny / MoonBit prove / Lean / Rocq から選ぶ。

6. 結果をドメイン語へ戻す
   sat / trace / proof failure を、業務上の具体例として言い換える。

7. 修正対象を決める
   docs を直すのか、コードを直すのか、仕様と実装の両方を直すのかを確認する。

8. 契約として lock する
   意図した性質は CI の regression guard にし、次回の差分で壊れたら赤くする。
```

## 台帳の形

形式手法の成果物は、証明ログだけでは足りない。
実務では次の台帳にする。

```text
source:
  docs: 管理者だけが設定画面を開ける

implementation observation:
  settings_preview flag があると non-admin も settings route を通れる

model question:
  role != Admin and Reachable(Settings) は satisfiable か?

machine result:
  SAT

domain wording:
  preview flag を持つ非管理者が設定画面に到達できます。
  これは意図した公開範囲ですか?

decision:
  意図しないなら code bug。
  意図するなら docs に preview 例外を書き、監査ログ条件を追加する。

lock:
  決定後の性質を Alloy / Z3 / route test の CI に入れる。
```

この形にすると、形式手法を知らない人にも確認できる。
確認相手に見せるのは `SAT` や quantifier ではなく、
「誰が、何を、どの条件でできるのか」というドメイン上の文である。

## 修正先の判断

反例が出たとき、修正先は自動では決まらない。

| 状況 | 直す候補 |
| --- | --- |
| docs が現在の業務ルールと一致し、コードだけが外れている | コード |
| コードが意図した挙動で、docs が古い | docs / API 契約 / テスト名 |
| docs もコードも曖昧で、ドメイン判断が必要 | 仕様決定、次に docs とコード |
| 仕様は正しいがモデルが粗すぎる | モデル |
| 実装詳細を過剰にモデル化している | 抽象化をやり直す |

形式手法は「裁判官」ではなく、矛盾を具体化する道具である。
最終判断は、ドメインの言葉で合意された仕様に戻す。

## GitBook と skill の役割分担

この GitBook の目的は、読者が **モデル化できる問いを見分ける概念** を獲得すること。
具体的には、述語、関係、状態、遷移、不変条件、反例という見方を身につける。

将来の skill は、実作業の支援に寄せる。
skill が担うべきなのは、コードの性質とアプリケーションの目的から、
適切な支援ツールを選び、確認質問まで落とすことである。

```text
skill input:
  対象コード、docs、テスト、config、ユーザーの目的

skill decision:
  純粋述語か?
  関係モデルか?
  状態遷移か?
  並行 interleaving か?
  code-level contract か?

skill output:
  推奨ツール
  最小モデル
  期待する反例の型
  ドメイン確認質問
  CI に載せる regression guard
```

GitBook は概念の獲得、skill は現場での選定と実行。
両方が揃うと、読者は「なぜそのツールを使うか」を理解しつつ、
実際の repo では迷わず最小の検査から始められる。
