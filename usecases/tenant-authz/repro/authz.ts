export type Role = "Owner" | "BillingAdmin" | "Member";
export type User = { org: string; role: Role; supportOverride: boolean };
export type Resource = { org: string; kind: "project" | "invoice" };
export type Action = "read_project" | "read_invoice";

export function actionFor(resource: Resource): Action {
  return resource.kind === "project" ? "read_project" : "read_invoice";
}

// The implementation as observed. `resource` is unused, which is the bug.
export function canReadImpl(user: User, _resource: Resource, action: Action): boolean {
  if (user.role === "Owner") return true;
  if (user.role === "BillingAdmin" &&
      (action === "read_invoice" || action === "read_project")) return true;
  if (user.supportOverride) return true;
  return false;
}

// The fix checked by authz.als (FixedCanRead).
export function canReadFixed(user: User, resource: Resource, action: Action): boolean {
  if (user.org !== resource.org) return false;
  if (user.role === "Owner") return true;
  if (action === "read_invoice" &&
      (user.role === "BillingAdmin" || user.supportOverride)) return true;
  return false;
}
