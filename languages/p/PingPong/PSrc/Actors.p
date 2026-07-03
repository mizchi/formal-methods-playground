// Events
//   ePing carries the sender's machine reference so the receiver
//   knows where to address its reply.
//   ePong is the reply; no payload needed.
event ePing : machine;
event ePong;

// Sender: fires ePing, waits for ePong, fires again. Stops after
// three round trips so the test terminates.
machine Sender {
  var receiver: machine;
  var roundTrips: int;

  start state Init {
    entry (r: machine) {
      receiver = r;
      roundTrips = 0;
      goto Sending;
    }
  }

  state Sending {
    entry {
      roundTrips = roundTrips + 1;
      send receiver, ePing, this;
      goto WaitForPong;
    }
  }

  state WaitForPong {
    on ePong do {
      if (roundTrips < 3) {
        goto Sending;
      }
    }
  }
}

// Receiver: replies to every ePing with ePong. Stateless.
machine Receiver {
  start state Listening {
    on ePing do (sender: machine) {
      send sender, ePong;
    }
  }
}
