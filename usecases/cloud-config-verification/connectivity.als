/*
 * Probe: cloud configuration reachability derived from IaC facts.
 *
 * This models a small public web stack:
 *
 *   Internet --HTTPS--> ALB --HTTP--> API --Postgres--> DB
 *                                      Worker --Postgres--> DB
 *
 * The "Facts" section is what a Terraform/Pulumi/CloudFormation
 * extractor would emit from security groups, firewall rules, service
 * attachments, and route exposure.
 *
 * Run:
 *   alloy6 exec -f --command InternetCanReachAlb connectivity.als
 *   alloy6 exec -f --command ApiCanReachDb connectivity.als
 *   alloy6 exec -f --command NoInternetDirectToDb connectivity.als
 *   alloy6 exec -f --command InternetNeverAffectsDb connectivity.als
 *   alloy6 exec -f --command InternetCannotReachWorker connectivity.als
 *
 * Expectations:
 *   InternetCanReachAlb          SAT   (positive sanity)
 *   ApiCanReachDb                SAT   (positive sanity)
 *   NoInternetDirectToDb         UNSAT (assertion holds)
 *   InternetNeverAffectsDb       SAT   (intentional counterexample:
 *                                      Internet -> ALB -> API -> DB)
 *   InternetCannotReachWorker    UNSAT (assertion holds)
 */

abstract sig Node {}
one sig Internet, Alb, Api, Worker, Db extends Node {}

abstract sig Port {}
one sig HTTPS, HTTP, Postgres extends Port {}

sig Rule {
  src: one Node,
  dst: one Node,
  port: one Port,
}

pred Direct[srcNode, dstNode: Node, p: Port] {
  some r: Rule | r.src = srcNode and r.dst = dstNode and r.port = p
}

fun edges: Node -> Node {
  { a, b: Node | some p: Port | Direct[a, b, p] }
}

pred CanReach[srcNode, dstNode: Node] {
  (srcNode -> dstNode) in ^edges
}

// ── Facts (IaC-derived; hand-encoded for this probe) ───────────────────────

one sig InternetToAlbHttps, AlbToApiHttp, ApiToDbPostgres, WorkerToDbPostgres
  extends Rule {}

fact rules {
  Rule = InternetToAlbHttps + AlbToApiHttp + ApiToDbPostgres + WorkerToDbPostgres

  InternetToAlbHttps.src = Internet
  InternetToAlbHttps.dst = Alb
  InternetToAlbHttps.port = HTTPS

  AlbToApiHttp.src = Alb
  AlbToApiHttp.dst = Api
  AlbToApiHttp.port = HTTP

  ApiToDbPostgres.src = Api
  ApiToDbPostgres.dst = Db
  ApiToDbPostgres.port = Postgres

  WorkerToDbPostgres.src = Worker
  WorkerToDbPostgres.dst = Db
  WorkerToDbPostgres.port = Postgres
}

// ── Positive sanity checks ─────────────────────────────────────────────────

run InternetCanReachAlb {
  Direct[Internet, Alb, HTTPS]
} for 5 Node, 3 Port, 4 Rule

run ApiCanReachDb {
  Direct[Api, Db, Postgres]
} for 5 Node, 3 Port, 4 Rule

// ── Safety properties ──────────────────────────────────────────────────────

assert NoInternetDirectToDb {
  no p: Port | Direct[Internet, Db, p]
}
check NoInternetDirectToDb for 5 Node, 3 Port, 4 Rule

// This assertion is deliberately false. It surfaces the data-plane path:
// Internet can cause DB access through ALB and API. The domain owner must decide
// whether API is a trusted mediator or whether an authorization guard is missing.
assert InternetNeverAffectsDb {
  not CanReach[Internet, Db]
}
check InternetNeverAffectsDb for 5 Node, 3 Port, 4 Rule

assert InternetCannotReachWorker {
  not CanReach[Internet, Worker]
}
check InternetCannotReachWorker for 5 Node, 3 Port, 4 Rule
