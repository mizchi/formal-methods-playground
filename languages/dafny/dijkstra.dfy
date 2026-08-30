// Verified Dijkstra probe for non-negative directed graphs.
//
// The adjacency matrix uses NoEdge instead of a numeric sentinel, and
// distances use Infinity instead of a fixed "large enough" integer. Both
// datatypes are executable and translate to JavaScript and Go.

datatype Edge = NoEdge | Weighted(weight: nat)
datatype Distance = Infinity | Finite(value: nat)
datatype Predecessor = NoPredecessor | Previous(vertex: nat)

function DistanceLeq(left: Distance, right: Distance): bool
{
  match right
  case Infinity => true
  case Finite(rightValue) =>
    match left
    case Infinity => false
    case Finite(leftValue) => leftValue <= rightValue
}

function AddWeight(distance: Distance, weight: nat): Distance
{
  match distance
  case Infinity => Infinity
  case Finite(value) => Finite(value + weight)
}

lemma DistanceLeqTransitive(a: Distance, b: Distance, c: Distance)
  requires DistanceLeq(a, b)
  requires DistanceLeq(b, c)
  ensures DistanceLeq(a, c)
{
  match c
  case Infinity =>
  case Finite(_) =>
    match b
    case Infinity =>
    case Finite(_) =>
      match a
      case Infinity =>
      case Finite(_) =>
}

lemma AddWeightMonotone(distance: Distance, upperBound: nat, weight: nat)
  requires DistanceLeq(distance, Finite(upperBound))
  ensures DistanceLeq(AddWeight(distance, weight), Finite(upperBound + weight))
{
  match distance
  case Infinity =>
  case Finite(_) =>
}

lemma DistanceLeqAddRight(smaller: Distance, base: Distance, weight: nat)
  requires DistanceLeq(smaller, base)
  ensures DistanceLeq(smaller, AddWeight(base, weight))
{
  match base
  case Infinity =>
  case Finite(_) =>
    match smaller
    case Infinity =>
    case Finite(_) =>
}

function HasCandidate(distances: seq<Distance>, visited: seq<bool>): bool
  requires |distances| == |visited|
{
  exists vertex ::
    0 <= vertex < |distances| &&
    !visited[vertex] &&
    distances[vertex].Finite?
}

function CountFalse(values: seq<bool>): nat
  decreases |values|
{
  if |values| == 0 then 0
  else (if values[0] then 0 else 1) + CountFalse(values[1..])
}

lemma CountFalseUpdate(values: seq<bool>, index: nat)
  requires index < |values|
  requires !values[index]
  ensures CountFalse(values[index := true]) + 1 == CountFalse(values)
  decreases |values|
{
  if index == 0 {
    assert values[0 := true][1..] == values[1..];
  } else {
    CountFalseUpdate(values[1..], index - 1);
    assert values[index := true][0] == values[0];
    assert values[index := true][1..] == values[1..][index - 1 := true];
  }
}

ghost predicate WellFormed(graph: seq<seq<Edge>>)
{
  && |graph| > 0
  && (forall u :: 0 <= u < |graph| ==> |graph[u]| == |graph|)
}

ghost predicate ValidPath(graph: seq<seq<Edge>>, path: seq<nat>)
  requires WellFormed(graph)
{
  && |path| > 0
  && (forall i :: 0 <= i < |path| ==> path[i] < |graph|)
  && (forall i :: 0 <= i < |path| - 1 ==>
                    graph[path[i]][path[i + 1]].Weighted?)
}

function PathCost(graph: seq<seq<Edge>>, path: seq<nat>): nat
  requires WellFormed(graph)
  requires ValidPath(graph, path)
  decreases |path|
{
  if |path| == 1 then 0
  else PathCost(graph, path[..|path| - 1])
       + graph[path[|path| - 2]][path[|path| - 1]].weight
}

lemma ExtendPath(
  graph: seq<seq<Edge>>,
  path: seq<nat>,
  next: nat)
  requires WellFormed(graph)
  requires ValidPath(graph, path)
  requires next < |graph|
  requires graph[path[|path| - 1]][next].Weighted?
  ensures ValidPath(graph, path + [next])
  ensures PathCost(graph, path + [next]) ==
          PathCost(graph, path) + graph[path[|path| - 1]][next].weight
{
  assert (path + [next])[..|path|] == path;
}

