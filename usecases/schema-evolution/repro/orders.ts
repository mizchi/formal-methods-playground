// An order message during a rolling deploy.
// v1 knows status pending|paid|cancelled and treats currency as optional.
// v2 adds status "refunded" and makes currency required.

export type Order = { id: string; status: string; currency?: string };

const V1_STATUS = ["pending", "paid", "cancelled"];
const V2_STATUS = [...V1_STATUS, "refunded"];

export class Rejected extends Error {}

// --- readers ---------------------------------------------------------------
export function v2ReadStrict(o: Order): Order {
  if (!V2_STATUS.includes(o.status)) throw new Rejected(`unknown status ${o.status}`);
  if (o.currency === undefined) throw new Rejected("currency is required");
  return o;
}

export function v2ReadTolerant(o: Order): Order {
  if (!V2_STATUS.includes(o.status)) throw new Rejected(`unknown status ${o.status}`);
  return { ...o, currency: o.currency ?? "JPY" }; // default the missing field
}

export function v1ReadStrict(o: Order): Order {
  if (!V1_STATUS.includes(o.status)) throw new Rejected(`unknown status ${o.status}`);
  return o;
}

// Tolerant v1 readers: accept anything, map an unknown status to something v1 knows.
export function v1ReadFallbackPending(o: Order): Order {
  return V1_STATUS.includes(o.status) ? o : { ...o, status: "pending" }; // fail-open
}

export function v1ReadFallbackHold(o: Order): Order {
  return V1_STATUS.includes(o.status) ? o : { ...o, status: "hold" }; // fail-closed
}

// --- what v1 does with what it parsed -----------------------------------------
export function v1Process(o: Order, capture: (id: string) => void) {
  if (o.status === "pending") capture(o.id); // v1 captures payment for pending orders
}
