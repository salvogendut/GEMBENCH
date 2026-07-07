; ---------------------------------------------------------------------------
; lib/pcw/bank.asm - slot-1 block paging for the PCW target (#331).
;
; The PCW counterpart of lib/bank.asm. A "page value" is a PCW bank register
; byte: #80 | physical block (bit 7 = extended mode, low 7 bits = 16K block).
; Switching is a single OUT to port #F1 (CPU slot 1, #4000-#7FFF).
;
; Same interface + shadow discipline as the CPC pager: bank_set (A = page
; value), bank_normal (identity block 1 - the roller table lives in its first
; 512 bytes, so nothing else uses it), bank_cur shadow at BANK_CUR.
;
; CRITICAL (same as CPC/MSX): callers + stack must live outside #4000-#7FFF.
; ---------------------------------------------------------------------------

; (bank_cur resolves to lowram.inc's BANK_CUR - RASM symbols are case-insensitive)

; bank_set: A = page value -> map it at #4000-#7FFF and record it.
; (Clobbers nothing but the shadow - cheaper than the CPC contract.)
bank_set
                ld    (bank_cur),a
                out   (PCW_BANK1),a
                ret

; bank_normal: back to the identity mapping (phys block 1).
bank_normal
                ld    a,#81
                jr    bank_set