ghost predicate PathMatches(
  graph: seq<seq<Edge>>,
  source: nat,
  vertex: nat,
  distance: Distance,
  path: seq<nat>)
  requires WellFormed(graph)
  requires source < |graph|
  requires vertex < |graph|
{
  match distance
  case Infinity => |path| == 0
  case Finite(value) =>
    && ValidPath(graph, path)
    && path[0] == source
    && path[|path| - 1] == vertex
    && PathCost(graph, path) == value
}

ghost predicate DistancesAreShortest(
  graph: seq<seq<Edge>>,
  source: nat,
  distances: seq<Distance>,
  paths: seq<seq<nat>>)
  requires WellFormed(graph)
  requires source < |graph|
{
  && |distances| == |graph|
  && |paths| == |graph|
  && (forall vertex :: 0 <= vertex < |graph| ==>
                         PathMatches(graph, source, vertex, distances[vertex], paths[vertex]))
  && (forall vertex, path ::
        0 <= vertex < |graph| &&
        ValidPath(graph, path) &&
        path[0] == source &&
        path[|path| - 1] == vertex
        ==> match distances[vertex]
            case Infinity => false
            case Finite(value) => value <= PathCost(graph, path))
}

ghost predicate PathsMatchDistances(
  graph: seq<seq<Edge>>,
  source: nat,
  distances: seq<Distance>,
  paths: seq<seq<nat>>)
  requires WellFormed(graph)
  requires source < |graph|
{
  && |distances| == |graph|
  && |paths| == |graph|
  && (forall vertex :: 0 <= vertex < |graph| ==>
                         PathMatches(graph, source, vertex, distances[vertex], paths[vertex]))
}

// The executable implementation stores one predecessor per reachable vertex.
// Full paths exist only as ghost state and are erased by code generation.
ghost predicate ValidPredecessors(
  graph: seq<seq<Edge>>,
  source: nat,
  distances: seq<Distance>,
  predecessors: seq<Predecessor>)
  requires WellFormed(graph)
  requires source < |graph|
{
  && |predecessors| == |graph|
  && |distances| == |graph|
  && predecessors[source].NoPredecessor?
  && (forall vertex ::
        0 <= vertex < |graph| && distances[vertex].Infinity? ==>
          predecessors[vertex].NoPredecessor?)
  && (forall vertex ::
        0 <= vertex < |graph| &&
        vertex != source &&
        distances[vertex].Finite? ==>
          predecessors[vertex].Previous? &&
          predecessors[vertex].vertex < |graph| &&
          graph[predecessors[vertex].vertex][vertex].Weighted?)
}

ghost predicate ProcessedTriangle(
  graph: seq<seq<Edge>>,
  distances: seq<Distance>,
  visited: seq<bool>)
  requires WellFormed(graph)
  requires |distances| == |graph|
  requires |visited| == |graph|
{
  forall from, to ::
    0 <= from < |graph| &&
    0 <= to < |graph| &&
    visited[from] &&
    graph[from][to].Weighted?
    ==> DistanceLeq(
        distances[to],
        AddWeight(distances[from], graph[from][to].weight))
}

ghost predicate SettledBeforeFrontier(
  distances: seq<Distance>,
  visited: seq<bool>)
{
  && |distances| == |visited|
  && (forall settled, frontier ::
        0 <= settled < |visited| &&
        0 <= frontier < |visited| &&
        visited[settled] &&
        !visited[frontier] &&
        distances[frontier].Finite?
        ==> DistanceLeq(distances[settled], distances[frontier]))
}

ghost predicate Triangle(
  graph: seq<seq<Edge>>,
  distances: seq<Distance>)
  requires WellFormed(graph)
  requires |distances| == |graph|
{
  forall from, to ::
    0 <= from < |graph| &&
    0 <= to < |graph| &&
    graph[from][to].Weighted?
    ==> DistanceLeq(
        distances[to],
        AddWeight(distances[from], graph[from][to].weight))
}

