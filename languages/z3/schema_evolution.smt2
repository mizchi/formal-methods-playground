; Probe: is this schema change safe to deploy?
;
; Domain: a rolling deploy (or a Kafka/outbox topic, or a persisted event log).
; For the length of the deploy window BOTH versions run at once, so every
; message crosses the version boundary in BOTH directions:
;
;   v1 pod writes  ->  v2 pod reads     (backward compatibility)
;   v2 pod writes  ->  v1 pod reads     (forward  compatibility)
;
; A change is deployable only if both directions hold. The change under test
; is the one every team ships eventually:
;
;   * `status` gains a new variant `refunded` (v1 knows 0,1,2; v2 adds 3)
;   * `currency` goes from optional to required
;
; Record shape (flattened, one integer + one presence flag):
;   status       0=pending 1=paid 2=cancelled 3=refunded
;   hasCurrency  was the field present on the wire?
;
; Run:
;   z3 -smt2 languages/z3/schema_evolution.smt2
;
; Expected check-sat sequence:
;   sat   -- backward break: a v1 record with no currency; the strict v2
;            reader requires it, so old rows fail to parse after deploy
;   sat   -- forward break: a v2 record with status=refunded; the strict v1
;            reader rejects the unknown variant and the message dead-letters
;   unsat -- tolerant v2 reader (default the missing currency) accepts every
;            v1 record
;   unsat -- tolerant v1 reader (unknown variant -> a catch-all) accepts every
;            v2 record
;   sat   -- parsing is not semantics: a v1 reader that maps unknown -> pending
;            will re-capture a refunded order
;   unsat -- a v1 reader that maps unknown -> a non-actionable hold cannot
;            act on any status it does not understand
;
; Data-only: this models what each side accepts and acts on, not a codec.
; The claim it locks is a property of the compatibility rules, so it belongs
; in the PR that changes the schema, not in a post-deploy incident review.

(set-logic QF_LIA)

(define-fun PENDING   () Int 0)
(define-fun PAID      () Int 1)
(define-fun CANCELLED () Int 2)
(define-fun REFUNDED  () Int 3)

; --- what each version can put on the wire ------------------------------
(define-fun v1-writes ((status Int) (hasCurrency Bool)) Bool
  (and (>= status PENDING) (<= status CANCELLED)))          ; currency optional

(define-fun v2-writes ((status Int) (hasCurrency Bool)) Bool
  (and (>= status PENDING) (<= status REFUNDED) hasCurrency)); currency required

; --- what each version accepts ------------------------------------------
(define-fun v1-reads-strict ((status Int) (hasCurrency Bool)) Bool
  (and (>= status PENDING) (<= status CANCELLED)))

(define-fun v2-reads-strict ((status Int) (hasCurrency Bool)) Bool
  (and (>= status PENDING) (<= status REFUNDED) hasCurrency))

; Tolerant readers: the expand/contract discipline.
(define-fun v2-reads-tolerant ((status Int) (hasCurrency Bool)) Bool
  (and (>= status PENDING) (<= status REFUNDED)))           ; default the currency

(define-fun v1-reads-tolerant ((status Int) (hasCurrency Bool)) Bool
  (>= status PENDING))                                      ; unknown -> catch-all

; --- what a v1 reader DOES with what it parsed --------------------------
; v1 captures payment for anything it believes is still pending.
(define-fun v1-status-fallback-pending ((status Int)) Int
  (ite (<= status CANCELLED) status PENDING))               ; fail-open fallback

(define-fun v1-status-fallback-hold ((status Int)) Int
  (ite (<= status CANCELLED) status 99))                    ; fail-closed fallback

(define-fun v1-captures ((mapped Int)) Bool (= mapped PENDING))


; 1. backward: strict v2 reader vs a v1 record  -> expect sat (currency absent)
(push)
(declare-const status Int)
(declare-const hasCurrency Bool)
(assert (v1-writes status hasCurrency))
(assert (not (v2-reads-strict status hasCurrency)))
(check-sat)
(pop)

; 2. forward: strict v1 reader vs a v2 record   -> expect sat (status=refunded)
(push)
(declare-const status Int)
(declare-const hasCurrency Bool)
(assert (v2-writes status hasCurrency))
(assert (not (v1-reads-strict status hasCurrency)))
(check-sat)
(pop)

; 3. backward, fixed: tolerant v2 reader accepts every v1 record -> expect unsat
(push)
(declare-const status Int)
(declare-const hasCurrency Bool)
(assert (v1-writes status hasCurrency))
(assert (not (v2-reads-tolerant status hasCurrency)))
(check-sat)
(pop)

; 4. forward, fixed: tolerant v1 reader accepts every v2 record -> expect unsat
(push)
(declare-const status Int)
(declare-const hasCurrency Bool)
(assert (v2-writes status hasCurrency))
(assert (not (v1-reads-tolerant status hasCurrency)))
(check-sat)
(pop)

; 5. accepting is not understanding: with a fail-open fallback the v1 reader
;    parses a refunded order and then captures it -> expect sat
(push)
(declare-const status Int)
(declare-const hasCurrency Bool)
(assert (v2-writes status hasCurrency))
(assert (= status REFUNDED))
(assert (v1-reads-tolerant status hasCurrency))
(assert (v1-captures (v1-status-fallback-pending status)))
(check-sat)
(pop)

; 6. fail-closed fallback: no status v1 does not understand can be acted on,
;    for any record v2 can write -> expect unsat
(push)
(declare-const status Int)
(declare-const hasCurrency Bool)
(assert (v2-writes status hasCurrency))
(assert (not (= status PENDING)))
(assert (v1-captures (v1-status-fallback-hold status)))
(check-sat)
(pop)
