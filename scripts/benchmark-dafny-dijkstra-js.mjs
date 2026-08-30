import { createRequire } from "node:module";
import { performance } from "node:perf_hooks";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const generatedPath = new URL("../build/dafny/dijkstra.js", import.meta.url);
const generated = readFileSync(generatedPath, "utf8").replace(
  /\n_dafny\.HandleHaltExceptions\(\(\) => _module\.__default\.Main[\s\S]*$/,
  "\n",
);
const require = createRequire(generatedPath);
const context = vm.createContext({ console, process, require });
vm.runInContext(generated, context, { filename: generatedPath.pathname });
const { algorithm, Edge, BigNumber } = vm.runInContext(
  "({ algorithm: _module.__default, Edge: _module.Edge, BigNumber })",
  context,
);

// Every newly settled vertex improves all later non-chain vertices. This
// deliberately exposes immutable seq.update copies in the reference version.
function worstCaseGraph(size) {
  return Array.from({ length: size }, (_, from) =>
    Array.from({ length: size }, (_, to) => {
      if (from >= to) return Edge.create_NoEdge();
      const weight = to === from + 1 ? 1 : 100_000 - 2 * from + to;
      return Edge.create_Weighted(new BigNumber(weight));
    }),
  );
}

function finiteValues(distances) {
  return Array.from(distances, (distance) => distance.dtor_value.toFixed());
}

function measureMedian(run) {
  let result;
  const samples = [];
  for (let repeat = 0; repeat < 3; repeat += 1) {
    const start = performance.now();
    result = run();
    samples.push(performance.now() - start);
  }
  samples.sort((left, right) => left - right);
  return { result, milliseconds: samples[1] };
}

const warmupGraph = worstCaseGraph(20);
algorithm.Dijkstra(warmupGraph, new BigNumber(0));
algorithm.DijkstraArray(warmupGraph, new BigNumber(0));

for (const size of [50, 100, 150, 200]) {
  const graph = worstCaseGraph(size);
  const sequence = measureMedian(() => algorithm.Dijkstra(graph, new BigNumber(0))[0]);
  const mutable = measureMedian(() => algorithm.DijkstraArray(graph, new BigNumber(0))[0]);
  if (finiteValues(sequence.result).join(",") !== finiteValues(mutable.result).join(",")) {
    throw new Error(`distance mismatch at V=${size}`);
  }
  console.log(
    JSON.stringify({
      vertices: size,
      sequenceMs: Number(sequence.milliseconds.toFixed(2)),
      mutableMs: Number(mutable.milliseconds.toFixed(2)),
      speedup: Number((sequence.milliseconds / mutable.milliseconds).toFixed(2)),
    }),
  );
}
