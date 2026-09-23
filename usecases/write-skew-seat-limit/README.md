# write-skew-seat-limit/

Pattern: the code reads an aggregate, checks it against a limit, then inserts a
row. Two requests do this concurrently. The two inserts touch **different
rows**, so there is no write-write conflict for the database to detect — and
under Snapshot Isolation both commit.

This is *not* the read-modify-write race in [`rate-limiting/`](../rate-limiting/).
There, both requests write the same counter and a conditional write fixes it.
Here nothing overlaps: the invariant spans rows that no single transaction
writes. Wrapping the handler in a transaction does not help, and neither does
an atomic increment on a row nobody is incrementing.

Real instances: seat limits on a B2B plan, coupon redemption caps, inventory
reservation, "at least one owner must remain in the org", free-tier project
quotas, double-booking a meeting room.

The source of truth is the handler's SQL plus the **configured isolation
level** — which is usually a framework default nobody chose. Do not model the
database; model the snapshot read, the guard, and the commit rule.

## Split the question

| Question | Shape | Tool | Example |
| --- | --- | --- | --- |
| Can two concurrent invites exceed the seat limit? | write skew over commit interleavings | TLA+ | both read `count = 0`, both insert |
| Does the isolation level we actually run at prevent it? | same model, different commit rule | TLA+ | `REPEATABLE READ` vs `SERIALIZABLE` |
| Does an explicit row lock prevent it? | same model, mutual exclusion | TLA+ | `SELECT ... FOR UPDATE` on the org row |
| Which isolation level were we *actually* on last Tuesday? | replay the production log against the same model | TLA+ | the log's second `COMMIT` succeeded, which SSI would not allow |

## Probe: TLA+

[`languages/tla/SeatLimitWriteSkew.tla`](../../languages/tla/SeatLimitWriteSkew.tla)

`Isolation` selects the store's commit rule:

| Value | Models |
| --- | --- |
| `"SI"` | snapshot read, first-committer-wins on the *same* row (PostgreSQL `REPEATABLE READ`, MySQL default) |
| `"SERIALIZABLE"` | PostgreSQL SSI: abort at commit if the read set moved |
| `"SI_LOCK"` | still SI, but `SELECT ... FOR UPDATE` on the org row first |

| Command | Expected | Domain meaning |
| --- | --- | --- |
| `tlc -config SeatLimitWriteSkew.cfg SeatLimitWriteSkew.tla` | no error (21 states, depth 7) | SSI aborts the second transaction; the limit holds |
| `tlc -config SeatLimitWriteSkew_si.cfg SeatLimitWriteSkew.tla` | `Invariant SeatsWithinLimit is violated` (`members = 2`, limit 1) | breaking variant: plain snapshot isolation admits the write skew |
| `tlc -config SeatLimitWriteSkew_lock.cfg SeatLimitWriteSkew.tla` | no error (11 states, depth 6) | the explicit lock materialises the missing conflict |

Two green configs is deliberate. They are green for *different reasons*
(commit-time abort vs. mutual exclusion), so a change that drops one — someone
"optimising away" the `FOR UPDATE`, or a connection-pool setting that resets
the isolation level — cannot pass by leaning on the other.

```sh
nix develop -c just check-tla
nix develop -c bash -c 'cd languages/tla && tlc -config SeatLimitWriteSkew_si.cfg SeatLimitWriteSkew.tla'
```

## The trace to show a reviewer

`SeatLimitWriteSkew_si.cfg`, `SeatLimit = 1`:

```text
Read(t1)     snap[t1] = 0                        members = 0
Insert(t1)   guard passes (0 < 1)                members = 0
Read(t2)     snap[t2] = 0   <- still the old snapshot
Commit(t1)                                       members = 1
Insert(t2)   guard passes against snap[t2] = 0   members = 1
Commit(t2)   nothing conflicts; SI lets it       members = 2   <- violated
```

The domain sentence: *"two admins clicking Invite within the same second both
see one free seat, and the org ends up with two members on a one-seat plan."*

## Probe: TLA+ trace replay (T5)

[`languages/tla/SeatLimitTrace.tla`](../../languages/tla/SeatLimitTrace.tla) ·
logs in [`traces/`](./traces/)

The probe above is a [T0 check](../../book/06-timing.md): it says which
isolation level is safe. The section below ("What this does NOT catch") admits
the question it cannot answer — *whether production runs at the level you
modelled*. That question has no design-time answer. It is settled by what the
database did, and that is in the log.

So take the same model and, instead of searching interleavings, replay one
production log through it. The log determines every step, so there is nothing
to explore: `Len(log) + 1` states, under a second. What the check asks at each
line is whether the model **admits** that step at the configured `Isolation`.

`scripts/trace-to-tla.sh` projects `traces/*.json` onto the five operations the
model has actions for, and writes the generated module
`languages/tla/SeatLimitTraceLog.tla`:

| log `op` | reality | model action |
| --- | --- | --- |
| `select` | `BEGIN` + the counting `SELECT` | `Read` |
| `insert` | the `INSERT` was issued | `Insert` |
| `deny` | handler refused, `409`, nothing written | `Reject` |
| `commit` | `COMMIT` returned success | `Commit`, landing on `committed` |
| `abort` | rolled back, `40001 serialization_failure` | `Commit`, landing on `aborted` |

