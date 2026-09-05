; Shared existing deferred-message policy (#73).
; Provider obligations: deferred_contract.inc.
; Called exactly once per WM root-loop turn. The queue head is copied and
; removed before validation/callback, so handlers may enqueue replies without
; nesting delivery or corrupting the stable current record.
defer_dispatch_one
                ld    a,(CORE_DEFER_BUSY)
                or    a
                ret   nz
                ld    a,(CORE_DEFER_COUNT)
                or    a
                ret   z
                ld    hl,CORE_DEFER_QUEUE
                ld    de,CORE_DEFER_CURRENT
                ld    bc,GB_DEFER_RECORD_SIZE
                ldir
                ld    c,0
                call  defer_remove_index
                ld    de,(CORE_DEFER_CURRENT+2)
                call  DEFER_VALIDATE_OWNER
                ret   nc                            ; stale receiver: deterministic drop
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,CORE_APP_FLAGS
                add   a,l
                ld    l,a
                bit   CORE_APP_TERMINATING_BIT,(hl)
                ret   nz                            ; terminating endpoints never run
                ld    hl,CORE_DEFER_HANDLER_LO
                ld    a,c
                add   a,l
                ld    l,a
                ld    e,(hl)
                ld    hl,CORE_DEFER_HANDLER_HI
                ld    a,c
                add   a,l
                ld    l,a
                ld    d,(hl)
                ld    a,d
                or    e
                ret   z
                ex    de,hl                         ; HL=handler
                ld    a,c
                ld    de,CORE_APP_CODE_NATIVE
                add   a,e
                ld    e,a
                ld    a,(de)
                or    a
                ret   z
                ld    c,a                           ; target native code-bank tag
                ld    a,(CORE_DEFER_CURRENT+2)      ; precompute receiver's primary window
                dec   a
                ld    de,CORE_APP_PRIMARY_WIN
                add   a,e
                ld    e,a
                ld    a,(de)
                ld    (CORE_DEFER_ACTIVATE),a
                ld    a,1
                ld    (CORE_DEFER_BUSY),a
                ld    a,(CORE_MAPPED_NATIVE)
                push  af
                ld    a,c
                call  DEFER_SET_BANK                ; preserves HL=handler
                ld    a,CORE_DEFER_EVENT
                ld    (CORE_MESSAGE),a
                ld    a,(CORE_DEFER_CURRENT+4)
                ld    (CORE_MESSAGE+1),a
                ld    a,(CORE_DEFER_CURRENT+5)
                ld    (CORE_MESSAGE+2),a
                xor   a                             ; handler response: nonzero requests activation
                ld    (CORE_MESSAGE+3),a
                call  DEFER_CALL
                pop   af
                call  DEFER_SET_BANK
                xor   a
                ld    (CORE_DEFER_BUSY),a
                ld    a,(CORE_MESSAGE+3)
                or    a
                ret   z
                ld    a,(CORE_DEFER_ACTIVATE)
                cp    #FF
                ret   z
                ld    c,a
                DEFER_ACTIVATE_WINDOW
