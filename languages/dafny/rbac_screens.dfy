// Probe: the same RBAC + screen-navigation domain we did in Alloy,
// now in Dafny.
//
// Side-by-side comparison: languages/alloy/app-rbac.als checks the property
// in finite scope and returns instance graphs; this Dafny version
// uses a stateful Session class with a ghost history sequence and
// proves the same property as a lemma — discharged by SMT, valid
// for ANY trace length, no scope bound.
//
// Run:  dafny verify rbac_screens.dfy
// Expect: "Dafny program verifier finished with N verified, 0 errors"
//
// To watch the verifier catch a bug, change the Viewer arm of
// `Allowed` to include `Settings`. The `ViewerNeverAtSettings`
// lemma's post-condition stops being provable and Dafny reports
// it on the lemma line.

datatype Role = Viewer | Editor | Admin

datatype Screen = Login | Dashboard | Settings | UserList | AuditLog

// Static authorisation table. `predicate` here is a pure boolean
// function — same shape as Alloy's `fun allowedFor[r: Role]`.
predicate Allowed(r: Role, s: Screen)
{
  match r
  case Viewer => s == Login || s == Dashboard
  case Editor => s == Login || s == Dashboard || s == AuditLog
  case Admin  => true
}

// Screen-graph adjacency (transition topology). Mirrors
// Alloy's `fun adjacent[s: Screen]`.
predicate Adjacent(from: Screen, to: Screen)
{
  match from
  case Login     => to == Dashboard
  case Dashboard => to == Settings || to == UserList || to == AuditLog || to == Login
  case _         => to == Dashboard || to == Login
}

// A logged-in session. State + history; Valid() is the
// across-step invariant.
class Session {
  var role: Role
  var screen: Screen
  ghost var history: seq<Screen>

  // Object invariant: the current screen is reachable for the
  // session's role AND every screen ever visited was reachable.
  // The conjunction with the history list is what makes the
  // lemma below discharge — without it, the SMT cannot connect
  // "the current value is allowed" to "no past value was X."
  ghost predicate Valid()
    reads this
  {
    && Allowed(role, screen)
    && |history| > 0
    && history[|history| - 1] == screen
    && (forall i :: 0 <= i < |history| ==> Allowed(role, history[i]))
  }

  constructor (r: Role)
    ensures Valid()
    ensures role == r
    ensures screen == Login
  {
    role := r;
    screen := Login;
    history := [Login];
  }

  // Navigate to a new screen. Three pre-conditions encode the
  // operation's authorisation gate: must currently be valid,
  // the graph must have the edge, and the role must permit the
  // destination.
  method Navigate(to: Screen)
    requires Valid()
    requires Adjacent(screen, to)
    requires Allowed(role, to)
    modifies this
    ensures Valid()
    ensures screen == to
    ensures role == old(role)
    ensures history == old(history) + [to]
  {
    screen := to;
    history := history + [to];
  }
}

// Safety property — proved as a lemma, valid for ANY session
// regardless of trace length. The Alloy version checks this for
// scope 4 with 6 steps; the Dafny version is universally
// quantified over `i` and discharged by SMT from the invariant
// chain in `Valid()`.
lemma ViewerNeverAtSettings(s: Session)
  requires s.Valid()
  requires s.role == Viewer
  ensures forall i :: 0 <= i < |s.history| ==> s.history[i] != Settings
{
  // SMT discharges automatically: Valid() guarantees
  //   forall i :: 0 <= i < |s.history| ==> Allowed(s.role, s.history[i])
  // and with s.role == Viewer this restricts each history[i] to
  // {Login, Dashboard} by definition of Allowed.
}

// Symmetric: an Editor is never at Settings either.
lemma EditorNeverAtSettings(s: Session)
  requires s.Valid()
  requires s.role == Editor
  ensures forall i :: 0 <= i < |s.history| ==> s.history[i] != Settings
{
}

// Generalised: any non-Admin is never at Settings. This subsumes
// the two lemmas above; kept as a separate one to show the
// match-based case-split style Dafny prefers.
lemma NonAdminNeverAtSettings(s: Session)
  requires s.Valid()
  requires s.role != Admin
  ensures forall i :: 0 <= i < |s.history| ==> s.history[i] != Settings
{
}

// Non-vacuity / sanity: there exists an Admin trajectory that
// actually reaches Settings. The Alloy version finds this via
// `run AdminCanReachSettings`; the Dafny version exhibits it
// constructively with a method that walks the trace.
method AdminCanReachSettings() returns (s: Session)
  ensures s.Valid()
  ensures s.role == Admin
  ensures Settings in s.history
{
  s := new Session(Admin);
  s.Navigate(Dashboard);
  s.Navigate(Settings);
}