lemma TriangleBoundsPath(
  graph: seq<seq<Edge>>,
  source: nat,
  distances: seq<Distance>,
  path: seq<nat>)
  requires WellFormed(graph)
  requires source < |graph|
  requires |distances| == |graph|
  requires distances[source] == Finite(0)
  requires Triangle(graph, distances)
  requires ValidPath(graph, path)
  requires path[0] == source
  ensures DistanceLeq(
            distances[path[|path| - 1]],
            Finite(PathCost(graph, path)))
  decreases |path|
{
  if |path| == 1 {
    assert path[0] == path[|path| - 1];
  } else {
    var prefix := path[..|path| - 1];
    assert ValidPath(graph, prefix);
    assert prefix[0] == source;
    TriangleBoundsPath(graph, source, distances, prefix);

    var previous := path[|path| - 2];
    var last := path[|path| - 1];
    var weight := graph[previous][last].weight;
    assert prefix[|prefix| - 1] == previous;
    assert DistanceLeq(distances[previous], Finite(PathCost(graph, prefix)));
    AddWeightMonotone(distances[previous], PathCost(graph, prefix), weight);
    assert DistanceLeq(distances[last], AddWeight(distances[previous], weight));
    DistanceLeqTransitive(
      distances[last],
      AddWeight(distances[previous], weight),
      Finite(PathCost(graph, prefix) + weight));
  }
}

method SelectMin(distances: seq<Distance>, visited: seq<bool>)
  returns (found: bool, vertex: nat)
  requires |distances| == |visited|
  requires |distances| > 0
  ensures found ==>
            vertex < |distances| && !visited[vertex] && distances[vertex].Finite?
  ensures found ==> forall other ::
              0 <= other < |distances| &&
              !visited[other] &&
              distances[other].Finite?
              ==> DistanceLeq(distances[vertex], distances[other])
  ensures !found ==> forall other ::
              0 <= other < |distances| && !visited[other]
              ==> distances[other].Infinity?
{
  found := false;
  vertex := 0;
  var i := 0;
  while i < |distances|
    invariant 0 <= i <= |distances|
    invariant found ==>
                vertex < i && !visited[vertex] && distances[vertex].Finite?
    invariant forall other ::
                0 <= other < i && !visited[other] && distances[other].Finite?
                ==> found && DistanceLeq(distances[vertex], distances[other])
  {
    if !visited[i] && distances[i].Finite? {
      if !found || distances[i].value < distances[vertex].value {
        found := true;
        vertex := i;
      }
    }
    i := i + 1;
  }
}

method SelectMinArray(distances: array<Distance>, visited: array<bool>)
  returns (found: bool, vertex: nat)
  requires distances.Length == visited.Length
  requires distances.Length > 0
  ensures found ==>
            vertex < distances.Length && !visited[vertex] && distances[vertex].Finite?
  ensures found ==> forall other ::
              0 <= other < distances.Length &&
              !visited[other] &&
              distances[other].Finite?
              ==> DistanceLeq(distances[vertex], distances[other])
  ensures !found ==> forall other ::
              0 <= other < distances.Length && !visited[other]
              ==> distances[other].Infinity?
{
  found := false;
  vertex := 0;
  var i := 0;
  while i < distances.Length
    invariant 0 <= i <= distances.Length
    invariant found ==>
                vertex < i && !visited[vertex] && distances[vertex].Finite?
    invariant forall other ::
                0 <= other < i && !visited[other] && distances[other].Finite?
                ==> found && DistanceLeq(distances[vertex], distances[other])
  {
    if !visited[i] && distances[i].Finite? {
      if !found || distances[i].value < distances[vertex].value {
        found := true;
        vertex := i;
      }
    }
    i := i + 1;
  }
}

