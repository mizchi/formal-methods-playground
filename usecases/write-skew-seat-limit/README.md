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
| Does the lock still help under REPEATABLE READ? | same model, snapshot taken before the lock wait | TLA+ | `REPEATABLE READ` + `FOR UPDATE` |

## Probe: TLA+

[`languages/tla/SeatLimitWriteSkew.tla`](../../languages/tla/SeatLimitWriteSkew.tla)

`Isolation` selects the store's commit rule:

| Value | Models |
| --- | --- |
| `"SI"` | snapshot read, first-committer-wins on the *same* row (PostgreSQL `REPEATABLE READ`, MySQL default) |
| `"SERIALIZABLE"` | PostgreSQL SSI: abort at commit if the read set moved |
| `"SI_LOCK"` | `SELECT ... FOR UPDATE` on the org row first, then read the count with a fresh snapshot (PostgreSQL `READ COMMITTED`) |
| `"RR_LOCK"` | the same lock under PostgreSQL `REPEATABLE READ`: the snapshot is taken before the locking statement waits |

| Command | Expected | Domain meaning |
| --- | --- | --- |
| `tlc -config SeatLimitWriteSkew.cfg SeatLimitWriteSkew.tla` | no error (21 states, depth 7) | SSI aborts the second transaction; the limit holds |
| `tlc -config SeatLimitWriteSkew_si.cfg SeatLimitWriteSkew.tla` | `Invariant SeatsWithinLimit is violated` (`members = 2`, limit 1) | breaking variant: plain snapshot isolation admits the write skew |
| `tlc -config SeatLimitWriteSkew_lock.cfg SeatLimitWriteSkew.tla` | no error (11 states, depth 6) | the explicit lock materialises the missing conflict |
| `tlc -config SeatLimitWriteSkew_rrlock.cfg SeatLimitWriteSkew.tla` | `Invariant SeatsWithinLimit is violated` (`members = 2`) | breaking variant: under `REPEATABLE READ` the lock is granted after the stale snapshot was taken, so it does not help |

Two green configs is deliberate. They are green for *different reasons*
(commit-time abort vs. mutual exclusion), so a change that drops one — someone
"optimising away" the `FOR UPDATE`, or a connection-pool setting that resets
the isolation level — cannot pass by leaning on the other.

```sh
nix develop -c just check-tla
nix develop -c bash -c 'cd languages/tla && tlc -config SeatLimitWriteSkew_si.cfg SeatLimitWriteSkew.tla'
nix develop -c bash -c 'cd languages/tla && tlc -config SeatLimitWriteSkew_rrlock.cfg SeatLimitWriteSkew.tla'
```

## The lock only works under READ COMMITTED

`SI_LOCK` used to be described as "still SI, plus `FOR UPDATE`". That is not
what PostgreSQL does. Under `REPEATABLE READ` the transaction snapshot is taken
when the first statement starts; if that statement is the `SELECT ... FOR
UPDATE` and it blocks, the snapshot is already fixed, and the count read after
the lock is granted is the stale one. The second invite still passes the check.

[`repro/`](repro/) runs the handler against PostgreSQL 17 with two
connections, pausing the first request after its read:

| Isolation | without `FOR UPDATE` | with `FOR UPDATE` |
| --- | --- | --- |
| `READ COMMITTED` (PostgreSQL default) | 2 members | 1 member (second invite sees the new count) |
| `REPEATABLE READ` | 2 members | **2 members** |
| `SERIALIZABLE` | 1 member (one `40001`) | 1 member (one `40001`) |

`RR_LOCK` models the stale snapshot and reproduces the same trace in TLC.
`SI_LOCK` is correct for `READ COMMITTED`, where every statement takes a new
snapshot.

```sh
cd usecases/write-skew-seat-limit/repro
pnpm install
PGHOST=localhost PGPORT=5432 pnpm test   # needs a PostgreSQL, e.g. postgres:17 in Docker
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

## Domain ledger

| field | value |
| --- | --- |
| source of truth | the invite handler's SQL and the isolation level the pool actually sets |
| claim | committed member rows never exceed the plan's seat limit |
| model question | is there a commit interleaving with `members > SeatLimit`? |
| tool | TLA+ (TLC) |
| machine result | SERIALIZABLE: no error / SI: `SeatsWithinLimit` violated, `members = 2` / SI_LOCK: no error / RR_LOCK: `SeatsWithinLimit` violated, `members = 2` |
| domain wording | "under REPEATABLE READ, two simultaneous invites both pass the seat check and both commit -- and adding FOR UPDATE does not change that; use READ COMMITTED + FOR UPDATE or SERIALIZABLE" |
| lock | `just check-tla` |

## What this does NOT catch

- Whether production actually runs at the isolation level you modelled. That is
  a config claim: assert it at connection setup, or read it back in a smoke
  test. The model tells you which answer is safe; it cannot tell you which one
  you deployed.
- Retry behaviour after an SSI abort. `SERIALIZABLE` turns the bug into a
  `40001` serialization failure — correct only if the caller retries. An
  un-retried abort is a user-visible 500.
- Lock ordering. `SI_LOCK` takes one lock; a handler taking two org locks in
  different orders can deadlock, which this single-lock model cannot show.
- Limits enforced across services or shards, where no single database sees
  both writes.
- A `CHECK` constraint or unique index would enforce some of these invariants
  in the engine. Where one exists, the invariant is not the application's to
  hold — model the constraint, not the handler.
