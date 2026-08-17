# 3. やりたいことからツールを選ぶ

ツール名から選ばない。まず問いの形を分類する。

## 選定表

| やりたいこと | まず使う | 理由 |
| --- | --- | --- |
| validator / feature flag / policy に悪い入力が通るか知りたい | Z3 | 純粋述語をそのまま SAT/UNSAT にできる |
| config の矛盾、dead config、旧新 evaluator の差分を見たい | Z3 | witness を取れる。CI validator にしやすい |
| RBAC、tenant、ownership、workflow の構造に穴があるか見たい | Alloy | entity と relation をそのまま書ける |
| distributed design を Python 風の擬似コード、role/RPC、図としてレビューしたい | FizzBee | 非 atomic action、fault injection、可視化、MBT へ同じ model を伸ばせる |
| workflow / protocol を型付きで実行可能な domain contract にしたい | Quint | TLA semantics を `type` / `action` / `test` / temporal property で書ける |
| network / queue / retry / crash の順序バグを見たい | FizzBee / Quint / TLA+ | action interleaving、fairness、liveness を扱える |
| actor / message protocol を実装に近い形で検査したい | P | typed message と state machine が主語になる |
| 逐次関数が pre/postcondition を守るか証明したい | Dafny | loop invariant と SMT で code-like に証明できる |
| MoonBit 実装の契約をその場で lock したい | MoonBit `moon prove` | `.mbt` / `.mbtp` に contract と proof model を置ける |
| 将来追加される値も含めて普遍定理を証明したい | Lean 4 | bounded ではない theorem を proof term として残せる |
| compiler / interpreter / DSL の意味保存を証明したい | Rocq | operational semantics 間の対応を構造帰納法で証明できる |
| concurrent data structure など既存 proof ecosystem が必要 | Rocq | Iris などの成熟資産がある |

## 迷ったときの順序

1. 実装から純粋述語を抜けるなら Z3。
2. entity と relation の話なら Alloy。
3. 時間、順序、retry、crash、eventual が出たら FizzBee / Quint / TLA+。
4. Python 風の design pseudocode、role/RPC、図、fault injection、MBT を正本にするなら FizzBee。
5. 型付き domain contract、REPL、test を正本にするなら Quint。TLAPS や既存 TLA+ 資産を直接使うなら TLA+。
6. actor / message の実装モデルに寄せたいなら P。
7. 関数本体の正しさなら Dafny または MoonBit `moon prove`。
8. 普遍定理や数学的構造なら Lean / Rocq。

## 典型的な判断

| 問い | 判断 |
| --- | --- |
| 「この認可条件で他 tenant の project が読めるか」 | Alloy か Z3 |
| 「retry で二重決済になる interleaving があるか」 | FizzBee / Quint / TLA+ |
| 「この config 条件は誰にも match しないのでは」 | Z3 |
| 「この loop は常に sorted prefix を保つか」 | Dafny / MoonBit `moon prove` |
| 「role hierarchy の単調性は permission 追加後も成り立つか」 | Lean |
| 「この compiler は任意の source program の意味を保存するか」 | Rocq |

FizzBee、Quint、TLA+ は同じ temporal state-transition 領域を扱えるが、authoring と
ecosystem が違う。設計擬似コード・role/RPC・可視化・MBT を優先するなら FizzBee、
型付き domain contract と TLA semantics を優先するなら Quint、既存 module・TLAPS・
高度な refinement を優先するなら TLA+ を直接使う。

## Z3 と temporal model（FizzBee / Quint / TLA+）の境界

Z3 は「ある一瞬の入力組み合わせ」を見る。

```text
この user, role, resource, action の組み合わせで allowed になるか?
```

FizzBee / Quint / TLA+ は「時間を通じた全順序」を見る。

```text
request, retry, crash, recover がどの順で起きても二重決済しないか?
```

同じ「モデル」と言っても、問いの形が違う。
Z3 で時間の全 interleaving を無理に書かない。FizzBee / Quint / TLA+ で単純な config 矛盾を
書きすぎない。
