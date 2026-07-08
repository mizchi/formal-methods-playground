# trust-boundary/

Pattern: a request attribute (client IP, user id, tenant) is resolved by a
priority chain over several sources. Some are set by trusted infrastructure
(load balancer, edge); some are freely settable by the caller (query param,
arbitrary header). If a caller-controlled source is adopted **without a trust
check** and sits high in the chain, the attribute is spoofable -- and it may
feed authorization, geo targeting, rate-limit keys, or billing.

The source of truth is the resolution function and which inputs cross the
trust boundary. Do not model the whole HTTP stack; model the priority chain
and the attacker's control over each source.

## Split the question

| Question | Shape | Tool | Example |
| --- | --- | --- | --- |
| Can the caller force the resolved value? | reachability over a decision chain | Z3 | `?ip=` adopted unconditionally |
| Does a guard close the hole? | same query, guarded resolver | Z3 | accept caller sources only behind a trusted marker |

## Probe: Z3

[`languages/z3/trust_boundary.smt2`](../../languages/z3/trust_boundary.smt2)

Sources in priority order: caller param, edge header, forwarded-for header,
connection peer. The current resolver adopts the param unconditionally.

| Check | Expected | Domain meaning |
| --- | --- | --- |
| param spoof, trusted peer | `sat` | caller sets `param = EVIL`; resolved becomes EVIL even behind a trusted LB |
| param spoof, direct peer | `sat` | spoofable regardless of the peer -- param does not depend on it |
| guarded resolver | `unsat` | gating caller sources on a trusted marker admits no spoof |

```sh
nix develop -c z3 -smt2 languages/z3/trust_boundary.smt2
nix develop -c just check-z3
```

## Domain ledger

| field | value |
| --- | --- |
| source of truth | the identity-resolution function + the deployment's trust boundary |
| claim | the resolved identity is never a value the caller freely chose |
| model question | is there caller input making `resolve(...) = EVIL` with `EVIL` != the real peer? |
| tool | Z3 |
| machine result | sat, sat (spoofable) / unsat (guarded) |
| domain wording | "any caller can set the resolved client IP by adding a query param, independent of the connection; gating the param on a trusted marker closes it" |
| lock | `just check-z3` |

## What this does NOT catch

- Whether the edge actually strips the caller-set headers is a deployment
  fact, not modeled here; if it does not, the header sources are additional
  spoof vectors.
- Cryptographic protocol attacks (replay, MITM, token forgery) need a
  symbolic-crypto tool (Tamarin/ProVerif), not this reachability model.
- This proves *a* spoof path exists; it does not enumerate downstream impact
  (which authz / geo / billing decisions consume the spoofed value).
