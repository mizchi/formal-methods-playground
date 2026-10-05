# tenant-authz/

Pattern: an authorization function checks the role and the action, and forgets
the resource. Every role test in the suite passes, because every test fixture
puts the user and the resource in the same org.

Real instances: SaaS dashboards with billing roles, support impersonation or
"break-glass" flags, admin consoles that grew a second role after launch.

This is the reference implementation for scenario B of the
[`formal-methods-reconciler`](https://github.com/mizchi/skills/tree/main/formal-methods-reconciler)
skill eval (`formal-reconciler-authz-alloy-001`).

## Source of truth

The docs are trusted. The function is an implementation observation.

| # | Docs (trusted) |
| --- | --- |
| D1 | Owner reads projects and invoices in their own org |
| D2 | BillingAdmin reads only invoices in their own org |
| D3 | BillingAdmin cannot read projects |
| D4 | Support override exists for billing investigations: invoice reads only |
| D5 | No role reads a resource in another org |

```ts
// observed
function canRead(user, resource, action) {
  if (user.role === "Owner") return true;
  if (user.role === "BillingAdmin" &&
      (action === "read_invoice" || action === "read_project")) return true;
  if (user.supportOverride) return true;
  return false;
}
```

## Split the question

| Question | Shape | Tool |
| --- | --- | --- |
| Does any user read across orgs? | relation over user, role, org, resource | Alloy |
| Does BillingAdmin reach projects? | the same relation | Alloy |
| Does the override grant more than invoices? | the same relation | Alloy |
| Does the fix say exactly what the docs say? | equality of two relations | Alloy |

Z3 could encode the same predicate, but the question is about which *pairs* of
user and resource exist, and Alloy prints them as a small world a reviewer can
read. There is no ordering, so TLA+ adds nothing. A theorem prover is the wrong
first tool for finding a missing `org` check.

## Probe: Alloy

[`authz.als`](authz.als) states each property once as a predicate over a
`User -> Resource` relation, and applies it to three relations: the observed
implementation (`impl`), the proposed fix (`fixed`), and the docs (`doc`). The
fix is written in the shape of the code (org check first, then the role table),
not copied from the docs predicate, so `FixedMatchesDocs` compares two
different formulas.

| Command | Expected | Domain meaning |
| --- | --- | --- |
| `ImplNoCrossTenantRead` | `SAT` | a BillingAdmin in org B reads an invoice of org A |
| `ImplNoBillingAdminProjectRead` | `SAT` | a BillingAdmin reads a project in its own org |
| `ImplSupportInvoiceOnly` | `SAT` | a Member with the support override reads a project |
| `ImplMatchesDocs` | `SAT` | the implementation and the docs disagree somewhere |
| `FixedNoCrossTenantRead` | `UNSAT` (scope 4) | no cross-org read under the fix |
| `FixedNoBillingAdminProjectRead` | `UNSAT` (scope 4) | BillingAdmin never reads a project |
| `FixedSupportInvoiceOnly` | `UNSAT` (scope 4) | the override grants invoices only |
| `FixedMatchesDocs` | `UNSAT` (scope 4) | the fix grants exactly what D1-D5 grant |
| `SanityOwnerReadsOwnProject` | `SAT` | the fix is not "deny everything" |
| `SanityBillingAdminReadsOwnInvoice` | `SAT` | D2 is reachable |
| `SanitySupportReadsInvoice` | `SAT` | D4 is reachable |

```sh
nix develop -c just check-alloy
alloy6 exec -f -t text -o - --command ImplNoCrossTenantRead usecases/tenant-authz/authz.als
```

Negative control: replacing `u.org = r.owner` in `FixedCanRead` with
`some r.owner` flips `FixedNoCrossTenantRead` and `FixedMatchesDocs` to `SAT`,
and leaves `FixedNoBillingAdminProjectRead` `UNSAT`. The org check is the only
thing those two checks rest on.

## The instance to show a reviewer

`ImplNoCrossTenantRead`, trimmed:

```text
User$0   org = Org$1   role = BillingAdmin
Invoice$0            owner = Org$0
canRead(User$0, Invoice$0) = true      <- org$1 user, org$0 invoice
```

Two things in one line for the reviewer: the BillingAdmin branch never looks at
`resource`, and neither does any other branch.

## Reproduce in the implementation

[`repro/authz.ts`](repro/authz.ts) holds the observed function verbatim and the
fix. [`repro/authz.test.ts`](repro/authz.test.ts) replays each Alloy witness
against both, plus the Owner cross-org case, and then compares the fix with a
table of D1-D5 on all 24 combinations of role, override, org, and resource
kind.

```sh
node --test usecases/tenant-authz/repro/authz.test.ts
```

All four witnesses reproduced: the observed function returns `true`, the fix
returns `false`.

## Domain ledger

| field | value |
| --- | --- |
| source | authorization docs D1-D5 (trusted); `canRead` (observed) |
| expected claim | every read stays inside the user's org; BillingAdmin and the support override read invoices only |
| implementation observation | `canRead` ignores `resource`; Owner and any override holder are allowed everything; BillingAdmin is allowed `read_project` |
| model question | is there a `User -> Resource` pair in `impl` that crosses orgs, gives BillingAdmin a project, or gives the override a non-invoice? is `fixed = doc`? |
| tool | Alloy 6 |
| machine result | four `Impl*` checks `SAT`; four `Fixed*` checks `UNSAT` at scope 4; three sanity runs `SAT` |
| witness | BillingAdmin of org B reads an invoice of org A; BillingAdmin reads its own org's project; Member with override reads a project |
| reproduction | all witnesses reproduced by `repro/authz.test.ts`; the fix agrees with the D1-D5 table on all 24 combinations |
| domain wording | "any Owner, and anyone with the support flag, can read every org's projects and invoices; a BillingAdmin can read projects" |
| domain question | D4 and D5 together mean support staff can only read invoices of *their own* org. Is support meant to investigate customers' invoices across orgs? If yes, D5 needs an explicit exception for the override, and the model needs an audited cross-org grant |
| decision | bug: ship `canReadFixed`. Unresolved: whether the support override crosses orgs |
| lock | `just check-alloy` (`scripts/check-alloy.sh`) and `node --test usecases/tenant-authz/repro/authz.test.ts`; add a same-org and a cross-org fixture to every role test |

## What this does NOT catch

- Where `user.org` comes from. If the org is read from a request header or a
  URL parameter instead of the session, the model's `org` is not the real one.
- Write actions, listing endpoints, and search. A list query that filters by
  org in SQL is a different code path from `canRead`.
- Scope. `UNSAT` holds for up to 4 atoms per signature; with no quantifier over
  counts in the rule, a larger world adds nothing new, but that is an argument,
  not a check.
