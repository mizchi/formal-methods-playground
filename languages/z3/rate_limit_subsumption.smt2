; Probe: redundant (subsumed) rate limits.
;
; A resource may carry several rate limits, all enforced (AND): "at most
; cap_i events per period_i". If one limit is *subsumed* by another, it is
; dead configuration -- present in the config, but it never changes any
; decision. Operators then believe a cap is active when it is not.
;
; a=(cap_a,period_a) subsumes b=(cap_b,period_b)  <=>  no event sequence
; satisfies a while violating b. We refute subsumption by searching for a
; witness sequence: cap_b+1 events inside one period_b window (violates b)
; such that every period_a window holds <= cap_a events (satisfies a).
;   unsat -> no witness -> a subsumes b -> b is redundant
;   sat   -> witness exists -> both limits are independently effective
;
; Run:
;   z3 -smt2 languages/z3/rate_limit_subsumption.smt2
;
; Expected check-sat sequence:
;   unsat -- 1/3600s subsumes 10/3600s (tighter same-window limit dominates)
;   unsat -- 2/10s subsumes 5/10s
;   sat   -- 10/3600s and 2/10s are independent (witness: 3 events in 10s, <=10/h)
;
; Data-only: models event timestamps in integer seconds. No clock, no store.

(set-logic QF_LIA)


