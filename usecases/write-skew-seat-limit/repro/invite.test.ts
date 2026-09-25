// Needs a PostgreSQL: PGHOST=... PGPORT=... pnpm test
// e.g. docker run --rm -p 5432:5432 -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17
import { test } from "node:test";
import assert from "node:assert/strict";
import pg from "pg";
import { setup, invite, type Options } from "./invite.ts";

const conn = {
  host: process.env.PGHOST ?? "localhost",
  port: Number(process.env.PGPORT ?? 5432),
  user: process.env.PGUSER ?? "postgres",
  database: process.env.PGDATABASE ?? "postgres",
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// Two admins click "invite" at the same time on a 1-seat plan.
// t1 pauses after its read long enough for t2 to reach its own read
// (or to block on the org row lock).
async function twoAdminsInvite(opts: Options) {
  const a = new pg.Client(conn), b = new pg.Client(conn), admin = new pg.Client(conn);
  await Promise.all([a.connect(), b.connect(), admin.connect()]);
  try {
    await setup(admin, 1);
    const results = await Promise.all([
      invite(a, 1, "alice", opts, { afterRead: () => sleep(300) }),
      sleep(50).then(() => invite(b, 1, "bob", opts)),
    ]);
    const { rows } = await admin.query("SELECT count(*)::int AS n FROM members");
    return { results, members: rows[0].n as number };
  } finally {
    await Promise.all([a.end(), b.end(), admin.end()]);
  }
}

test("REPEATABLE READ: both invites pass the seat check (write skew)", async () => {
  const r = await twoAdminsInvite({ isolation: "REPEATABLE READ", lockOrg: false });
  assert.deepEqual(r.results, ["invited", "invited"]);
  assert.equal(r.members, 2);
});

test("READ COMMITTED (PostgreSQL default): same write skew", async () => {
  const r = await twoAdminsInvite({ isolation: "READ COMMITTED", lockOrg: false });
  assert.equal(r.members, 2);
});

test("SERIALIZABLE: one invite fails with 40001, the limit holds", async () => {
  const r = await twoAdminsInvite({ isolation: "SERIALIZABLE", lockOrg: false });
  assert.ok(r.results.includes("serialization_failure"));
  assert.equal(r.members, 1);
});

test("READ COMMITTED + FOR UPDATE: the second invite sees the new count", async () => {
  const r = await twoAdminsInvite({ isolation: "READ COMMITTED", lockOrg: true });
  assert.deepEqual(r.results, ["invited", "full"]);
  assert.equal(r.members, 1);
});

// The model's SI_LOCK assumes the count is read after the lock is acquired.
// Under REPEATABLE READ the snapshot is taken when the first statement starts,
// before it waits for the lock -- so the lock does not help.
test("REPEATABLE READ + FOR UPDATE: the lock does NOT fix it", async () => {
  const r = await twoAdminsInvite({ isolation: "REPEATABLE READ", lockOrg: true });
  assert.equal(r.members, 2);
});
