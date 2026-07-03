# 0. モデル化できる問いとして考える

形式手法は、自然言語で書いた仕様を後から無理に翻訳する道具ではない。
うまく使うには、仕様を考える段階で「これは何を変数・状態・関係・遷移・
不変条件として見ればよいか」と考える必要がある。

この book の最初の目的は、特定ツールの文法を覚えることではなく、
**何ならモデル化できて、何を炙り出せるかを見分ける視点** を手に入れること。

## AI と人間の役割分担

形式手法を AI に任せるときに混ぜてはいけないのは、
「結果を分かりやすく言い換える作業」と
「何を証明する価値があるかを決める作業」である。

AI が得意なのは、すでに候補になった性質を Z3 / Alloy / TLA+ などに渡せる
形へ整え、`SAT`、`UNSAT`、counterexample、trace、proof failure を
アプリケーションの言葉へ戻すこと。

人間が担うのは、次の判断である。

- 何が事故になる性質か
- 何を invariant / reachability / equivalence / liveness として扱うか
- どこまで抽象化してよいか
- どの仮定を置いてよいか
- 反例が意図した例外か、仕様漏れか、実装 bug か

| 場面 | AI がやること | 人間がやること |
| --- | --- | --- |
| 対象選び | 認可、config、queue、retry など危険な型を候補に出す | 事業・運用上、壊れると困る境界を選ぶ |
| claim 抽出 | docs、テスト名、ガード節、schema から「〜できる / できない」を抜く | その claim が本当に保証したい性質か確認する |
| モデル化 | 述語、関係、状態、遷移、不変条件の案に落とす | 抽象化で落としてはいけないドメイン差を指摘する |
| 仮定 | finite scope、fairness、fail-open/close などを明示する | その仮定を業務上受け入れてよいか決める |
| 機械結果 | 反例や proof failure を具体的な業務シナリオに翻訳する | そのシナリオを許すか、禁止するか決める |
| 修正判断 | docs / code / model のどれが怪しいか候補を出す | 最終的に何を正とするか決める |
| 契約化 | 決まった性質を CI の regression guard にする | その guard を将来も守る契約として承認する |

証明可能な性質とは、「観測できる入力・状態・操作・結果」で書ける性質である。
たとえば「認可が安全」は曖昧だが、
「`role != Admin` の user が `Settings` に到達する trace は存在しない」
なら検査できる。

AI は後者への翻訳を手伝える。
しかし、「Settings は本当に Admin だけでよいのか」
「preview flag の例外を許すのか」は、人間が決める。

## 自然言語仕様から始めない

自然言語の仕様は、たいてい次のように曖昧である。

```text
管理者だけが設定画面を開ける。
決済は二重に走らない。
この campaign は対象ユーザーに配信される。
worker はいつか job を処理する。
```

このままでは機械に渡せない。まず問いを分解する。

| 自然言語 | モデル化するときの問い |
| --- | --- |
| 管理者だけが設定画面を開ける | `role`, `screen`, `transition` の関係で、non-admin が `Settings` に到達する trace はあるか |
| 決済は二重に走らない | `requestId` ごとに `externalCharge` が 2 回以上起きる action 順序はあるか |
| campaign は配信される | targeting 条件を満たす user は少なくとも 1 人存在するか |
| worker はいつか job を処理する | fairness 仮定の下で、pending job が forever pending の trace はあるか |

大事なのは、文章をそのまま形式化することではない。
文章の中にある **数えたいもの・到達したくない状態・順序・例外条件** を取り出す。

## モデル化できるもの

モデル化しやすいものは、観測対象がはっきりしている。

| 見方 | モデル化するもの | 向くツール |
| --- | --- | --- |
| 述語 | 入力から `true / false` を返す判定 | Z3, Dafny, MoonBit prove |
| 関係 | user、role、tenant、resource の対応 | Alloy |
| 状態 | order、job、session などの lifecycle | Alloy, TLA+, P |
| 遷移 | request、retry、timeout、ack、crash | TLA+, P |
| 不変条件 | どの時点でも破れてはいけない性質 | TLA+, Alloy, Dafny, MoonBit prove |
| 到達可能性 | ある状態・組み合わせに行けるか | Alloy, TLA+, Z3 |
| 等価性 | old と new が同じ判定を返すか | Z3, Dafny, MoonBit prove |
| 普遍定理 | 型に属する全値で成り立つ性質 | Lean, Rocq |

