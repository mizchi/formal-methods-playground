# iam-assume-role/

Pattern: pull the IAM roles out of a Terraform plan and ask Alloy whether a
role a person can enter reaches an administrator role by chaining
`sts:AssumeRole`. Each hop is only possible when the caller's policy allows
the action on the target **and** the target's trust policy admits the caller,
so no single resource looks wrong; the escalation is in the composition.

```text
main.tf --tofu plan / show -json--> plan.json --extract.py--> iam_facts.als (generated)
                                                                  |
                                          iam_check.als (hand-written) opens it
```

The facts are generated and never edited; the property lives in a separate,
hand-written file, so the model cannot be derived from the configuration it
checks.

| Directory | Change | `NoEscalation` | `EntryReachesOtherRoles` |
| --- | --- | --- | --- |
| [`escalates/`](escalates/main.tf) | `deploy` may assume `role/*`; `admin` trusts `deploy` | SAT: developer -> deploy -> admin | SAT |
| [`fixed/`](fixed/main.tf) | `deploy` may only assume `role/app-*` | UNSAT | SAT (non-vacuity) |

```sh
nix develop -c usecases/iam-assume-role/check.sh          # uses the saved plan.json
nix develop -c usecases/iam-assume-role/check.sh --plan   # re-plans with OpenTofu first (TF=terraform to switch)
```

`plan` runs offline: the provider skips credential validation, and every ARN is
built from the account id so nothing is "known after apply".

## What this does NOT catch

- Deny statements, `NotAction` / `NotResource`, and `Condition` blocks (MFA,
  source IP, `aws:PrincipalTag`). The extractor only reads `Allow` + `Action`
  + `Resource`.
- SCPs, permission boundaries, and session policies, which can narrow what an
  identity policy allows.
- Other escalation routes: `iam:PassRole` into Lambda / EC2, `iam:CreatePolicyVersion`,
  `iam:AttachRolePolicy`, resource-based policies on S3 / KMS.
- Users and groups; only roles are modelled.
- Whether the live account matches the plan. Confirm with
  `aws iam simulate-principal-policy` or by trying the chain in a sandbox account.
