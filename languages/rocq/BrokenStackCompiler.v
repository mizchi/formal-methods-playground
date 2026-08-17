(*
  Negative control for StackCompiler.v.

  [compile_broken] emits the right operand before the left operand. Addition
  hides the bug, but subtraction exposes it: 5 - 2 is executed as 2 - 5.
  This file is intentionally rejected by [rocq compile]. scripts/check-rocq.sh treats
  that rejection, including the concrete Some [0] / Some [3] mismatch, as the
  expected result.
*)

From Stdlib Require Import List.
Import ListNotations.
Require Import StackCompiler.

Fixpoint compile_broken (e : expr) : program :=
  match e with
  | Lit value => [Push value]
  | Add lhs rhs => compile_broken rhs ++ compile_broken lhs ++ [AddI]
  | Sub lhs rhs => compile_broken rhs ++ compile_broken lhs ++ [SubI]
  end.

Example broken_subtraction_result :
  exec (compile_broken (Sub (Lit 5) (Lit 2))) [] = Some [0].
Proof.
  reflexivity.
Qed.

Theorem broken_compile_preserves_subtraction :
  exec (compile_broken (Sub (Lit 5) (Lit 2))) [] =
    Some [eval (Sub (Lit 5) (Lit 2))].
Proof.
  cbv.
  reflexivity.
Qed.
