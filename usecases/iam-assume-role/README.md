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

## Domain ledger

| field | value |
| --- | --- |
| source | `escalates/main.tf` and `fixed/main.tf`, planned to `plan.json`; `extract.py` generates `iam_facts.als`, and the property is hand-written in `iam_check.als` |
| expected claim | No role a person can enter reaches an administrator role by chaining `sts:AssumeRole` |
| implementation observation | In `escalates/`, `deploy` may assume `role/*` and `admin` trusts `deploy`; in `fixed/`, `deploy` may only assume `role/app-*` |
| model question | Is any role in `Entry.*canAssume` also `Privileged`, where each hop needs both the caller's Allow and the target's trust policy (`NoEscalation`)? Does an entry role reach some other role at all (`EntryReachesOtherRoles`, non-vacuity)? |
| tool | Alloy 6 (scope 5) |
| machine result | `escalates/`: `NoEscalation` SAT (counterexample), `EntryReachesOtherRoles` SAT / `fixed/`: `NoEscalation` UNSAT, `EntryReachesOtherRoles` SAT |
| witness | developer -> deploy -> admin |
| reproduction | none yet; the README suggests `aws iam simulate-principal-policy` or trying the chain in a sandbox account |
| domain wording | A developer becomes admin in two hops: assume `deploy`, whose `role/*` permission covers `admin`, which trusts `deploy`. |
| domain question | Does `deploy` need to assume anything beyond the per-environment `role/app-*` roles, and should `admin` trust `deploy` at all? |
| decision | bug; fixed variant `fixed/` (`deploy` limited to `role/app-*`) is the check |
| lock | `just check-alloy`, which runs `usecases/iam-assume-role/check.sh` against the saved `plan.json` and fails unless escalates is `SAT` and fixed is `UNSAT` (`--plan` re-plans with OpenTofu) |

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
