import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveGreedy, resolveBacktrack, isValid, type Problem } from "./resolver.ts";
import { solvable } from "./oracle.ts";

// 再現できるように、乱数は種を固定する
function rng(seed: number) {
  return () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
}

function randomProblem(r: () => number): Problem {
  const packages = ["root", "a", "b", "c", "d", "e"];
  const pick = () => packages[1 + Math.floor(r() * (packages.length - 1))];
  const requires: Record<string, string[][]> = {};
  for (const pkg of packages) {
    if (r() < 0.6) requires[pkg] = [[pick(), pick()]]; // 2 つの候補のどちらか
  }
  const conflicts: [string, string][] = [];
  for (let i = 0; i < 2; i++) conflicts.push([pick(), pick()]);
  return { packages, root: "root", requires, conflicts };
}

// 実装とオラクル (Z3) の判断が最初に食い違う問題を探す (200 問)
async function firstMismatch(resolve: (p: Problem) => Set<string> | null) {
  const r = rng(1);
  for (let i = 0; i < 200; i++) {
    const p = randomProblem(r);
    const ours = resolve(p);
    const z3 = await solvable(p);
    if (ours) assert.ok(isValid(p, ours), `実装の解が条件を満たさない: ${JSON.stringify(p)}`);
    if ((ours !== null) !== (z3 !== null)) return { problem: p, ours, z3 };
  }
  return null;
}

test("貪欲法の実装は、Z3 が解けると言う問題で「無理」と答える", async () => {
  const m = await firstMismatch(resolveGreedy);
  assert.ok(m);
  console.log("反例:", JSON.stringify(m.problem), "/ Z3 の解:", [...m.z3!].join(","));
});

test("後戻りする実装は、200 問すべてで Z3 と一致する", async () => {
  assert.equal(await firstMismatch(resolveBacktrack), null);
});
