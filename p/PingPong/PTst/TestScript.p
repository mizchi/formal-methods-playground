// Test driver: spawn one Sender + one Receiver and wire them up.
machine TestPingPong {
  start state Init {
    entry {
      var r: machine;
      r = new Receiver();
      new Sender(r);
    }
  }
}

// Test case: run TestPingPong, monitor it with PingPongBalance.
// The checker explores all interleavings of message delivery and
// asserts the spec holds on every trace.
// Module composition: each machine class becomes a module so the
// `union` form in `test` can reference them.
module Senders   = { Sender };
module Receivers = { Receiver };

test tcPingPong [main=TestPingPong]:
  assert PingPongBalance in
  (union Senders, Receivers, { TestPingPong });
