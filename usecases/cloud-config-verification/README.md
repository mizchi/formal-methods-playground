# cloud-config-verification/

Pattern: verify cloud configuration by separating static connectivity from
time-dependent state transitions.

The source of truth is the cloud configuration you already operate:

- Terraform plan JSON
- Pulumi stack export
- CloudFormation template / change set
- Kubernetes manifests
- live inventory from AWS Config / Steampipe / `gcloud asset`

Do not ask the model checker to understand AWS or GCP. Extract a small set of
facts from the configuration, then verify the claim you care about.

## Split the question

| Question | Shape | Tool | Example |
| --- | --- | --- | --- |
| Can A talk to B directly? | graph relation | Alloy | security group / firewall reachability |
| Can A affect B through a chain? | transitive graph relation | Alloy | Internet -> ALB -> API -> DB |
| Can this Worker use that resource? | capability graph | Alloy | route -> Worker -> binding |
| Is this rollout order safe? | state transition | TLA+ | old stays serving until new is healthy |
| Does a failover eventually converge? | temporal property | TLA+ | primary down eventually routes to standby |
| Does every generated rule satisfy a local constraint? | per-resource predicate | Rego / Z3 | no public SSH, no wildcard admin |

## Static connectivity: Alloy

Example:

- [`connectivity.als`](./connectivity.als)

Modeled stack:

```text
Internet --HTTPS--> ALB --HTTP--> API --Postgres--> DB
                           Worker --Postgres--> DB
```

Checks:

| Command | Expected | Domain meaning |
| --- | --- | --- |
| `InternetCanReachAlb` | `SAT` | public entrypoint exists |
| `ApiCanReachDb` | `SAT` | application can reach database |
| `NoInternetDirectToDb` | `UNSAT` | no direct public DB path |
| `InternetNeverAffectsDb` | `SAT` | intentional counterexample: Internet can affect DB via ALB/API |
| `InternetCannotReachWorker` | `UNSAT` | worker is not externally reachable |

Run:

```sh
nix develop -c alloy6 exec -f --command NoInternetDirectToDb \
  usecases/cloud-config-verification/connectivity.als
nix develop -c just check-alloy
```

In production, the fact section should be generated:

```sh
terraform plan -out=plan.binary
terraform show -json plan.binary \
  | extract-cloud-facts \
  > generated/connectivity-facts.als
alloy6 exec -f --command NoInternetDirectToDb generated/connectivity.als
```

The extractor should emit only the semantic facts needed by the model:

```text
node(service/api)
node(service/db)
port(postgres)
edge(api, db, postgres)
edge(internet, alb, https)
```

## Cloudflare Workers: route / binding graph

Cloudflare Workers often do not have a VPC-style topology to inspect. The
security boundary is closer to a capability graph:

```text
public route -> Worker -> env bindings -> KV / D1 / R2 / Durable Object / Secret
                         -> service binding -> internal Worker
```

Example:

- [`cloudflare-workers-bindings.als`](./cloudflare-workers-bindings.als)

Modeled stack:

```text
Prod API route    -> ProdApiWorker    -> Prod D1, Prod KV
                                      -> service binding -> ProdAuthWorker
Prod static route -> ProdStaticWorker -> Assets
Preview API route -> PreviewApiWorker -> Prod D1  (intentional bug)
```

Checks:

| Command | Expected | Domain meaning |
| --- | --- | --- |
| `ProdApiCanReachProdD1` | `SAT` | production API has its intended D1 binding |
| `PublicApiCanReachAuthService` | `SAT` | service binding path to internal auth exists |
| `StaticAssetsCannotReachDataBindings` | `UNSAT` | static assets route cannot touch D1/KV/DO/secrets |
| `PublicEntryWorkerCannotBindSecretDirectly` | `UNSAT` | public entry Workers do not bind secrets directly |
| `PreviewNeverUsesProductionData` | `SAT` | intentional counterexample: preview Worker binds production D1 |

Run:

```sh
nix develop -c alloy6 exec -f --command PreviewNeverUsesProductionData \
  usecases/cloud-config-verification/cloudflare-workers-bindings.als
nix develop -c just check-alloy
```

Facts to extract from `wrangler.jsonc` / `wrangler.toml`:

| Wrangler concept | Model fact |
| --- | --- |
| top-level Worker / `env.<name>` Worker | `worker(name, environment)` |
| `routes` / `workers_dev` / custom domain | `handles(worker, route)` |
| `kv_namespaces`, `d1_databases`, `r2_buckets` | `binding(worker, resource)` |
| Durable Object binding | `binding(worker, durableObject)` |
| Secret / vars / Secrets Store binding | `binding(worker, secret)` |
| Service binding | `calls(callerWorker, targetWorker)` |

