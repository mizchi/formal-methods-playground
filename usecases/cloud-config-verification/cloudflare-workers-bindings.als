/*
 * Probe: Cloudflare Workers route / binding capability graph.
 *
 * Cloudflare Workers do not expose a VPC-style topology to model. The useful
 * configuration boundary is:
 *
 *   public route -> Worker -> bindings / service bindings -> resources
 *
 * A Wrangler config extractor would emit workers, routes, environments, and
 * bindings from wrangler.jsonc / wrangler.toml. This standalone model keeps the
 * facts hand-written.
 *
 * Run:
 *   alloy6 exec -f --command ProdApiCanReachProdD1 cloudflare-workers-bindings.als
 *   alloy6 exec -f --command PublicApiCanReachAuthService cloudflare-workers-bindings.als
 *   alloy6 exec -f --command StaticAssetsCannotReachDataBindings cloudflare-workers-bindings.als
 *   alloy6 exec -f --command PublicEntryWorkerCannotBindSecretDirectly cloudflare-workers-bindings.als
 *   alloy6 exec -f --command PreviewNeverUsesProductionData cloudflare-workers-bindings.als
 *
 * Expectations:
 *   ProdApiCanReachProdD1                       SAT   (positive sanity)
 *   PublicApiCanReachAuthService                SAT   (service binding sanity)
 *   StaticAssetsCannotReachDataBindings         UNSAT (assertion holds)
 *   PublicEntryWorkerCannotBindSecretDirectly   UNSAT (assertion holds)
 *   PreviewNeverUsesProductionData              SAT   (intentional leak:
 *                                                    preview API binds prod D1)
 */

abstract sig Environment {}
one sig Production, Preview extends Environment {}

abstract sig Exposure {}
one sig Public, Internal extends Exposure {}

sig Route {
  routeEnv: one Environment,
  exposure: one Exposure,
}

abstract sig ResourceKind {}
one sig AssetsKind, D1Kind, KVKind, DurableObjectKind, SecretKind extends ResourceKind {}

sig Resource {
  resourceEnv: one Environment,
  kind: one ResourceKind,
}

sig Worker {
  workerEnv: one Environment,
  handles: set Route,
  bindings: set Resource,
  calls: set Worker,
}

fun dataKinds: set ResourceKind {
  D1Kind + KVKind + DurableObjectKind + SecretKind
}

fun WorkersFromRoute[r: Route]: set Worker {
  { w: Worker | some entry: Worker | r in entry.handles and w in entry.*calls }
}

pred RouteCanReachResource[r: Route, res: Resource] {
  some w: WorkersFromRoute[r] | res in w.bindings
}

pred RouteCanReachWorker[r: Route, worker: Worker] {
  worker in WorkersFromRoute[r]
}

// ── Facts (wrangler-derived; hand-encoded for this probe) ──────────────────

one sig ProdApiRoute, ProdStaticRoute, PreviewApiRoute extends Route {}

one sig ProdApiWorker, ProdStaticWorker, ProdAuthWorker, PreviewApiWorker,
  PreviewAuthWorker extends Worker {}

one sig ProdD1, PreviewD1, ProdSessionKV, PreviewSessionKV, ProdSessionDO,
  PreviewSessionDO, ProdSecret, PreviewSecret, AssetsBucket extends Resource {}

fact routes {
  Route = ProdApiRoute + ProdStaticRoute + PreviewApiRoute

  ProdApiRoute.routeEnv = Production
  ProdApiRoute.exposure = Public

  ProdStaticRoute.routeEnv = Production
  ProdStaticRoute.exposure = Public

  PreviewApiRoute.routeEnv = Preview
  PreviewApiRoute.exposure = Public
}

