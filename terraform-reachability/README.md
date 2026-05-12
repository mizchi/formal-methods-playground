# terraform-reachability/

Probe: take a Terraform-style microservice stack (security
groups + service-to-SG memberships + ingress rules) and answer
graph-reachability questions in Alloy.

## What this models

```
Frontend  ─HTTP→  Api  ─Postgres→  Db
```

Three services in three security groups. Two ingress rules:
api admits frontend, db admits api. No rule connects frontend
to db.

The probe asks three questions on this graph:

1. **Safety** — Is there a direct rule frontend → db? Should be
   `UNSAT` (no path).
2. **Sanity** — Can api reach db directly? Should be `SAT`.
3. **Transitive** — Can frontend reach db *via any chain*?
   Intentionally `SAT` — surfaces the proxy-chain path frontend
   → api → db that the rule table doesn't make obvious.

## Run

```sh
cd terraform-reachability
nix develop ..  # if not already in devShell

alloy6 exec -f --command FrontendCannotReachDbDirectly reachability.als
alloy6 exec -f --command ApiCanReachDb reachability.als
alloy6 exec -f --command FrontendNeverTransitivelyReachesDb reachability.als
```

Verified results:

```
FrontendCannotReachDbDirectly         UNSAT
ApiCanReachDb                          SAT
FrontendNeverTransitivelyReachesDb     SAT  (intentional counter-example)
```

## Source vs facts

`fixture/main.tf` is the HCL the architect would author. The
Alloy file's "Facts" section is what a `terraform show -json`
→ Alloy translator would emit. For this probe the translator
is omitted and the facts are hand-encoded; production wiring
would look like:

```sh
terraform plan -out=plan.binary
terraform show -json plan.binary | go run extract.go > facts.als
```

The translator's job: walk `resource_changes`, pick out each
`aws_security_group` (membership) and `aws_security_group_rule`
of type `ingress` (edge), emit `one sig` and `fact rules { ... }`.
~150 LOC of Go, sketched but not implemented here.

## What this layer adds over OPA / Rego

Rego on terraform plan is the right starting tool for
*rule-by-rule* checks ("no SG opens 0.0.0.0/0 on port 22"). It
struggles with transitive reachability because Rego's
non-stratified-negation restrictions force you to unroll
recursion manually.

Alloy's `^edges` operator gives you the closure for free, and
returns a concrete witness chain when a transitive path exists.
For "can A reach B through some hop sequence?" questions, this
is qualitatively easier.

What Alloy doesn't replace:
- Linting individual rules (Rego / conftest are mature)
- Cloud-vendor reachability analyzers post-deploy (AWS VPC
  Reachability Analyzer, GCP Network Intelligence Center)
- Live drift detection (Steampipe + SQL queries against the
  real environment)

The picking matrix: Rego for "every rule satisfies X," Alloy
for "the graph of rules implies the property X (transitively
or not)."

## Extending the probe

Real microservice meshes also have:

- **IAM**: principal → resource → action edges. Add a second
  relation `iamAllows: Principal -> set Resource`, ask whether
  frontend's role can transitively touch db's data via api's
  S3-bucket policy etc.
- **Port granularity**: model ports as a `Port` enum, edges
  carry both source SG and port. Probe asks "is port 22 open
  to anything?" or "is port X open from outside the VPC?"
- **VPC boundaries**: introduce `Vpc` sig, `subnetIn: Subnet ->
  Vpc`, check "no cross-VPC reachability without a peering
  declaration."
- **NACLs**: subnet-level allow/deny rules, layer above SG.
  Modeled as a second pass of the same closure.

Each of these is a new sig + fact section; the closure logic
in `CanReachTransitive` stays unchanged.
