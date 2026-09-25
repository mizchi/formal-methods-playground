// The invite handler: count the members, check the seat limit, insert one.
import type pg from "pg";

export type Options = {
  isolation: "READ COMMITTED" | "REPEATABLE READ" | "SERIALIZABLE";
  lockOrg: boolean; // SELECT ... FOR UPDATE on the org row first
};

export type Hooks = { afterRead?: () => Promise<void> };

export async function setup(db: pg.Client, seatLimit: number) {
  await db.query(`
    DROP TABLE IF EXISTS members; DROP TABLE IF EXISTS orgs;
    CREATE TABLE orgs (id int PRIMARY KEY, seat_limit int NOT NULL);
    CREATE TABLE members (org_id int NOT NULL REFERENCES orgs(id), user_id text NOT NULL);
  `);
  await db.query("INSERT INTO orgs VALUES (1, $1)", [seatLimit]);
}

export async function invite(
  db: pg.Client,
  orgId: number,
  userId: string,
  opts: Options,
  hooks: Hooks = {},
): Promise<"invited" | "full" | "serialization_failure"> {
  await db.query(`BEGIN ISOLATION LEVEL ${opts.isolation}`);
  try {
    if (opts.lockOrg) {
      await db.query("SELECT 1 FROM orgs WHERE id = $1 FOR UPDATE", [orgId]);
    }
    const { rows } = await db.query(
      `SELECT (SELECT count(*) FROM members WHERE org_id = $1)::int AS count,
              (SELECT seat_limit FROM orgs WHERE id = $1) AS seat_limit`,
      [orgId],
    );
    await hooks.afterRead?.();
    if (rows[0].count >= rows[0].seat_limit) {
      await db.query("ROLLBACK");
      return "full";
    }
    await db.query("INSERT INTO members (org_id, user_id) VALUES ($1, $2)", [orgId, userId]);
    await db.query("COMMIT");
    return "invited";
  } catch (e: any) {
    await db.query("ROLLBACK").catch(() => {});
    if (e.code === "40001") return "serialization_failure";
    throw e;
  }
}