; 1 per 3600s subsumes 10 per 3600s -> the 10/h limit is redundant
(push)
(declare-const t0 Int)
(declare-const t1 Int)
(declare-const t2 Int)
(declare-const t3 Int)
(declare-const t4 Int)
(declare-const t5 Int)
(declare-const t6 Int)
(declare-const t7 Int)
(declare-const t8 Int)
(declare-const t9 Int)
(declare-const t10 Int)
(assert (= t0 0))
(assert (> t1 t0))
(assert (> t2 t1))
(assert (> t3 t2))
(assert (> t4 t3))
(assert (> t5 t4))
(assert (> t6 t5))
(assert (> t7 t6))
(assert (> t8 t7))
(assert (> t9 t8))
(assert (> t10 t9))
(assert (<= (- t10 t0) 3600))
(assert (<= (+ (ite (and (>= t0 t0) (<= t0 (+ t0 3600))) 1 0) (ite (and (>= t1 t0) (<= t1 (+ t0 3600))) 1 0) (ite (and (>= t2 t0) (<= t2 (+ t0 3600))) 1 0) (ite (and (>= t3 t0) (<= t3 (+ t0 3600))) 1 0) (ite (and (>= t4 t0) (<= t4 (+ t0 3600))) 1 0) (ite (and (>= t5 t0) (<= t5 (+ t0 3600))) 1 0) (ite (and (>= t6 t0) (<= t6 (+ t0 3600))) 1 0) (ite (and (>= t7 t0) (<= t7 (+ t0 3600))) 1 0) (ite (and (>= t8 t0) (<= t8 (+ t0 3600))) 1 0) (ite (and (>= t9 t0) (<= t9 (+ t0 3600))) 1 0) (ite (and (>= t10 t0) (<= t10 (+ t0 3600))) 1 0)) 1))
(assert (<= (+ (ite (and (>= t0 t1) (<= t0 (+ t1 3600))) 1 0) (ite (and (>= t1 t1) (<= t1 (+ t1 3600))) 1 0) (ite (and (>= t2 t1) (<= t2 (+ t1 3600))) 1 0) (ite (and (>= t3 t1) (<= t3 (+ t1 3600))) 1 0) (ite (and (>= t4 t1) (<= t4 (+ t1 3600))) 1 0) (ite (and (>= t5 t1) (<= t5 (+ t1 3600))) 1 0) (ite (and (>= t6 t1) (<= t6 (+ t1 3600))) 1 0) (ite (and (>= t7 t1) (<= t7 (+ t1 3600))) 1 0) (ite (and (>= t8 t1) (<= t8 (+ t1 3600))) 1 0) (ite (and (>= t9 t1) (<= t9 (+ t1 3600))) 1 0) (ite (and (>= t10 t1) (<= t10 (+ t1 3600))) 1 0)) 1))
(assert (<= (+ (ite (and (>= t0 t2) (<= t0 (+ t2 3600))) 1 0) (ite (and (>= t1 t2) (<= t1 (+ t2 3600))) 1 0) (ite (and (>= t2 t2) (<= t2 (+ t2 3600))) 1 0) (ite (and (>= t3 t2) (<= t3 (+ t2 3600))) 1 0) (ite (and (>= t4 t2) (<= t4 (+ t2 3600))) 1 0) (ite (and (>= t5 t2) (<= t5 (+ t2 3600))) 1 0) (ite (and (>= t6 t2) (<= t6 (+ t2 3600))) 1 0) (ite (and (>= t7 t2) (<= t7 (+ t2 3600))) 1 0) (ite (and (>= t8 t2) (<= t8 (+ t2 3600))) 1 0) (ite (and (>= t9 t2) (<= t9 (+ t2 3600))) 1 0) (ite (and (>= t10 t2) (<= t10 (+ t2 3600))) 1 0)) 1))
(assert (<= (+ (ite (and (>= t0 t3) (<= t0 (+ t3 3600))) 1 0) (ite (and (>= t1 t3) (<= t1 (+ t3 3600))) 1 0) (ite (and (>= t2 t3) (<= t2 (+ t3 3600))) 1 0) (ite (and (>= t3 t3) (<= t3 (+ t3 3600))) 1 0) (ite (and (>= t4 t3) (<= t4 (+ t3 3600))) 1 0) (ite (and (>= t5 t3) (<= t5 (+ t3 3600))) 1 0) (ite (and (>= t6 t3) (<= t6 (+ t3 3600))) 1 0) (ite (and (>= t7 t3) (<= t7 (+ t3 3600))) 1 0) (ite (and (>= t8 t3) (<= t8 (+ t3 3600))) 1 0) (ite (and (>= t9 t3) (<= t9 (+ t3 3600))) 1 0) (ite (and (>= t10 t3) (<= t10 (+ t3 3600))) 1 0)) 1))
(assert (<= (+ (ite (and (>= t0 t4) (<= t0 (+ t4 3600))) 1 0) (ite (and (>= t1 t4) (<= t1 (+ t4 3600))) 1 0) (ite (and (>= t2 t4) (<= t2 (+ t4 3600))) 1 0) (ite (and (>= t3 t4) (<= t3 (+ t4 3600))) 1 0) (ite (and (>= t4 t4) (<= t4 (+ t4 3600))) 1 0) (ite (and (>= t5 t4) (<= t5 (+ t4 3600))) 1 0) (ite (and (>= t6 t4) (<= t6 (+ t4 3600))) 1 0) (ite (and (>= t7 t4) (<= t7 (+ t4 3600))) 1 0) (ite (and (>= t8 t4) (<= t8 (+ t4 3600))) 1 0) (ite (and (>= t9 t4) (<= t9 (+ t4 3600))) 1 0) (ite (and (>= t10 t4) (<= t10 (+ t4 3600))) 1 0)) 1))
(assert (<= (+ (ite (and (>= t0 t5) (<= t0 (+ t5 3600))) 1 0) (ite (and (>= t1 t5) (<= t1 (+ t5 3600))) 1 0) (ite (and (>= t2 t5) (<= t2 (+ t5 3600))) 1 0) (ite (and (>= t3 t5) (<= t3 (+ t5 3600))) 1 0) (ite (and (>= t4 t5) (<= t4 (+ t5 3600))) 1 0) (ite (and (>= t5 t5) (<= t5 (+ t5 3600))) 1 0) (ite (and (>= t6 t5) (<= t6 (+ t5 3600))) 1 0) (ite (and (>= t7 t5) (<= t7 (+ t5 3600))) 1 0) (ite (and (>= t8 t5) (<= t8 (+ t5 3600))) 1 0) (ite (and (>= t9 t5) (<= t9 (+ t5 3600))) 1 0) (ite (and (>= t10 t5) (<= t10 (+ t5 3600))) 1 0)) 1))
(assert (<= (+ (ite (and (>= t0 t6) (<= t0 (+ t6 3600))) 1 0) (ite (and (>= t1 t6) (<= t1 (+ t6 3600))) 1 0) (ite (and (>= t2 t6) (<= t2 (+ t6 3600))) 1 0) (ite (and (>= t3 t6) (<= t3 (+ t6 3600))) 1 0) (ite (and (>= t4 t6) (<= t4 (+ t6 3600))) 1 0) (ite (and (>= t5 t6) (<= t5 (+ t6 3600))) 1 0) (ite (and (>= t6 t6) (<= t6 (+ t6 3600))) 1 0) (ite (and (>= t7 t6) (<= t7 (+ t6 3600))) 1 0) (ite (and (>= t8 t6) (<= t8 (+ t6 3600))) 1 0) (ite (and (>= t9 t6) (<= t9 (+ t6 3600))) 1 0) (ite (and (>= t10 t6) (<= t10 (+ t6 3600))) 1 0)) 1))
(assert (<= (+ (ite (and (>= t0 t7) (<= t0 (+ t7 3600))) 1 0) (ite (and (>= t1 t7) (<= t1 (+ t7 3600))) 1 0) (ite (and (>= t2 t7) (<= t2 (+ t7 3600))) 1 0) (ite (and (>= t3 t7) (<= t3 (+ t7 3600))) 1 0) (ite (and (>= t4 t7) (<= t4 (+ t7 3600))) 1 0) (ite (and (>= t5 t7) (<= t5 (+ t7 3600))) 1 0) (ite (and (>= t6 t7) (<= t6 (+ t7 3600))) 1 0) (ite (and (>= t7 t7) (<= t7 (+ t7 3600))) 1 0) (ite (and (>= t8 t7) (<= t8 (+ t7 3600))) 1 0) (ite (and (>= t9 t7) (<= t9 (+ t7 3600))) 1 0) (ite (and (>= t10 t7) (<= t10 (+ t7 3600))) 1 0)) 1))
(assert (<= (+ (ite (and (>= t0 t8) (<= t0 (+ t8 3600))) 1 0) (ite (and (>= t1 t8) (<= t1 (+ t8 3600))) 1 0) (ite (and (>= t2 t8) (<= t2 (+ t8 3600))) 1 0) (ite (and (>= t3 t8) (<= t3 (+ t8 3600))) 1 0) (ite (and (>= t4 t8) (<= t4 (+ t8 3600))) 1 0) (ite (and (>= t5 t8) (<= t5 (+ t8 3600))) 1 0) (ite (and (>= t6 t8) (<= t6 (+ t8 3600))) 1 0) (ite (and (>= t7 t8) (<= t7 (+ t8 3600))) 1 0) (ite (and (>= t8 t8) (<= t8 (+ t8 3600))) 1 0) (ite (and (>= t9 t8) (<= t9 (+ t8 3600))) 1 0) (ite (and (>= t10 t8) (<= t10 (+ t8 3600))) 1 0)) 1))
(assert (<= (+ (ite (and (>= t0 t9) (<= t0 (+ t9 3600))) 1 0) (ite (and (>= t1 t9) (<= t1 (+ t9 3600))) 1 0) (ite (and (>= t2 t9) (<= t2 (+ t9 3600))) 1 0) (ite (and (>= t3 t9) (<= t3 (+ t9 3600))) 1 0) (ite (and (>= t4 t9) (<= t4 (+ t9 3600))) 1 0) (ite (and (>= t5 t9) (<= t5 (+ t9 3600))) 1 0) (ite (and (>= t6 t9) (<= t6 (+ t9 3600))) 1 0) (ite (and (>= t7 t9) (<= t7 (+ t9 3600))) 1 0) (ite (and (>= t8 t9) (<= t8 (+ t9 3600))) 1 0) (ite (and (>= t9 t9) (<= t9 (+ t9 3600))) 1 0) (ite (and (>= t10 t9) (<= t10 (+ t9 3600))) 1 0)) 1))
(assert (<= (+ (ite (and (>= t0 t10) (<= t0 (+ t10 3600))) 1 0) (ite (and (>= t1 t10) (<= t1 (+ t10 3600))) 1 0) (ite (and (>= t2 t10) (<= t2 (+ t10 3600))) 1 0) (ite (and (>= t3 t10) (<= t3 (+ t10 3600))) 1 0) (ite (and (>= t4 t10) (<= t4 (+ t10 3600))) 1 0) (ite (and (>= t5 t10) (<= t5 (+ t10 3600))) 1 0) (ite (and (>= t6 t10) (<= t6 (+ t10 3600))) 1 0) (ite (and (>= t7 t10) (<= t7 (+ t10 3600))) 1 0) (ite (and (>= t8 t10) (<= t8 (+ t10 3600))) 1 0) (ite (and (>= t9 t10) (<= t9 (+ t10 3600))) 1 0) (ite (and (>= t10 t10) (<= t10 (+ t10 3600))) 1 0)) 1))
(check-sat)
(pop)

