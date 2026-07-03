/-
  Probe: RBAC role-hierarchy monotonicity.

  Same domain as languages/alloy/app-rbac.als, but the proof obligation is
  *universal* over the entire Permission type — not bounded by a
  finite scope. This is what an ITP buys you over a model finder:
  the theorem holds for every permission, not just permissions
  the solver could enumerate in 5 instances.

  Run from this directory inside the formal-methods-playground nix devShell:

    lean Rbac.lean

  Expect:
    no output. Lean prints nothing on success; errors and `#check`
    output go to stderr.

  To watch Lean catch a wrong theorem, uncomment the
  `editor_subset_viewer` block at the bottom — the case for
  `Permission.write` cannot close and Lean reports the open goal.
-/

inductive Role
  | viewer
  | editor
  | admin
  deriving DecidableEq

inductive Permission
  | read
  | write
  | manage
  deriving DecidableEq

def permits : Role → Permission → Bool
  | .viewer, .read   => true
  | .editor, .read   => true
  | .editor, .write  => true
  | .admin,  _       => true
  | _, _             => false

-- Sanity: the table behaves as expected on each role.
example : permits .viewer .read   = true  := rfl
example : permits .viewer .write  = false := rfl
example : permits .editor .write  = true  := rfl
example : permits .admin  .manage = true  := rfl

/-- Editor inherits every Viewer permission.

    The proof is by case-analysis on the permission. For each
    case (read / write / manage), both sides reduce to literal
    booleans and `simp [permits]` closes the goal. -/
theorem viewer_subset_editor :
    ∀ p : Permission, permits .viewer p = true → permits .editor p = true := by
  intro p h
  cases p <;> simp_all [permits]

/-- Admin inherits every Editor permission.

    Editor → Admin is a stronger claim than Viewer → Editor: the
    admin clause uses a wildcard, so the proof discharges by
    `simp` directly. -/
theorem editor_subset_admin :
    ∀ p : Permission, permits .editor p = true → permits .admin p = true := by
  intro p h
  cases p <;> simp_all [permits]

/-- Transitivity: combining the two inclusions, Viewer ⊆ Admin. -/
theorem viewer_subset_admin :
    ∀ p : Permission, permits .viewer p = true → permits .admin p = true := by
  intro p h
  exact editor_subset_admin p (viewer_subset_editor p h)

-- Sanity: there exists a permission only Admin has.
example : ∃ p : Permission,
    permits .admin p = true ∧ permits .editor p = false := by
  exact ⟨Permission.manage, by simp [permits]⟩

/-
  Counter-example bait — uncomment to see Lean reject it.

  theorem editor_subset_viewer :
      ∀ p : Permission, permits .editor p = true → permits .viewer p = true := by
    intro p h
    cases p <;> simp_all [permits]
    -- the `write` case leaves the goal `False`, derived from
    -- `permits .viewer .write = true` which is `false = true`.
-/