逆に、最初からモデル化しにくいものもある。

| 見方 | なぜ難しいか |
| --- | --- |
| 「使いやすい UI」 | 判定したい性質が曖昧で、反例の形も曖昧 |
| 「売上が上がる recommendation」 | 確率・分布・外部環境に依存する |
| 「LLM の回答品質」 | 正しさの述語が domain ごとに揺れる |
| 「外部 API はだいたい成功する」 | 外部世界の確率的性質であり、protocol safety とは別 |
| 「運用で気をつける」 | 状態・操作・責任境界に分解されていない |

モデル化できないのではなく、まず別の作業が必要になる。
例えば「使いやすい UI」は形式手法ではなく UX test の領域。
「外部 API はだいたい成功する」は、成功率ではなく「失敗しても不整合にならない」
という safety に言い換えるとモデル化できる。

## 何が炙り出せるか

形式手法が強いのは、「人間が見落とす組み合わせ」を具体化すること。

| 炙り出せるもの | 例 | 典型ツール |
| --- | --- | --- |
| 矛盾 | `country == JP` かつ `country != JP` | Z3 |
| dead config | 有効だが誰にも match しない campaign | Z3 |
| 優先順位バグ | allowlist が denylist より先に評価される | Z3 |
| tenant 境界の穴 | BillingAdmin override が project read まで広がる | Alloy |
| 到達不能 / dead branch | 設定されているが絶対に選ばれない rule | Z3, Alloy |
| read-modify-write race | 2 thread が古い count を読んで両方 accept | TLA+ |
| lost update | crash 前に publish されない outbox | TLA+ |
| liveness の穴 | fairness なしでは worker が永遠に job を取らない | TLA+ |
| protocol violation | response が request より先に観測される | P |
| loop invariant の不足 | binary search の候補区間が壊れる | Dafny, MoonBit prove |
| 抽象モデルとのずれ | vector の runtime tree と sequence model が一致しない | MoonBit prove |
| 普遍性の思い込み | viewer <= editor が permission 追加後に壊れる | Lean, Rocq |

この一覧を持ってコードや設計を見ると、読み方が変わる。
「この仕様は正しいか」ではなく、「この仕様はどの型の反例を持ちうるか」を考える。

## モデル化の最小単位

最初から巨大な仕様を書かない。
最小単位は、次のどれか 1 つでよい。

```text
1つの述語:
  isAllowed(user, action, resource)

1つの関係:
  memberOf(user, org), owner(resource, org)

1つの状態変数:
  orderState = Cart / Pending / Paid / Shipped

1つの action:
  RetryPayment

1つの invariant:
  NoShipWithoutPayment

1つの反例:
  BillingAdmin in Org A can read Project in Org B
```

小さいモデルで反例が出るなら、それで十分に価値がある。
反例が出なかったときだけ、scope を広げる、状態を増やす、ツールを変える。

## 仕様を考えるときの問い

仕様レビューで次の質問を投げる。

1. これは **入力に対する一瞬の判定** か、**時間を通じた性質** か。
2. 登場人物は何か。`User`, `Org`, `Resource`, `Request`, `Job` は何か。
3. 変わるものは何か。状態変数は何か。
4. 変える操作は何か。action は何か。
5. 絶対に起きてはいけない bad state は何か。
6. 到達してほしい good state は何か。
7. empty / missing / error / timeout / retry / crash はどう扱うか。
8. 反例が出たら、誰に「これは意図か」と聞くか。

この質問に答えられない仕様は、まだ形式手法以前に曖昧である。
その場合、形式化の前に domain の語彙を揃える。

## モデルからドメイン語へ戻す

形式手法の結果は、そのままでは `sat`、`unsat`、trace、proof obligation failure でしかない。
実務では必ずドメイン語へ戻す。

```text
SAT:
  BillingAdmin in Org A can read Project in Org B.

domain question:
  BillingAdmin の override は invoice だけですか?
  それとも project read まで許しますか?

decision:
  invoice だけなら bug。
  project read も許すなら仕様として明文化し、監査ログ条件を追加する。
```

これができて初めて、形式手法は設計・レビュー・実装の共通言語になる。
