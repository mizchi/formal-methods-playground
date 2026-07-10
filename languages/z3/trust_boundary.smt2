; Probe: client-identity resolution across a trust boundary.
;
; A common pattern: a request's "client identity" (IP, user id, tenant)
; is resolved by a priority chain over several sources -- some set by
; trusted infrastructure (load balancer, edge), some freely settable by
; the caller (query param, arbitrary header). If a caller-controlled
; source is adopted *without a trust check* and sits high in the chain,
; the identity is spoofable.
;
; Run:
;   z3 -smt2 languages/z3/trust_boundary.smt2
;
; Expected check-sat sequence:
;   sat   -- the caller can force the resolved identity to a value it
;            chose (spoofable) via the unconditional high-priority source
;   sat   -- spoofable regardless of the actual connection peer
;   unsat -- a guarded chain (caller-controlled sources gated on a
;            trusted marker) admits no spoof
;
; Data-only: no HTTP stack, no real network. The model is the resolution
; priority chain and which sources the attacker controls.

(set-logic QF_LIA)

; A "value" is an Int. We track for each candidate source whether it is
; present and whether it is attacker-controlled (a value the caller chose).
; Sources in priority order (first present wins):
;   0: param        -- caller-settable query/body param, adopted unconditionally
;   1: edgeHeader   -- header the edge is supposed to strip; attacker-set if not
;   2: fwdHeader    -- forwarded-for style header (only trusted when peer trusted)
;   3: peer         -- the actual connection peer (LB=trusted, or caller direct)

; sentinel for "attacker-chosen spoof value"
(define-fun EVIL () Int 999)

; --- resolver (current implementation): param is adopted unconditionally ---
;   present flags + values are inputs; peerTrusted says the TCP peer is infra.
(define-fun resolve
  ((paramPresent Bool) (paramVal Int)
   (edgePresent Bool)  (edgeVal Int)
   (fwdPresent Bool)   (fwdVal Int)
   (peerTrusted Bool)  (peerVal Int)
   (fwdTrusted Bool))
  Int
  (ite paramPresent paramVal                       ; unconditional: no trust check
    (ite edgePresent edgeVal                        ; unconditional
      (ite (and fwdPresent peerTrusted fwdTrusted) fwdVal ; only if peer trusted
        peerVal))))

; --- guarded resolver (proposed fix): caller-controlled param/edge are
;     adopted only when a trusted marker (s2s) is present ---
(define-fun resolve_guarded
  ((s2sTrusted Bool)
   (paramPresent Bool) (paramVal Int)
   (edgePresent Bool)  (edgeVal Int)
   (fwdPresent Bool)   (fwdVal Int)
   (peerTrusted Bool)  (peerVal Int)
   (fwdTrusted Bool))
  Int
  (ite (and s2sTrusted paramPresent) paramVal
    (ite (and s2sTrusted edgePresent) edgeVal
      (ite (and fwdPresent peerTrusted fwdTrusted) fwdVal
        peerVal))))

(declare-const peerVal Int)

; Contract violation 1: caller sets param = EVIL and the resolved identity
; becomes EVIL, even though the peer is a trusted LB (normal deployment).
(push)
(assert (= (resolve true EVIL false 0 false 0 true peerVal false) EVIL))
(assert (not (= peerVal EVIL)))   ; EVIL is not the real peer -> genuine spoof
(check-sat)
(pop)

; Contract violation 2: spoofable even when connecting directly
; (peer untrusted) -- param does not depend on the peer at all.
(push)
(assert (= (resolve true EVIL false 0 false 0 false peerVal false) EVIL))
(check-sat)
(pop)

; Guarded chain: with the fix, a caller without the trusted s2s marker
; cannot make the resolved identity be its chosen EVIL value via param/edge.
; (peer is the only remaining source; assume peer is not EVIL.)
(push)
(assert (not (= peerVal EVIL)))
(assert (= (resolve_guarded false true EVIL true EVIL false 0 true peerVal false) EVIL))
(check-sat)
(pop)