method Dijkstra(graph: seq<seq<Edge>>, source: nat)
  returns (distances: seq<Distance>, paths: seq<seq<nat>>)
  requires WellFormed(graph)
  requires source < |graph|
  ensures DistancesAreShortest(graph, source, distances, paths)
{
  distances := seq(|graph|, vertex =>
    if vertex == source then Finite(0) else Infinity);
  paths := seq(|graph|, vertex =>
    if vertex == source then [source] else []);

  var visited := seq(|graph|, _ => false);

  assert PathsMatchDistances(graph, source, distances, paths);
  assert distances[source] == Finite(0);
  assert ProcessedTriangle(graph, distances, visited);
  assert SettledBeforeFrontier(distances, visited);

  while HasCandidate(distances, visited)
    invariant |distances| == |graph|
    invariant |paths| == |graph|
    invariant |visited| == |graph|
    invariant distances[source] == Finite(0)
    invariant PathsMatchDistances(graph, source, distances, paths)
    invariant ProcessedTriangle(graph, distances, visited)
    invariant SettledBeforeFrontier(distances, visited)
    invariant forall vertex ::
                0 <= vertex < |graph| && visited[vertex] ==>
                  distances[vertex].Finite?
    decreases |set vertex | 0 <= vertex < |graph| && !visited[vertex]|
  {
    var found, current := SelectMin(distances, visited);
    assert found;

    assert !visited[current];
    assert distances[current].Finite?;
    assert forall settled ::
        0 <= settled < |graph| && visited[settled] ==>
          DistanceLeq(distances[settled], distances[current]);

    ghost var visitedBefore := visited;
    ghost var distancesBeforeRelaxing := distances;
    ghost var settledBefore := set vertex |
    0 <= vertex < |graph| && visitedBefore[vertex];
    ghost var unvisitedBefore := set vertex |
    0 <= vertex < |graph| && !visitedBefore[vertex];
    assert current !in settledBefore;
    assert current in unvisitedBefore;
    visited := visited[current := true];
    assert (set vertex | 0 <= vertex < |graph| && visited[vertex]) ==
           settledBefore + {current};
    assert (set vertex | 0 <= vertex < |graph| && !visited[vertex]) ==
           unvisitedBefore - {current};
    assert |unvisitedBefore - {current}| < |unvisitedBefore|;

    var target := 0;
    while target < |graph|
      invariant 0 <= target <= |graph|
      invariant |distances| == |graph|
      invariant |paths| == |graph|
      invariant |visited| == |graph|
      invariant visited[current]
      invariant distances[current].Finite?
      invariant distances[source] == Finite(0)
      invariant PathsMatchDistances(graph, source, distances, paths)
      invariant forall vertex ::
                  0 <= vertex < |graph| ==>
                    DistanceLeq(distances[vertex], distancesBeforeRelaxing[vertex])
      invariant forall vertex ::
                  0 <= vertex < |graph| && visitedBefore[vertex] ==>
                    distances[vertex] == distancesBeforeRelaxing[vertex]
      invariant forall settled ::
                  0 <= settled < |graph| &&
                  visited[settled] && settled != current ==>
                    DistanceLeq(distances[settled], distances[current])
      invariant forall vertex ::
                  0 <= vertex < target && graph[current][vertex].Weighted? ==>
                    DistanceLeq(
                      distances[vertex],
                      AddWeight(distances[current], graph[current][vertex].weight))
      invariant forall settled, frontier ::
                  0 <= settled < |graph| &&
                  0 <= frontier < |graph| &&
                  visited[settled] && settled != current &&
                  !visited[frontier] &&
                  distances[frontier].Finite?
                  ==> DistanceLeq(distances[settled], distances[frontier])
      invariant forall frontier ::
                  0 <= frontier < |graph| &&
                  !visited[frontier] &&
                  distances[frontier].Finite?
                  ==> DistanceLeq(distances[current], distances[frontier])
      decreases |graph| - target
    {
      if visited[target] && graph[current][target].Weighted? {
        if target == current {
          DistanceLeqAddRight(
            distances[current], distances[current], graph[current][target].weight);
        } else {
          DistanceLeqAddRight(
            distances[target], distances[current], graph[current][target].weight);
        }
      }
      if !visited[target] && graph[current][target].Weighted? {
        var candidate := distances[current].value + graph[current][target].weight;
        if distances[target].Infinity? || candidate < distances[target].value {
          var newPath := paths[current] + [target];
          ExtendPath(graph, paths[current], target);
          distances := distances[target := Finite(candidate)];
          paths := paths[target := newPath];
        }
      }
      assert graph[current][target].Weighted? ==>
          DistanceLeq(
            distances[target],
            AddWeight(distances[current], graph[current][target].weight));
      target := target + 1;
    }

    forall from, to |
      0 <= from < |graph| &&
      0 <= to < |graph| &&
      visitedBefore[from] &&
      graph[from][to].Weighted?
      ensures DistanceLeq(
                distances[to],
                AddWeight(distances[from], graph[from][to].weight))
    {
      assert DistanceLeq(
          distancesBeforeRelaxing[to],
          AddWeight(
            distancesBeforeRelaxing[from], graph[from][to].weight));
      assert distances[from] == distancesBeforeRelaxing[from];
      DistanceLeqTransitive(
        distances[to],
        distancesBeforeRelaxing[to],
        AddWeight(distances[from], graph[from][to].weight));
    }
    assert ProcessedTriangle(graph, distances, visited);
  }

  assert forall vertex ::
      0 <= vertex < |graph| && !visited[vertex] ==>
        distances[vertex].Infinity?;
  assert Triangle(graph, distances);

  forall vertex, path |
    0 <= vertex < |graph| &&
    ValidPath(graph, path) &&
    path[0] == source &&
    path[|path| - 1] == vertex
    ensures match distances[vertex]
            case Infinity => false
            case Finite(value) => value <= PathCost(graph, path)
  {
    TriangleBoundsPath(graph, source, distances, path);
  }
}

