; Campaign targeting: does the live config target anyone the docs say it should?
;
; Docs (trusted):
;   SummerPromo targets JP users aged 20-29.
;   Denylisted users never see it.
;   A missing or malformed country fails closed.
;   Empty allowlist: not documented.
;
; Live config (observed):
;   include.country = [JP], include.age = { gte: 30, lt: 30 }
;   exclude.country = [JP], allowlist = []
;
; Only the sat/unsat lines are compared by check.sh; get-value prints the
; witness for a human, and its concrete numbers may differ between Z3 versions.

(declare-datatypes () ((Country JP US Invalid)))
(declare-const country Country)
(declare-const age Int)
(declare-const denylisted Bool)
(declare-const allowlisted Bool)
(declare-const allowlist-size Int)
(assert (and (>= age 0) (<= age 150)))
(assert (>= allowlist-size 0))
; A user can only be on a non-empty list.
(assert (=> allowlisted (> allowlist-size 0)))
; The live config ships allowlist = [].
(assert (= allowlist-size 0))

; The evaluator reads a rule as: include AND NOT exclude AND NOT denylisted AND allowlist.
; repro/targeting.js reads allowlist = [] as "no restriction".
(define-fun allowlist-ok-empty-is-open () Bool (or (= allowlist-size 0) allowlisted))
(define-fun allowlist-ok-empty-is-closed () Bool allowlisted)

(define-fun live-include () Bool (and (= country JP) (>= age 30) (< age 30)))
(define-fun live-exclude () Bool (= country JP))
(define-fun live-match () Bool
  (and live-include (not live-exclude) (not denylisted) allowlist-ok-empty-is-open))

(define-fun doc-match () Bool
  (and (= country JP) (>= age 20) (< age 30) (not denylisted) allowlist-ok-empty-is-open))

; 1. Dead config: can the live config match anyone at all?          expect unsat
(push)
(assert live-match)
(check-sat)
(pop)

; 2. The age range alone is already empty (gte 30, lt 30).            expect unsat
(push)
(assert (and (>= age 30) (< age 30)))
(check-sat)
(pop)

; 3. Even with the documented age range, exclude JP cancels include JP. expect unsat
(push)
(assert (and (= country JP) (>= age 20) (< age 30) (not live-exclude)))
(check-sat)
(pop)

; 4. Sanity: the documented rule does target someone.                  expect sat
(push)
(assert doc-match)
(check-sat)
(get-value (country age denylisted))
(pop)

; 5. The documented rule never targets a denylisted user.              expect unsat
(push)
(assert (and doc-match denylisted))
(check-sat)
(pop)

; 6. Fail-close: a malformed country never matches.                    expect unsat
(push)
(assert (and doc-match (= country Invalid)))
(check-sat)
(pop)

; 7. Domain question, reading 1: empty allowlist = "no restriction".
;    The documented rule still targets someone.                        expect sat
(push)
(assert (and (= country JP) (>= age 20) (< age 30) (not denylisted)
             allowlist-ok-empty-is-open))
(check-sat)
(pop)

; 8. Domain question, reading 2: empty allowlist = "nobody".
;    The documented rule is dead as well.                              expect unsat
(push)
(assert (and (= country JP) (>= age 20) (< age 30) (not denylisted)
             allowlist-ok-empty-is-closed))
(check-sat)
(pop)

; 9. Fail-close for an exclude-only rule ("everyone except JP").
;    A malformed country is in no list, so exclude does not drop it.    expect sat
;    Check 6 only held because include.country already required JP.
(push)
(assert (and (not (= country JP)) (not denylisted) allowlist-ok-empty-is-open
             (= country Invalid)))
(check-sat)
(get-value (country))
(pop)
