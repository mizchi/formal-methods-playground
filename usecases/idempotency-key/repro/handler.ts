// A payment handler that takes an Idempotency-Key.
// It does two things that are NOT one transaction:
//   1. charge the card through a provider (external side effect)
//   2. record "this key is handled" in our DB (local durable record)

export type Design = {
  reserveFirst: boolean; // write the key row before calling the provider?
  takeoverReserved: boolean; // may a retry resume a row it finds "reserved"?
  providerIdempotent: boolean; // does the provider dedupe on the same key?
};

export class Crash extends Error {}

type CrashPoint = "afterReserve" | "afterCharge";

export function createSystem(design: Design) {
  const keys = new Map<string, "reserved" | "done">(); // idempotency_keys table
  const providerSeen = new Set<string>();
  let charges = 0;
  let crashAt: CrashPoint | null = null;

  function crashIf(point: CrashPoint) {
    if (crashAt === point) {
      crashAt = null;
      throw new Crash(point);
    }
  }

  function charge(key: string) {
    if (design.providerIdempotent && providerSeen.has(key)) return;
    providerSeen.add(key);
    charges++;
  }

  function handle(key: string): "ok" | "conflict" {
    const rec = keys.get(key);
    if (rec === "done") return "ok"; // replay the stored result
    if (rec === "reserved" && !design.takeoverReserved) return "conflict"; // 409
    if (rec === undefined && design.reserveFirst) keys.set(key, "reserved");
    crashIf("afterReserve");
    charge(key);
    crashIf("afterCharge");
    keys.set(key, "done");
    return "ok";
  }

  return {
    handle,
    crashOnce(point: CrashPoint) {
      crashAt = point;
    },
    get charges() {
      return charges;
    },
  };
}

// The caller: retry on crash (timeout) or 409, up to `attempts` times.
export function callWithRetry(
  handle: (key: string) => "ok" | "conflict",
  key: string,
  attempts = 5,
): "ok" | "gave up" {
  for (let i = 0; i < attempts; i++) {
    try {
      if (handle(key) === "ok") return "ok";
    } catch (e) {
      if (!(e instanceof Crash)) throw e;
    }
  }
  return "gave up";
}