// Runtime-oriented variant. Distances, visited flags, and predecessors are
// mutated in place. The path witnesses used by the shortest-path proof are
// ghost state, so JS/Go code generation does not allocate them.
method {:isolate_assertions} DijkstraArray(graph: seq<seq<Edge>>, source: nat)
  returns (distances: array<Distance>, predecessors: array<Predecessor>)
  requires WellFormed(graph)
  requires source < |graph|
  ensures distances.Length == |graph|
  ensures predecessors.Length == |graph|
  ensures exists paths: seq<seq<nat>> ::
            DistancesAreShortest(graph, source, distances[..], paths) &&
            ValidPredecessors(
              graph, source, distances[..], predecessors[..])
{
  distances := new Distance[|graph|](vertex =>
    if vertex == source then Finite(0) else Infinity);
  predecessors := new Predecessor[|graph|](_ => NoPredecessor);
  var visited := new bool[|graph|](_ => false);
  ghost var paths: seq<seq<nat>> := seq(|graph|, vertex =>
    if vertex == source then [source] else []);

  assert PathsMatchDistances(graph, source, distances[..], paths);
  assert ValidPredecessors(
    graph, source, distances[..], predecessors[..]);
  assert distances[source] == Finite(0);
  assert ProcessedTriangle(graph, distances[..], visited[..]);
  assert SettledBeforeFrontier(distances[..], visited[..]);

  var found := false;
  var current: nat := 0;
  while true
    invariant distances.Length == |graph|
    invariant predecessors.Length == |graph|
    invariant visited.Length == |graph|
    invariant distances[source] == Finite(0)
    invariant PathsMatchDistances(graph, source, distances[..], paths)
    invariant ValidPredecessors(
                graph, source, distances[..], predecessors[..])
    invariant ProcessedTriangle(graph, distances[..], visited[..])
    invariant SettledBeforeFrontier(distances[..], visited[..])
    invariant forall vertex ::
                0 <= vertex < |graph| && visited[vertex] ==>
                  distances[vertex].Finite?
    decreases CountFalse(visited[..])
  {
    ghost var falseCountBefore := CountFalse(visited[..]);
    found, current := SelectMinArray(distances, visited);
    if !found {
      break;
    }

    assert !visited[current];
    assert distances[current].Finite?;
    assert forall settled ::
        0 <= settled < |graph| && visited[settled] ==>
          DistanceLeq(distances[settled], distances[current]);

    ghost var visitedBefore := visited[..];
    ghost var distancesBeforeRelaxing := distances[..];
    ghost var settledBefore := set vertex |
      0 <= vertex < |graph| && visitedBefore[vertex];
    ghost var unvisitedBefore := set vertex |
      0 <= vertex < |graph| && !visitedBefore[vertex];
    assert current !in settledBefore;
    assert current in unvisitedBefore;
    CountFalseUpdate(visitedBefore, current);
    visited[current] := true;
    assert forall vertex :: 0 <= vertex < |graph| ==>
      visited[vertex] == (if vertex == current then true else visitedBefore[vertex]);
    assert visited[..] == visitedBefore[current := true];
    assert CountFalse(visited[..]) + 1 == falseCountBefore;
    assert (set vertex | 0 <= vertex < |graph| && visited[vertex]) ==
           settledBefore + {current};
    assert (set vertex | 0 <= vertex < |graph| && !visited[vertex]) ==
           unvisitedBefore - {current};
    assert |unvisitedBefore - {current}| < |unvisitedBefore|;

    ghost var proofDistances := distances[..];
    ghost var proofVisited := visited[..];
    var target := 0;
    while target < |graph|
      invariant 0 <= target <= |graph|
      invariant distances.Length == |graph|
      invariant predecessors.Length == |graph|
      invariant visited.Length == |graph|
      invariant distances[..] == proofDistances
      invariant visited[..] == proofVisited
      invariant proofVisited == visitedBefore[current := true]
      invariant proofVisited[current]
      invariant proofDistances[current].Finite?
      invariant proofDistances[source] == Finite(0)
      invariant PathsMatchDistances(graph, source, proofDistances, paths)
      invariant ValidPredecessors(
                  graph, source, proofDistances, predecessors[..])
      invariant forall vertex ::
                  0 <= vertex < |graph| ==>
                    DistanceLeq(proofDistances[vertex], distancesBeforeRelaxing[vertex])
      invariant forall vertex ::
                  0 <= vertex < |graph| && visitedBefore[vertex] ==>
                    proofDistances[vertex] == distancesBeforeRelaxing[vertex]
      invariant forall settled ::
                  0 <= settled < |graph| &&
                  proofVisited[settled] && settled != current ==>
                    DistanceLeq(proofDistances[settled], proofDistances[current])
      invariant forall vertex ::
                  0 <= vertex < target && graph[current][vertex].Weighted? ==>
                    DistanceLeq(
                      proofDistances[vertex],
                      AddWeight(proofDistances[current], graph[current][vertex].weight))
      invariant forall settled, frontier ::
                  0 <= settled < |graph| &&
                  0 <= frontier < |graph| &&
                  proofVisited[settled] && settled != current &&
                  !proofVisited[frontier] &&
                  proofDistances[frontier].Finite?
                  ==> DistanceLeq(proofDistances[settled], proofDistances[frontier])
      invariant forall frontier ::
                  0 <= frontier < |graph| &&
                  !proofVisited[frontier] &&
                  proofDistances[frontier].Finite?
                  ==> DistanceLeq(proofDistances[current], proofDistances[frontier])
      decreases |graph| - target
    {
      if visited[target] && graph[current][target].Weighted? {
        if target == current {
          DistanceLeqAddRight(
            distances[current], distances[current], graph[current][target].weight);
        } else {
          DistanceLeqAddRight(
            distances[target], distances[current], graph[current][target].weight);
        }
      }
      if !visited[target] && graph[current][target].Weighted? {
        var candidate := distances[current].value + graph[current][target].weight;
        if distances[target].Infinity? || candidate < distances[target].value {
          ghost var newPath := paths[current] + [target];
          ExtendPath(graph, paths[current], target);
          distances[target] := Finite(candidate);
          proofDistances := proofDistances[target := Finite(candidate)];
          predecessors[target] := Previous(current);
          paths := paths[target := newPath];
        }
      }
      assert graph[current][target].Weighted? ==>
          DistanceLeq(
            distances[target],
            AddWeight(distances[current], graph[current][target].weight));
      target := target + 1;
    }

    forall from, to |
      0 <= from < |graph| &&
      0 <= to < |graph| &&
      visitedBefore[from] &&
      graph[from][to].Weighted?
      ensures DistanceLeq(
                distances[to],
                AddWeight(distances[from], graph[from][to].weight))
    {
      assert DistanceLeq(
          distancesBeforeRelaxing[to],
          AddWeight(
            distancesBeforeRelaxing[from], graph[from][to].weight));
      assert distances[from] == distancesBeforeRelaxing[from];
      DistanceLeqTransitive(
        distances[to],
        distancesBeforeRelaxing[to],
        AddWeight(distances[from], graph[from][to].weight));
    }

    forall from, to |
      0 <= from < |graph| &&
      0 <= to < |graph| &&
      visited[from] &&
      graph[from][to].Weighted?
      ensures DistanceLeq(
                distances[to],
                AddWeight(distances[from], graph[from][to].weight))
    {
      if from == current {
        assert DistanceLeq(
          distances[to],
          AddWeight(distances[current], graph[current][to].weight));
      } else {
        assert from in settledBefore;
        assert visitedBefore[from];
      }
    }
    assert CountFalse(visited[..]) < falseCountBefore;
    assert ProcessedTriangle(graph, distances[..], visited[..]);
  }

  assert !found;
  assert forall vertex ::
      0 <= vertex < |graph| && !visited[vertex] ==>
        distances[vertex].Infinity?;
  assert Triangle(graph, distances[..]);

  forall vertex, path |
    0 <= vertex < |graph| &&
    ValidPath(graph, path) &&
    path[0] == source &&
    path[|path| - 1] == vertex
    ensures match distances[vertex]
            case Infinity => false
            case Finite(value) => value <= PathCost(graph, path)
  {
    TriangleBoundsPath(graph, source, distances[..], path);
  }
  assert DistancesAreShortest(graph, source, distances[..], paths);
}

