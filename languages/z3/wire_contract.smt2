; Probe: cross-system wire/bit-layout contract.
;
; Two independently-authored sides must agree on how a logical field is
; packed on the wire. Producer stores a compact form (1 bit per hour,
; H hours). A codec encodes it to a wire array of Q slots per hour
; (finer granularity). Consumer decodes to read a given hour back.
; If the two sides disagree on granularity (Q) or on block order
; (endianness / reversal), some hour decodes to the wrong bit -- a
; classic serialization / enum-layout mismatch bug that unit tests on
; one side never catch.
;
; The producer's bitmap is an *arbitrary* uninterpreted function, so a
; single check quantifies over all possible field contents.
;
; Run:
;   z3 -smt2 languages/z3/wire_contract.smt2
;
; Expected check-sat sequence:
;   unsat -- aligned codec (encode Q=4, decode Q=4) round-trips for every hour
;   sat   -- granularity mismatch (encode Q=4, decode Q=3) misreads some hour
;   sat   -- one-sided block reversal (codec reverses, consumer reads forward)
;
; Data-only: models index arithmetic of the layout, not a real byte buffer.

(set-logic QF_UFLIA)

(define-fun H () Int 6)   ; hours in the schedule
(declare-fun producer (Int) Bool)   ; arbitrary hourly bitmap: producer(hour)

; wire(i) written by the codec = the hour-bit that codec places at slot i.
;   aligned:  wire(i) = producer(i div Qenc)
;   reversed: wire(i) = producer((H-1) - (i div Qenc))
; consumer decodes hour h by reading slot (h * Qdec).

; Contract 1: aligned, Qenc = Qdec = 4, no reversal.
; decode(h) = wire(h*4) = producer((h*4) div 4) = producer(h). Round-trips.
(push)
(declare-const h Int)
(assert (and (>= h 0) (< h H)))
(assert (not (= (producer (div (* h 4) 4)) (producer h))))
(check-sat)
(pop)

; Contract 2 (breaking variant): codec encodes Q=4, consumer decodes Q=3.
; decode(h) reads slot h*3 -> producer((h*3) div 4), which is not producer(h)
; for some hour and some bitmap.
(push)
(declare-const h2 Int)
(assert (and (>= h2 0) (< h2 H)))
(assert (not (= (producer (div (* h2 3) 4)) (producer h2))))
(check-sat)
(pop)

; Contract 3 (breaking variant): codec reverses block order, consumer reads
; forward. decode(h) = wire(h*4) = producer((H-1) - ((h*4) div 4))
;                                = producer((H-1) - h) != producer(h) generally.
(push)
(declare-const h3 Int)
(assert (and (>= h3 0) (< h3 H)))
(assert (not (= (producer (- (- H 1) (div (* h3 4) 4))) (producer h3))))
(check-sat)
(pop)
