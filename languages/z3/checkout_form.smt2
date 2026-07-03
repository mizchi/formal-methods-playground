; Probe: checkout-form decision function extracted from
; languages/moonbit/checkout_form/checkout_form.mbt.
;
; Run:
;   z3 -smt2 languages/z3/checkout_form.smt2
;
; Expected check-sat sequence:
;   unsat -- unknown kind cannot validate
;   unsat -- digital order with empty email cannot validate
;   sat   -- boundary witness: digital order with email_len = 1 validates
;   sat   -- broken variant admits an invalid digital order
;   sat   -- broken variant differs from the extracted implementation
;
; This is a direct SMT mirror of the implementation-level predicate.
; It is intentionally data-only: no MoonBit runtime, IO, or product
; workflow is part of the model.

(set-logic QF_LIA)

(define-fun physical_kind () Int 0)
(define-fun digital_kind () Int 1)

(define-fun valid_checkout
  ((kind Int) (has_shipping Bool) (email_len Int) (total Int))
  Bool
  (and
    (> total 0)
    (or
      (and (= kind physical_kind) has_shipping)
      (and (= kind digital_kind) (> email_len 0)))))

; Broken variant: the digital branch accidentally forgets the
; non-empty-email guard. The final two checks prove the harness is
; load-bearing: the same queries turn SAT against the broken model.
(define-fun broken_checkout
  ((kind Int) (has_shipping Bool) (email_len Int) (total Int))
  Bool
  (and
    (> total 0)
    (or
      (and (= kind physical_kind) has_shipping)
      (= kind digital_kind))))

(declare-const kind Int)
(declare-const has_shipping Bool)
(declare-const email_len Int)
(declare-const total Int)

; Contract: unknown kinds fail closed.
(push)
(assert (valid_checkout kind has_shipping email_len total))
(assert (not (= kind physical_kind)))
(assert (not (= kind digital_kind)))
(check-sat)
(pop)

; Contract: digital orders require a non-empty email.
(push)
(assert (valid_checkout digital_kind has_shipping email_len total))
(assert (<= email_len 0))
(check-sat)
(pop)

; Sanity witness: the positive boundary is reachable.
(push)
(assert (valid_checkout digital_kind false 1 1))
(check-sat)
(pop)

; Broken-variant witness: this bad digital order should be rejected
; by valid_checkout but accepted by broken_checkout.
(push)
(assert (broken_checkout digital_kind false 0 1))
(check-sat)
(pop)

; Difference query: find any input where the broken predicate and
; extracted predicate disagree.
(push)
(assert (not (= (valid_checkout kind has_shipping email_len total)
                (broken_checkout kind has_shipping email_len total))))
(check-sat)
(pop)
