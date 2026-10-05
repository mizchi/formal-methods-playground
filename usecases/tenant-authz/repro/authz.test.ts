import { test } from "node:test";
import assert from "node:assert/strict";
import { actionFor, canReadFixed, canReadImpl } from "./authz.ts";
import type { Resource, Role, User } from "./authz.ts";

const read = (f: typeof canReadImpl, u: User, r: Resource) => f(u, r, actionFor(r));

// Alloy ImplNoCrossTenantRead: a BillingAdmin in org B reads an invoice of org A.
test("witness: BillingAdmin reads another org's invoice", () => {
  const u: User = { org: "B", role: "BillingAdmin", supportOverride: false };
  const r: Resource = { org: "A", kind: "invoice" };
  assert.equal(read(canReadImpl, u, r), true);
  assert.equal(read(canReadFixed, u, r), false);
});

test("witness: Owner reads another org's project", () => {
  const u: User = { org: "B", role: "Owner", supportOverride: false };
  const r: Resource = { org: "A", kind: "project" };
  assert.equal(read(canReadImpl, u, r), true);
  assert.equal(read(canReadFixed, u, r), false);
});

// Alloy ImplNoBillingAdminProjectRead.
test("witness: BillingAdmin reads a project in its own org", () => {
  const u: User = { org: "A", role: "BillingAdmin", supportOverride: false };
  const r: Resource = { org: "A", kind: "project" };
  assert.equal(read(canReadImpl, u, r), true);
  assert.equal(read(canReadFixed, u, r), false);
});

// Alloy ImplSupportInvoiceOnly.
test("witness: a Member with the support override reads a project", () => {
  const u: User = { org: "A", role: "Member", supportOverride: true };
  const r: Resource = { org: "A", kind: "project" };
  assert.equal(read(canReadImpl, u, r), true);
  assert.equal(read(canReadFixed, u, r), false);
});

// The docs as a table: the oracle for every combination the model ranges over.
function documented(u: User, r: Resource): boolean {
  if (u.org !== r.org) return false;
  if (u.role === "Owner") return true;
  if (r.kind === "invoice" && (u.role === "BillingAdmin" || u.supportOverride)) return true;
  return false;
}

test("fixed rule agrees with the docs on all 24 combinations", () => {
  const roles: Role[] = ["Owner", "BillingAdmin", "Member"];
  let n = 0;
  for (const role of roles)
    for (const supportOverride of [false, true])
      for (const org of ["A", "B"])
        for (const kind of ["project", "invoice"] as const) {
          const u: User = { org: "A", role, supportOverride };
          const r: Resource = { org, kind };
          assert.equal(read(canReadFixed, u, r), documented(u, r), JSON.stringify({ u, r }));
          n++;
        }
  assert.equal(n, 24);
});