Splitting `COMMIT` from `ROLLBACK` is what makes the check discriminate. The
model's `Commit` covers both outcomes — SSI aborts a transaction whose read set
moved, SI does not — so a log line has to say which one happened, and then only
one isolation level admits it. **That is how a log tells you the isolation
level you are really on.**

| Command | Expected | Domain meaning |
| --- | --- | --- |
| `tlc -config SeatLimitTrace.cfg SeatLimitTrace.tla` | no error (6 states, depth 6) | a quiet day: no contention, limit held |
| `tlc -config SeatLimitTrace_retry.cfg SeatLimitTrace.tla` | no error (7 states, depth 7) | contention *and* a `40001` — evidence the pool really is SSI |
| `tlc -config SeatLimitTrace_claimed.cfg SeatLimitTrace.tla` | `Temporal properties were violated`, final state `i = 6` | breaking variant: this history is impossible under `SERIALIZABLE` |
| `tlc -config SeatLimitTrace_actual.cfg SeatLimitTrace.tla` | `Invariant SeatsWithinLimit is violated` (`members = 2`) | breaking variant: at the level that admits it, the limit really broke |

The last two replay **the same incident log** and are the whole point of the
probe. Read them as a pair:

- at the level ops maintain the pool is set to, the log cannot have happened;
- at the level that does admit it, the seat limit is over.

Neither run alone identifies the fault. `_claimed` says "your model and your
store disagree" without saying which is wrong; `_actual` says "the limit broke"
without saying why it was allowed to. Together they say *the connection pool is
not on the isolation level you think it is* — which is a config bug, not a
concurrency bug, and would have been fixed in a different file.

Two green configs again, and again for different reasons: `SeatLimitTrace.cfg`
is green because nothing contended, `_retry` is green because something
contended and the store aborted it. Only the second is evidence *for* the
isolation level. A conformance check that only ever sees quiet days is not
measuring anything.

### Reading a failure

`TraceAccepted` is `<>(i > Len(Trace))` — the replay reached the end of the
log. When TLC reports it violated, the last state before `Stuttering` holds the
1-based index of the line that was refused:

```text
State 6: ...
/\ i = 6                                  <- log line 6 was refused
/\ pc = [t1 |-> "committed", t2 |-> "inserted"]
/\ members = 1
State 7: Stuttering
```

Line 6 of `incident.json` is t2's `COMMIT`. Under `SERIALIZABLE`, `members`
(1) has moved away from `snap[t2]` (0), so the model forces that transaction
onto the abort branch — and the log says it succeeded.

An operation the model has no action for is **refused, not skipped**: a log
that grew a `savepoint` line stalls the replay there rather than quietly
replaying around it. Drift in the log's vocabulary is drift worth a red build.

## Domain ledger

| field | value |
| --- | --- |
| source of truth | the invite handler's SQL and the isolation level the pool actually sets |
| claim | committed member rows never exceed the plan's seat limit |
| model question (T0) | is there a commit interleaving with `members > SeatLimit`? |
| model question (T5) | is last Tuesday's log a behaviour this model admits, at the isolation level we claim? |
| tool | TLA+ (TLC) |
| machine result (T0) | SERIALIZABLE: no error / SI: `SeatsWithinLimit` violated, `members = 2` / SI_LOCK: no error |
| machine result (T5) | incident log at SERIALIZABLE: `TraceAccepted` violated at line 6 / at SI: `SeatsWithinLimit` violated, `members = 2` |
| domain wording | "under REPEATABLE READ, two simultaneous invites both pass the seat check and both commit — and the log says REPEATABLE READ is what we were running" |
| lock | `just check-tla` |

## What this does NOT catch

- Retry behaviour after an SSI abort. `SERIALIZABLE` turns the bug into a
  `40001` serialization failure — correct only if the caller retries. An
  un-retried abort is a user-visible 500. The replay sees the `abort` line; it
  has no opinion on what the caller did next.
- Anything the projection dropped. `scripts/trace-to-tla.sh` keeps `op` and
  `txn` and throws away timestamps, SQL text, user ids and SQLSTATE. What it
  throws away, the replay can never contradict — so the projection, not the
  model, is where a T5 check is most easily fooled. Widening the alphabet is
  the fix; trusting the green is not.
- Whether the log is complete. A replay can only refuse steps it was shown. A
  transaction missing from the export is indistinguishable from one that never
  ran, and it is the missing writer that usually breaks an aggregate
  invariant. Establish completeness at the exporter (fixed backend_pid set,
  gapless sequence), not here.
- Sampling. A conformance check over one org and one window says nothing about
  the ones you did not replay. This is a witness-finder, not a proof.
- Lock ordering. `SI_LOCK` takes one lock; a handler taking two org locks in
  different orders can deadlock, which this single-lock model cannot show.
- Limits enforced across services or shards, where no single database sees
  both writes.
- A `CHECK` constraint or unique index would enforce some of these invariants
  in the engine. Where one exists, the invariant is not the application's to
  hold — model the constraint, not the handler.
