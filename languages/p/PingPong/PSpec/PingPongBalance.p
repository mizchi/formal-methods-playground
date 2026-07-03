// Safety spec: every ePong must be preceded by some ePing. If a
// Receiver implementation ever emitted a spurious ePong (e.g. on
// machine startup, or after a state-transition bug) the assertion
// fires and the test scenario fails.
//
// The spec runs as a monitor — a global observer machine that
// receives a copy of every ePing / ePong sent in the system. It
// has no effect on the simulated execution, only verdict.
spec PingPongBalance observes ePing, ePong {
  var pendingPings: int;

  start state Init {
    on ePing do {
      pendingPings = pendingPings + 1;
    }
    on ePong do {
      assert pendingPings > 0,
        "Spec violation: received ePong without a pending ePing";
      pendingPings = pendingPings - 1;
    }
  }
}
