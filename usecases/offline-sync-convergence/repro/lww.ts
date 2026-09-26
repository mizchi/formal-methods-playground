// Last-writer-wins on one field, as offline-first apps usually write it.

export type Update = { value: string; time: number; replica: string };

// The homegrown merge: newer wins, and on a tie "keep what I already have".
export function mergeNaive(local: Update | undefined, incoming: Update): Update {
  if (!local || incoming.time > local.time) return incoming;
  return local;
}

// Newer wins, replica id breaks ties: a total order on (time, replica).
export function mergeWithTiebreak(local: Update | undefined, incoming: Update): Update {
  if (!local) return incoming;
  if (incoming.time !== local.time) return incoming.time > local.time ? incoming : local;
  return incoming.replica > local.replica ? incoming : local;
}

// A device applies the updates it receives, in the order they arrive.
export function replay(merge: typeof mergeNaive, updates: Update[]): string | undefined {
  let state: Update | undefined;
  for (const u of updates) state = merge(state, u);
  return state?.value;
}

// A per-replica clock that never repeats a stamp (bump past the last stamp).
export function monotonicClock(now: () => number) {
  let last = -Infinity;
  return () => {
    last = Math.max(now(), last + 1);
    return last;
  };
}