// The canonical six-vertex example used as a proof-level regression test.
// The expected distances also satisfy Triangle, so they are lower bounds on
// every path. Concrete witness paths provide the matching upper bounds.
method CanonicalExample() returns (
    distances: seq<Distance>, paths: seq<seq<nat>>)
  ensures distances ==
          [Finite(0), Finite(7), Finite(9), Finite(20), Finite(20), Finite(11)]
{
  var graph := [
    [NoEdge,     Weighted(7),  Weighted(9),  NoEdge,      NoEdge,     Weighted(14)],
    [Weighted(7), NoEdge,      Weighted(10), Weighted(15), NoEdge,     NoEdge],
    [Weighted(9), Weighted(10), NoEdge,       Weighted(11), NoEdge,     Weighted(2)],
    [NoEdge,      Weighted(15), Weighted(11), NoEdge,      Weighted(6), NoEdge],
    [NoEdge,      NoEdge,       NoEdge,       Weighted(6), NoEdge,      Weighted(9)],
    [Weighted(14), NoEdge,      Weighted(2),  NoEdge,      Weighted(9), NoEdge]
  ];
  var expected :=
    [Finite(0), Finite(7), Finite(9), Finite(20), Finite(20), Finite(11)];
  var expectedPaths := [
    [0],
    [0, 1],
    [0, 2],
    [0, 2, 3],
    [0, 2, 5, 4],
    [0, 2, 5]
  ];

  assert WellFormed(graph);
  assert Triangle(graph, expected);
  assert forall vertex :: 0 <= vertex < |graph| ==>
                            ValidPath(graph, expectedPaths[vertex]);
  assert forall vertex :: 0 <= vertex < |graph| ==>
                            expectedPaths[vertex][0] == 0 &&
                            expectedPaths[vertex][|expectedPaths[vertex]| - 1] == vertex;
  assert PathCost(graph, expectedPaths[0]) == 0;
  assert PathCost(graph, expectedPaths[1]) == 7;
  assert PathCost(graph, expectedPaths[2]) == 9;
  assert PathCost(graph, expectedPaths[3]) == 20;
  assert PathCost(graph, expectedPaths[5]) == 11;
  assert expectedPaths[4] == [0, 2, 5, 4];
  assert expectedPaths[5] + [4] == expectedPaths[4];
  ExtendPath(graph, expectedPaths[5], 4);
  forall vertex | 0 <= vertex < |graph|
    ensures PathCost(graph, expectedPaths[vertex]) == expected[vertex].value
  {
    reveal PathCost;
    if vertex == 0 {
    } else if vertex == 1 {
    } else if vertex == 2 {
    } else if vertex == 3 {
    } else if vertex == 4 {
    } else {
      assert vertex == 5;
    }
  }

  distances, paths := Dijkstra(graph, 0);
  assert DistancesAreShortest(graph, 0, distances, paths);

  forall vertex | 0 <= vertex < |graph|
    ensures distances[vertex] == expected[vertex]
  {
    var knownPath := expectedPaths[vertex];
    assert ValidPath(graph, knownPath);
    assert knownPath[0] == 0;
    assert knownPath[|knownPath| - 1] == vertex;

    if distances[vertex].Infinity? {
      assert false;
    }

    var witnessPath := paths[vertex];
    assert PathMatches(graph, 0, vertex, distances[vertex], witnessPath);
    assert ValidPath(graph, witnessPath);
    assert witnessPath[0] == 0;
    TriangleBoundsPath(graph, 0, expected, witnessPath);
  }
}

