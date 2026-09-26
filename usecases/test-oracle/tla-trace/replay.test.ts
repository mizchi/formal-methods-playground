import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parseTrace, parseConstants } from "./trace.ts";
import { createSystem, callWithRetry } from "../../idempotency-key/repro/handler.ts";

// TLC の反例を、実装のテストケースに変換する
function scenarioFrom(name: string) {
  const { states, stuttering } = parseTrace(readFileSync(`${name}.out`, "utf8"));
  const c = parseConstants(readFileSync(`../../../languages/tla/IdempotentRetry_${name}.cfg`, "utf8"));
  const i = states.findIndex((s) => s.action === "Crash");
  // Crash の直前の pc で、どこで落ちたかがわかる
  const crashAt = states[i - 1].vars.pc === "storing" ? "afterCharge" : "afterReserve";
  return {
    design: { reserveFirst: c.ReserveFirst === "TRUE", takeoverReserved: c.TakeoverReserved === "TRUE", providerIdempotent: c.ProviderIdempotent === "TRUE" },
    crashAt: crashAt as "afterCharge" | "afterReserve",
    finalCharges: states.at(-1)!.vars.charges as number,
    settles: !stuttering,
  };
}

for (const name of ["late", "blocking"]) {
  test(`TLC の反例 (${name}) を実装で再生する`, () => {
    const s = scenarioFrom(name);
    const sys = createSystem(s.design);
    sys.crashOnce(s.crashAt);
    const result = callWithRetry(sys.handle, "k1");
    // 反例の最後の状態と同じことが、実装でも起きる
    assert.equal(sys.charges, s.finalCharges);
    assert.equal(result === "ok", s.settles);
    console.log(name, s);
  });
}
