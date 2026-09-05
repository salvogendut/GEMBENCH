; Shared existing deferred-message policy (#73).
; Provider obligations: deferred_contract.inc.
; A=index -> HL=queue record. Queue storage fits one provider-selected byte-index page.
defer_record_ptr
                add   a,a
                add   a,a
                add   a,a
                add   a,CORE_DEFER_QUEUE & #FF
                ld    l,a
                ld    h,(CORE_DEFER_QUEUE & #FF00) / #100
                ret

; Remove compact record C and retain FIFO order. Count is decremented before
; the bounded overlap-safe left shift (at most (capacity-1)*8 bytes).
defer_remove_index
                ld    a,(CORE_DEFER_COUNT)
                dec   a
                ld    (CORE_DEFER_COUNT),a
                sub   c                             ; records after the removed one
                ret   z
                ld    b,a
                ld    a,c
                call  defer_record_ptr
                push  hl                            ; destination
                ld    de,GB_DEFER_RECORD_SIZE
                add   hl,de                         ; source
                pop   de
                ld    a,b
                add   a,a
                add   a,a
                add   a,a
                ld    c,a
                ld    b,0
                ldir
                ret
