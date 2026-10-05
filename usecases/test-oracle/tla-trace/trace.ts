// TLC の出力から、反例のトレースを読み出す
export type State = { action: string; vars: Record<string, string | number | boolean> };

export function parseTrace(tlcOutput: string): { states: State[]; stuttering: boolean } {
  const states: State[] = [];
  const blocks = tlcOutput.split(/\nState \d+: /).slice(1);
  for (const block of blocks) {
    const action = block.startsWith("<Initial predicate>") ? "Init" : (block.match(/^<(\w+)/)?.[1] ?? "Stuttering");
    const vars: State["vars"] = {};
    for (const m of block.matchAll(/^\/\\ (\w+) = (.+)$/gm)) {
      const raw = m[2].trim();
      vars[m[1]] = /^-?\d+$/.test(raw) ? Number(raw) : raw === "TRUE" ? true : raw === "FALSE" ? false : raw.replace(/^"|"$/g, "");
    }
    states.push({ action, vars });
  }
  const stuttering = /\nState \d+: Stuttering/.test(tlcOutput);
  return { states: states.filter((s) => s.action !== "Stuttering"), stuttering };
}

// .cfg の CONSTANTS を読む
export function parseConstants(cfg: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const m of cfg.matchAll(/^\s+(\w+)\s*=\s*(\S+)\s*$/gm)) out[m[1]] = m[2];
  return out;
}