; 2 per 10s subsumes 5 per 10s
(push)
(declare-const t0 Int)
(declare-const t1 Int)
(declare-const t2 Int)
(declare-const t3 Int)
(declare-const t4 Int)
(declare-const t5 Int)
(assert (= t0 0))
(assert (> t1 t0))
(assert (> t2 t1))
(assert (> t3 t2))
(assert (> t4 t3))
(assert (> t5 t4))
(assert (<= (- t5 t0) 10))
(assert (<= (+ (ite (and (>= t0 t0) (<= t0 (+ t0 10))) 1 0) (ite (and (>= t1 t0) (<= t1 (+ t0 10))) 1 0) (ite (and (>= t2 t0) (<= t2 (+ t0 10))) 1 0) (ite (and (>= t3 t0) (<= t3 (+ t0 10))) 1 0) (ite (and (>= t4 t0) (<= t4 (+ t0 10))) 1 0) (ite (and (>= t5 t0) (<= t5 (+ t0 10))) 1 0)) 2))
(assert (<= (+ (ite (and (>= t0 t1) (<= t0 (+ t1 10))) 1 0) (ite (and (>= t1 t1) (<= t1 (+ t1 10))) 1 0) (ite (and (>= t2 t1) (<= t2 (+ t1 10))) 1 0) (ite (and (>= t3 t1) (<= t3 (+ t1 10))) 1 0) (ite (and (>= t4 t1) (<= t4 (+ t1 10))) 1 0) (ite (and (>= t5 t1) (<= t5 (+ t1 10))) 1 0)) 2))
(assert (<= (+ (ite (and (>= t0 t2) (<= t0 (+ t2 10))) 1 0) (ite (and (>= t1 t2) (<= t1 (+ t2 10))) 1 0) (ite (and (>= t2 t2) (<= t2 (+ t2 10))) 1 0) (ite (and (>= t3 t2) (<= t3 (+ t2 10))) 1 0) (ite (and (>= t4 t2) (<= t4 (+ t2 10))) 1 0) (ite (and (>= t5 t2) (<= t5 (+ t2 10))) 1 0)) 2))
(assert (<= (+ (ite (and (>= t0 t3) (<= t0 (+ t3 10))) 1 0) (ite (and (>= t1 t3) (<= t1 (+ t3 10))) 1 0) (ite (and (>= t2 t3) (<= t2 (+ t3 10))) 1 0) (ite (and (>= t3 t3) (<= t3 (+ t3 10))) 1 0) (ite (and (>= t4 t3) (<= t4 (+ t3 10))) 1 0) (ite (and (>= t5 t3) (<= t5 (+ t3 10))) 1 0)) 2))
(assert (<= (+ (ite (and (>= t0 t4) (<= t0 (+ t4 10))) 1 0) (ite (and (>= t1 t4) (<= t1 (+ t4 10))) 1 0) (ite (and (>= t2 t4) (<= t2 (+ t4 10))) 1 0) (ite (and (>= t3 t4) (<= t3 (+ t4 10))) 1 0) (ite (and (>= t4 t4) (<= t4 (+ t4 10))) 1 0) (ite (and (>= t5 t4) (<= t5 (+ t4 10))) 1 0)) 2))
(assert (<= (+ (ite (and (>= t0 t5) (<= t0 (+ t5 10))) 1 0) (ite (and (>= t1 t5) (<= t1 (+ t5 10))) 1 0) (ite (and (>= t2 t5) (<= t2 (+ t5 10))) 1 0) (ite (and (>= t3 t5) (<= t3 (+ t5 10))) 1 0) (ite (and (>= t4 t5) (<= t4 (+ t5 10))) 1 0) (ite (and (>= t5 t5) (<= t5 (+ t5 10))) 1 0)) 2))
(check-sat)
(pop)

; 10 per 3600s vs 2 per 10s are independent (both effective)
(push)
(declare-const t0 Int)
(declare-const t1 Int)
(declare-const t2 Int)
(assert (= t0 0))
(assert (> t1 t0))
(assert (> t2 t1))
(assert (<= (- t2 t0) 10))
(assert (<= (+ (ite (and (>= t0 t0) (<= t0 (+ t0 3600))) 1 0) (ite (and (>= t1 t0) (<= t1 (+ t0 3600))) 1 0) (ite (and (>= t2 t0) (<= t2 (+ t0 3600))) 1 0)) 10))
(assert (<= (+ (ite (and (>= t0 t1) (<= t0 (+ t1 3600))) 1 0) (ite (and (>= t1 t1) (<= t1 (+ t1 3600))) 1 0) (ite (and (>= t2 t1) (<= t2 (+ t1 3600))) 1 0)) 10))
(assert (<= (+ (ite (and (>= t0 t2) (<= t0 (+ t2 3600))) 1 0) (ite (and (>= t1 t2) (<= t1 (+ t2 3600))) 1 0) (ite (and (>= t2 t2) (<= t2 (+ t2 3600))) 1 0)) 10))
(check-sat)
(pop)
