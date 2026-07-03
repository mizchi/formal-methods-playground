# 3. やりたいことからツールを選ぶ

ツール名から選ばない。まず問いの形を分類する。

## 選定表

| やりたいこと | まず使う | 理由 |
| --- | --- | --- |
| validator / feature flag / policy に悪い入力が通るか知りたい | Z3 | 純粋述語をそのまま SAT/UNSAT にできる |
| config の矛盾、dead config、旧新 evaluator の差分を見たい | Z3 | witness を取れる。CI validator にしやすい |
| RBAC、tenant、ownership、workflow の構造に穴があるか見たい | Alloy | entity と relation をそのまま書ける |
| network / queue / retry / crash の順序バグを見たい | TLA+ | action interleaving と liveness を扱える |
| actor / message protocol を実装に近い形で検査したい | P | typed message と state machine が主語になる |
| 逐次関数が pre/postcondition を守るか証明したい | Dafny | loop invariant と SMT で code-like に証明できる |
| MoonBit 実装の契約をその場で lock したい | MoonBit `moon prove` | `.mbt` / `.mbtp` に contract と proof model を置ける |
| 将来追加される値も含めて普遍定理を証明したい | Lean 4 | bounded ではない theorem を proof term として残せる |
| compiler / concurrent data structure など既存 proof ecosystem が必要 | Rocq | CompCert / Iris などの成熟資産がある |

## 迷ったときの順序

1. 実装から純粋述語を抜けるなら Z3。
2. entity と relation の話なら Alloy。
3. 時間、順序、retry、crash、eventual が出たら TLA+。
4. actor / message の実装モデルに寄せたいなら P。
5. 関数本体の正しさなら Dafny または MoonBit `moon prove`。
6. 普遍定理や数学的構造なら Lean / Rocq。

## 典型的な判断

| 問い | 判断 |
| --- | --- |
| 「この認可条件で他 tenant の project が読めるか」 | Alloy か Z3 |
| 「retry で二重決済になる interleaving があるか」 | TLA+ |
| 「この config 条件は誰にも match しないのでは」 | Z3 |
| 「この loop は常に sorted prefix を保つか」 | Dafny / MoonBit `moon prove` |
| 「role hierarchy の単調性は permission 追加後も成り立つか」 | Lean |

## Z3 と TLA+ の境界

Z3 は「ある一瞬の入力組み合わせ」を見る。

```text
この user, role, resource, action の組み合わせで allowed になるか?
```

TLA+ は「時間を通じた全順序」を見る。

```text
request, retry, crash, recover がどの順で起きても二重決済しないか?
```

同じ「モデル」と言っても、問いの形が違う。
Z3 で時間の全 interleaving を無理に書かない。TLA+ で単純な config 矛盾を
書きすぎない。