Source notes from the Cloudflare docs:

- [Workers bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/)
  grant Workers capabilities to platform resources such as D1, KV, R2, Durable
  Objects, service bindings, and secrets.
- [Wrangler environments](https://developers.cloudflare.com/workers/wrangler/configuration/)
  need explicit binding definitions; do not assume preview inherits production
  bindings safely.
- [Service bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/service-bindings/)
  are a useful way to keep internal Workers off public routes.
- [Workers KV](https://developers.cloudflare.com/kv/concepts/how-kv-works/)
  is eventually consistent, so do not use it as the source of truth for
  read-after-write security decisions.
- [Durable Objects](https://developers.cloudflare.com/durable-objects/concepts/what-are-durable-objects/)
  provide strongly consistent per-object storage and are a better boundary for
  coordination/session authority.

Domain wording for the intentional counterexample:

```text
Preview API traffic can reach production D1 through its Worker binding.
Is preview allowed to mutate production data, or should preview bind PreviewD1?
```

## State transitions: TLA+

Example:

- [`languages/tla/CloudRollout.tla`](../../languages/tla/CloudRollout.tla)
- [`languages/tla/CloudRollout.cfg`](../../languages/tla/CloudRollout.cfg)

Modeled rollout:

```text
old healthy + serving
  -> provision new
  -> new healthy
  -> db compatibility gate ready
  -> shift traffic
  -> terminate old
```

Checked properties:

| Property | Domain meaning |
| --- | --- |
| `TrafficOnlyToHealthyTarget` | load balancer never routes to an unhealthy target group |
| `NewTrafficRequiresDbReady` | v2 traffic does not start before DB compatibility is ready |
| `OldServesUntilCutover` | old target keeps serving during prepare/warmup |
| `DoneMeansNewOnly` | completed rollout has only new serving |
| `ReadyRolloutEventuallyShifts` | once new and DB are ready, traffic eventually moves |
| `ShiftedEventuallyDone` | once shifted, cleanup eventually terminates old |

Run:

```sh
nix develop -c tlc -config CloudRollout.cfg CloudRollout.tla
nix develop -c just check-tla
```

## Domain ledger

```text
source:
  Terraform / Pulumi / CloudFormation / Kubernetes configuration.

expected claim:
  Public traffic reaches only the intended entrypoint.
  Database is reachable only from application roles that are supposed to use it.
  Rollout never sends traffic to an unhealthy or schema-incompatible target.

model question:
  Static: does the extracted graph contain a forbidden direct or transitive path?
  Temporal: can any allowed deployment ordering violate the rollout invariants?

tool:
  Alloy for extracted connectivity facts.
  TLA+ for rollout / failover / lifecycle transitions.

machine result:
  SAT means "here is a concrete topology/path/order".
  UNSAT for an assertion check means no counterexample exists in the scope.
  TLC success means every explored state satisfies the invariants.

domain wording:
  "Internet cannot open a direct DB connection."
  "Internet can still cause DB writes through ALB and API; API must be treated as
  the authorization boundary."
  "Traffic will not move to the new target group until both target health and DB
  compatibility are true."

domain question:
  Is the transitive Internet -> ALB -> API -> DB path intended data flow?
  If intended, where is authorization enforced and logged?
  If not intended, should the API route, IAM permission, or DB ingress be split?

lock:
  `nix develop -c just check-alloy`
  `nix develop -c just check-tla`
```

## What to extract from real cloud config

Start with the smallest useful schema:

| Cloud concept | Model fact |
| --- | --- |
| security group / firewall rule | `edge(src, dst, port)` |
| subnet route to internet / NAT / peering | `edge(src, dst, routeKind)` |
| ALB listener / target group | `edge(listener, target, protocol)` |
| Cloudflare Worker route | `handles(worker, route)` |
| Cloudflare Worker binding | `binding(worker, resource)` |
| Cloudflare service binding | `calls(callerWorker, targetWorker)` |
| service account / IAM role | `principal(role)` |
| IAM binding / policy statement | `allows(principal, action, resource)` |
| health check / readiness gate | TLA+ boolean state |
| deployment phase | TLA+ `phase` variable |

Then add properties in this order:

1. Positive sanity: required paths exist.
2. Direct deny: forbidden direct paths do not exist.
3. Transitive deny or review: unexpected chains are surfaced.
4. Lifecycle safety: traffic only reaches healthy/compatible targets.
5. Lifecycle liveness: once readiness conditions hold, rollout converges.

This keeps the model tied to domain language and prevents "green but useless"
checks.
