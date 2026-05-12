/*
 * Probe: application-level RBAC + screen-navigation verifier.
 *
 * Models a small SaaS shape:
 *   3 roles     — Viewer, Editor, Admin
 *   5 screens   — Login, Dashboard, Settings, UserList, AuditLog
 *   3 dynamic actions per step — login, logout, navigate.
 *
 * The "validity" we want to express is split into three styles
 * of statement so the team can see what Alloy actually produces
 * for each:
 *
 *   1. SAFETY    — "no Viewer ever lands on Settings"
 *   2. SAFETY    — "non-admins are never at Settings"
 *   3. SANITY    — "an Admin CAN reach Settings" (non-vacuity check;
 *                  otherwise the model could trivially satisfy 1 + 2
 *                  by being unable to move)
 *
 * Run from this directory (Alloy 6 CLI):
 *
 *   alloy6 exec --command ViewerScopedToPublicScreens app-rbac.als
 *   alloy6 exec --command NonAdminNeverAtSettings     app-rbac.als
 *   alloy6 exec --command AdminCanReachSettings        app-rbac.als
 *
 * First two should report "No counterexample found".
 * Third should produce a concrete trace with an Admin at Settings.
 *
 * To watch the verifier *catch* a bug, weaken allowedFor[Editor]
 * to include Settings and re-run NonAdminNeverAtSettings — Alloy
 * produces a 2-step counter-example trace.
 */

// ── Static structure ─────────────────────────────────────────────

abstract sig Role {}
one sig Viewer, Editor, Admin extends Role {}

abstract sig Screen {}
one sig Login, Dashboard, Settings, UserList, AuditLog extends Screen {}

sig User {
  role: one Role
}

// Authorisation table: which screens a role is allowed to be on.
fun allowedFor[r: Role]: set Screen {
  r = Viewer  implies Login + Dashboard
  else r = Editor implies Login + Dashboard + AuditLog
  else /* Admin */ Login + Dashboard + Settings + UserList + AuditLog
}

// Navigation topology: edges of the screen graph (role-agnostic).
fun adjacent[s: Screen]: set Screen {
  s = Login     implies Dashboard
  else s = Dashboard implies Settings + UserList + AuditLog + Login
  else /* leaf */ Dashboard + Login
}

// ── Dynamic state (Alloy 6 temporal `var`) ───────────────────────

var sig LoggedIn in User {
  var at: one Screen
}

pred init {
  no LoggedIn
}

pred login[u: User] {
  u not in LoggedIn
  LoggedIn' = LoggedIn + u
  at' = at ++ (u -> Login)
}

pred logout[u: User] {
  u in LoggedIn
  LoggedIn' = LoggedIn - u
  at' = at - (u -> Screen)
}

pred navigate[u: User, s: Screen] {
  u in LoggedIn
  s in adjacent[u.at]            // graph edge exists
  s in allowedFor[u.role]        // RBAC gate
  LoggedIn' = LoggedIn
  at' = at ++ (u -> s)
}

fact behavior {
  init
  always (
    some u: User |
      login[u]
      or logout[u]
      or (some s: Screen | navigate[u, s])
  )
}

// ── Properties ───────────────────────────────────────────────────

// SAFETY: a Viewer is observed only on public screens.
assert ViewerScopedToPublicScreens {
  always (all u: LoggedIn |
    u.role = Viewer implies u.at in (Login + Dashboard))
}
check ViewerScopedToPublicScreens for 4 but 6 steps

// SAFETY: non-admins are never on Settings.
assert NonAdminNeverAtSettings {
  always (all u: LoggedIn |
    u.role != Admin implies u.at != Settings)
}
check NonAdminNeverAtSettings for 4 but 6 steps

// SANITY: an admin CAN reach Settings. (Non-vacuity check.)
run AdminCanReachSettings {
  some u: User | u.role = Admin and
    eventually (u in LoggedIn and u.at = Settings)
} for 4 but 6 steps