fact resources {
  Resource = ProdD1 + PreviewD1 + ProdSessionKV + PreviewSessionKV +
    ProdSessionDO + PreviewSessionDO + ProdSecret + PreviewSecret + AssetsBucket

  ProdD1.resourceEnv = Production
  ProdD1.kind = D1Kind
  PreviewD1.resourceEnv = Preview
  PreviewD1.kind = D1Kind

  ProdSessionKV.resourceEnv = Production
  ProdSessionKV.kind = KVKind
  PreviewSessionKV.resourceEnv = Preview
  PreviewSessionKV.kind = KVKind

  ProdSessionDO.resourceEnv = Production
  ProdSessionDO.kind = DurableObjectKind
  PreviewSessionDO.resourceEnv = Preview
  PreviewSessionDO.kind = DurableObjectKind

  ProdSecret.resourceEnv = Production
  ProdSecret.kind = SecretKind
  PreviewSecret.resourceEnv = Preview
  PreviewSecret.kind = SecretKind

  AssetsBucket.resourceEnv = Production
  AssetsBucket.kind = AssetsKind
}

fact workers {
  Worker = ProdApiWorker + ProdStaticWorker + ProdAuthWorker +
    PreviewApiWorker + PreviewAuthWorker

  ProdApiWorker.workerEnv = Production
  ProdStaticWorker.workerEnv = Production
  ProdAuthWorker.workerEnv = Production
  PreviewApiWorker.workerEnv = Preview
  PreviewAuthWorker.workerEnv = Preview
}

fact routeBindings {
  ProdApiWorker.handles = ProdApiRoute
  ProdStaticWorker.handles = ProdStaticRoute
  no ProdAuthWorker.handles
  PreviewApiWorker.handles = PreviewApiRoute
  no PreviewAuthWorker.handles
}

fact resourceBindings {
  ProdApiWorker.bindings = ProdD1 + ProdSessionKV
  ProdStaticWorker.bindings = AssetsBucket
  ProdAuthWorker.bindings = ProdSessionDO + ProdSecret

  // Intentional bug pattern: preview is bound to production D1. This is the
  // sort of drift that is easy to miss because Wrangler environments require
  // bindings to be declared per environment.
  PreviewApiWorker.bindings = ProdD1 + PreviewSessionKV
  PreviewAuthWorker.bindings = PreviewSessionDO + PreviewSecret
}

fact serviceBindings {
  ProdApiWorker.calls = ProdAuthWorker
  PreviewApiWorker.calls = PreviewAuthWorker
  no ProdStaticWorker.calls
  no ProdAuthWorker.calls
  no PreviewAuthWorker.calls
}

// ── Positive sanity checks ─────────────────────────────────────────────────

run ProdApiCanReachProdD1 {
  RouteCanReachResource[ProdApiRoute, ProdD1]
} for 3 Environment, 2 Exposure, 3 Route, 5 Worker, 9 Resource, 5 ResourceKind

run PublicApiCanReachAuthService {
  RouteCanReachWorker[ProdApiRoute, ProdAuthWorker]
} for 3 Environment, 2 Exposure, 3 Route, 5 Worker, 9 Resource, 5 ResourceKind

// ── Safety properties ──────────────────────────────────────────────────────

assert StaticAssetsCannotReachDataBindings {
  no res: Resource |
    res.kind in dataKinds and RouteCanReachResource[ProdStaticRoute, res]
}
check StaticAssetsCannotReachDataBindings
  for 3 Environment, 2 Exposure, 3 Route, 5 Worker, 9 Resource, 5 ResourceKind

assert PublicEntryWorkerCannotBindSecretDirectly {
  no w: Worker, r: Route, res: Resource |
    r.exposure = Public
    and r in w.handles
    and res in w.bindings
    and res.kind = SecretKind
}
check PublicEntryWorkerCannotBindSecretDirectly
  for 3 Environment, 2 Exposure, 3 Route, 5 Worker, 9 Resource, 5 ResourceKind

// Deliberately false for this fixture: PreviewApiWorker binds ProdD1.
// Domain wording: "preview traffic can mutate production data".
assert PreviewNeverUsesProductionData {
  no w: Worker, res: Resource |
    w.workerEnv = Preview
    and res in w.bindings
    and res.resourceEnv = Production
    and res.kind in dataKinds
}
check PreviewNeverUsesProductionData
  for 3 Environment, 2 Exposure, 3 Route, 5 Worker, 9 Resource, 5 ResourceKind
