// パッケージの依存解決。
// requires: パッケージ -> 依存の候補グループ。各グループからどれか 1 つ以上が要る
// conflicts: 同時に入れられない組
export type Problem = {
  packages: string[];
  root: string;
  requires: Record<string, string[][]>;
  conflicts: [string, string][];
};

// 実装: 各グループの最初の候補を入れていく貪欲法 (後戻りしない)
export function resolveGreedy(p: Problem): Set<string> | null {
  const installed = new Set<string>();
  const stack = [p.root];
  while (stack.length > 0) {
    const pkg = stack.pop()!;
    if (installed.has(pkg)) continue;
    if (p.conflicts.some(([a, b]) => (a === pkg && installed.has(b)) || (b === pkg && installed.has(a)))) {
      return null; // 競合したら諦める
    }
    installed.add(pkg);
    for (const group of p.requires[pkg] ?? []) {
      if (!group.some((g) => installed.has(g))) stack.push(group[0]);
    }
  }
  return installed;
}

// 解が条件を満たしているかの検査 (実装が返した解のチェック用)
export function isValid(p: Problem, s: Set<string>): boolean {
  if (!s.has(p.root)) return false;
  for (const pkg of s) {
    for (const group of p.requires[pkg] ?? []) if (!group.some((g) => s.has(g))) return false;
  }
  return !p.conflicts.some(([a, b]) => s.has(a) && s.has(b));
}

// 直した実装: 候補を順に試して、行き詰まったら戻る
export function resolveBacktrack(p: Problem): Set<string> | null {
  // pkg を足したときに、競合する組が両方入ってしまうか (自分自身との競合も含む)
  const conflictsWith = (pkg: string, s: Set<string>) => {
    const next = new Set([...s, pkg]);
    return p.conflicts.some(([a, b]) => next.has(a) && next.has(b));
  };
  function go(s: Set<string>): Set<string> | null {
    for (const pkg of s) {
      for (const group of p.requires[pkg] ?? []) {
        if (group.some((g) => s.has(g))) continue;
        for (const cand of group) {
          if (conflictsWith(cand, s)) continue;
          const r = go(new Set([...s, cand]));
          if (r) return r;
        }
        return null; // このグループはどの候補でも満たせない
      }
    }
    return s;
  }
  return conflictsWith(p.root, new Set()) ? null : go(new Set([p.root]));
}
