(*
  Use case: compiler-correctness proof in Rocq.

  The source language contains natural-number literals, addition, and
  subtraction. [compile] targets a stack machine. [compile_correct] proves
  that, for every expression and every initial stack, executing the compiled
  code produces exactly the source-language result without underflow.

  Run through the repository guard:
    just check-rocq

  The negative control in [BrokenStackCompiler.v] reverses the operands of
  subtraction. It turns 5 - 2 into 2 - 5 = 0; the same correctness claim must
  then fail under [rocq compile].
*)

From Stdlib Require Import List.
Import ListNotations.

Inductive expr : Type :=
| Lit (value : nat)
| Add (lhs rhs : expr)
| Sub (lhs rhs : expr).

Fixpoint eval (e : expr) : nat :=
  match e with
  | Lit value => value
  | Add lhs rhs => eval lhs + eval rhs
  | Sub lhs rhs => eval lhs - eval rhs
  end.

Inductive instr : Type :=
| Push (value : nat)
| AddI
| SubI.

Definition stack := list nat.
Definition program := list instr.

Definition step (instruction : instr) (s : stack) : option stack :=
  match instruction, s with
  | Push value, _ => Some (value :: s)
  | AddI, rhs :: lhs :: rest => Some ((lhs + rhs) :: rest)
  | SubI, rhs :: lhs :: rest => Some ((lhs - rhs) :: rest)
  | _, _ => None
  end.

Fixpoint exec (code : program) (s : stack) : option stack :=
  match code with
  | [] => Some s
  | instruction :: rest =>
      match step instruction s with
      | Some s' => exec rest s'
      | None => None
      end
  end.

Fixpoint compile (e : expr) : program :=
  match e with
  | Lit value => [Push value]
  | Add lhs rhs => compile lhs ++ compile rhs ++ [AddI]
  | Sub lhs rhs => compile lhs ++ compile rhs ++ [SubI]
  end.

Lemma exec_append :
  forall first second s,
    exec (first ++ second) s =
      match exec first s with
      | Some s' => exec second s'
      | None => None
      end.
Proof.
  induction first as [| instruction rest IH]; intros second s.
  - reflexivity.
  - simpl.
    destruct (step instruction s) as [s'|] eqn:Hstep.
    + apply IH.
    + reflexivity.
Qed.

Theorem compile_correct :
  forall e s,
    exec (compile e) s = Some (eval e :: s).
Proof.
  induction e as [value | lhs IHlhs rhs IHrhs | lhs IHlhs rhs IHrhs];
    intros s; simpl.
  - reflexivity.
  - rewrite exec_append, IHlhs; simpl.
    rewrite exec_append, IHrhs.
    reflexivity.
  - rewrite exec_append, IHlhs; simpl.
    rewrite exec_append, IHrhs.
    reflexivity.
Qed.

Example subtraction_example :
  exec (compile (Sub (Lit 5) (Lit 2))) [] = Some [3].
Proof.
  reflexivity.
Qed.
