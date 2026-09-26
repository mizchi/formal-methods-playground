// Z3 をオラクルにする: 「入れられる組み合わせは存在するか」を完全に答える
import { init } from "z3-solver";
import type { Problem } from "./resolver.ts";

const { Context } = await init();
const Z3 = Context("main");

export async function solvable(p: Problem): Promise<Set<string> | null> {
  const v = new Map(p.packages.map((name) => [name, Z3.Bool.const(name)]));
  const s = new Z3.Solver();
  s.add(v.get(p.root)!);
  for (const [pkg, groups] of Object.entries(p.requires)) {
    for (const group of groups) s.add(Z3.Implies(v.get(pkg)!, Z3.Or(...group.map((g) => v.get(g)!))));
  }
  for (const [a, b] of p.conflicts) s.add(Z3.Not(Z3.And(v.get(a)!, v.get(b)!)));
  if ((await s.check()) !== "sat") return null;
  const m = s.model();
  return new Set(p.packages.filter((name) => Z3.isTrue(m.eval(v.get(name)!))));
}
