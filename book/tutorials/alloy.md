# Alloy

Alloy は、entity と relation の世界を小さい scope で総当たりし、
構造的な穴を concrete instance として出す道具である。

RBAC、tenant、ownership、workflow、network reachability に向く。

## 最小チュートリアル

題材: RBAC。

まず domain の登場人物を `sig` で書く。

```alloy
abstract sig Role {}
one sig Admin, Viewer extends Role {}

abstract sig Screen {}
one sig Home, Settings extends Screen {}

sig User {
  role: one Role,
  at: one Screen
}
```

安全性を assert する。

```alloy
assert NonAdminNeverAtSettings {
  all u: User |
    u.role != Admin implies u.at != Settings
}
```

反例を探す。

```alloy
check NonAdminNeverAtSettings for 4
```

Alloy は、`Viewer` が `Settings` にいるような小さい world を見つける。
その world が「仕様の穴」か「モデルの条件不足」かを確認する。

repo の実行例:

```sh
alloy6 exec --command <CommandName> languages/alloy/app-rbac.als
```

## 出力の読み方

| 出力 | 意味 |
| --- | --- |
| counterexample found | scope 内に仕様を破る小さい instance がある |
| no counterexample | 指定 scope では破れない |
| instance found for `run` | sanity case が到達可能 |

Alloy は bounded である。`for 4` で通っても全宇宙で証明したわけではない。
ただし実務の構造バグは小さい scope で見つかることが多い。

## レシピ

### tenant isolation

置き換える作業:

- 「orgId check しているはず」という認可レビュー

モデルにする入力:

- `User`
- `Org`
- `Resource`
- `memberOf`
- `owner`
- `allowed`

検査する性質:

```text
allowed[u, Read, r] implies owner[r] in memberOf[u]
```

期待:

- cross-tenant read の counterexample がない

### RBAC screen navigation

置き換える作業:

- UI route guard と API guard の組み合わせレビュー

検査する性質:

```text
non-admin user never reaches Settings
```

Alloy 6 の temporal operator を使えば、画面遷移も小さい trace として扱える。

### workflow の self approval 検出

モデル:

- `Requester`
- `Approver`
- `Expense`
- `Review`

検査:

```text
no expense is approved by its requester
```

反例が出たら、承認 route / role override / fallback approver を確認する。

### network reachability

モデル:

- `Service`
- `SecurityGroup`
- `Ingress`
- `CanReach`

検査:

```text
public service cannot reach database directly
```

Terraform / security group のレビューを、graph reachability 問題に変換する。

## 避ける使い方

- fairness や liveness を Alloy だけで押し切る
- scope を大きくしすぎて探索不能にする
- relation の sanity `run` を置かず、空モデルで assert を通す

近い repo 例:

- [`../../languages/alloy/app-rbac.als`](../../languages/alloy/app-rbac.als)
- [`../../languages/alloy/multi-tenant.als`](../../languages/alloy/multi-tenant.als)
- [`../../languages/alloy/workflow-approval.als`](../../languages/alloy/workflow-approval.als)
- [`../../usecases/terraform-reachability/reachability.als`](../../usecases/terraform-reachability/reachability.als)