// Executable regression contract for the mutable implementation.  Keeping
// this separate from CanonicalExample makes the performance-oriented state
// representation observable without weakening the sequence implementation's
// universal shortest-path proof.
method CanonicalArrayExample() returns (
    distances: array<Distance>, predecessors: array<Predecessor>)
  ensures distances[..] ==
          [Finite(0), Finite(7), Finite(9), Finite(20), Finite(20), Finite(11)]
{
  var graph := [
    [NoEdge,      Weighted(7),  Weighted(9),  NoEdge,      NoEdge,     Weighted(14)],
    [Weighted(7), NoEdge,       Weighted(10), Weighted(15), NoEdge,     NoEdge],
    [Weighted(9), Weighted(10), NoEdge,       Weighted(11), NoEdge,     Weighted(2)],
    [NoEdge,      Weighted(15), Weighted(11), NoEdge,      Weighted(6), NoEdge],
    [NoEdge,      NoEdge,       NoEdge,       Weighted(6), NoEdge,      Weighted(9)],
    [Weighted(14), NoEdge,      Weighted(2),  NoEdge,      Weighted(9), NoEdge]
  ];
  var expected :=
    [Finite(0), Finite(7), Finite(9), Finite(20), Finite(20), Finite(11)];
  var expectedPaths := [
    [0],
    [0, 1],
    [0, 2],
    [0, 2, 3],
    [0, 2, 5, 4],
    [0, 2, 5]
  ];
  assert WellFormed(graph);
  assert Triangle(graph, expected);
  assert forall vertex :: 0 <= vertex < |graph| ==>
                            ValidPath(graph, expectedPaths[vertex]);
  assert forall vertex :: 0 <= vertex < |graph| ==>
                            expectedPaths[vertex][0] == 0 &&
                            expectedPaths[vertex][|expectedPaths[vertex]| - 1] == vertex;
  assert PathCost(graph, expectedPaths[0]) == 0;
  assert PathCost(graph, expectedPaths[1]) == 7;
  assert PathCost(graph, expectedPaths[2]) == 9;
  assert PathCost(graph, expectedPaths[3]) == 20;
  assert PathCost(graph, expectedPaths[5]) == 11;
  assert expectedPaths[4] == [0, 2, 5, 4];
  assert expectedPaths[5] + [4] == expectedPaths[4];
  ExtendPath(graph, expectedPaths[5], 4);
  forall vertex | 0 <= vertex < |graph|
    ensures PathCost(graph, expectedPaths[vertex]) == expected[vertex].value
  {
    reveal PathCost;
    if vertex == 0 {
    } else if vertex == 1 {
    } else if vertex == 2 {
    } else if vertex == 3 {
    } else if vertex == 4 {
    } else {
      assert vertex == 5;
    }
  }

  distances, predecessors := DijkstraArray(graph, 0);
  ghost var paths: seq<seq<nat>> :|
    DistancesAreShortest(graph, 0, distances[..], paths) &&
    ValidPredecessors(graph, 0, distances[..], predecessors[..]);

  forall vertex | 0 <= vertex < |graph|
    ensures distances[vertex] == expected[vertex]
  {
    var knownPath := expectedPaths[vertex];
    assert ValidPath(graph, knownPath);
    assert knownPath[0] == 0;
    assert knownPath[|knownPath| - 1] == vertex;

    if distances[vertex].Infinity? {
      assert false;
    }

    var witnessPath := paths[vertex];
    assert PathMatches(graph, 0, vertex, distances[vertex], witnessPath);
    assert ValidPath(graph, witnessPath);
    assert witnessPath[0] == 0;
    TriangleBoundsPath(graph, 0, expected, witnessPath);
  }
}

method Main()
{
  var distances, paths := CanonicalExample();
  print "distances = ", distances, "\n";
  print "paths = ", paths, "\n";

  var arrayDistances, predecessors := CanonicalArrayExample();
  print "array distances = ", arrayDistances[..], "\n";
  print "predecessors = ", predecessors[..], "\n";
}
