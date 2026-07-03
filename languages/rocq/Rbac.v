(*
  Probe: RBAC role-hierarchy monotonicity in Rocq.

  Run:
    coqc languages/rocq/Rbac.v

  This mirrors the Lean RBAC probe at a small scale. The point is
  not to prefer Rocq for this example, but to keep the Rocq toolchain
  exercised in CI and leave a slot for future Iris / CompCert style
  examples.
*)

Inductive role : Type :=
| viewer
| editor
| admin.

Inductive permission : Type :=
| read
| write
| manage.

Definition permits (r : role) (p : permission) : bool :=
  match r, p with
  | viewer, read => true
  | editor, read => true
  | editor, write => true
  | admin, _ => true
  | _, _ => false
  end.

Theorem viewer_subset_editor :
  forall p, permits viewer p = true -> permits editor p = true.
Proof.
  intros p H.
  destruct p; simpl in *; try discriminate; reflexivity.
Qed.

Theorem editor_subset_admin :
  forall p, permits editor p = true -> permits admin p = true.
Proof.
  intros p H.
  destruct p; simpl in *; reflexivity.
Qed.

Theorem viewer_subset_admin :
  forall p, permits viewer p = true -> permits admin p = true.
Proof.
  intros p H.
  apply editor_subset_admin.
  apply viewer_subset_editor.
  exact H.
Qed.
