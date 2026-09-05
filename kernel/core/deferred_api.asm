; Shared existing deferred-message policy (#73).
; Provider obligations: deferred_contract.inc.
; GB_DEFER #80CF (Architecture Milestone 3): bounded asynchronous application
; messages. Operations retain the existing append-only ABI:
;   A=0, HL=handler       register/unregister the current application endpoint
;   A=1, HL=send record   enqueue receiver,type,p0,p1,p2 (sender is implicit)
;   A=2                   DE=current eight-byte delivery record, or zero
;   A=3                   A=free queue records
;   A=4, B=service class  DE=topmost matching application owner, or zero
;   A=5, C=accessory ID   DE=matching accessory application owner, or zero
;   A=6                   cancel all messages queued by the current application
k_defer
                or    a
                jp    z,kdefer_register
                dec   a
                jp    z,kdefer_send
                dec   a
                jp    z,kdefer_current
                dec   a
                jp    z,kdefer_free
                dec   a
                jp    z,kdefer_find_service
                dec   a
                jp    z,kdefer_find_accessory
                dec   a
                jp    z,kdefer_cancel_all
kdefer_bad     ld    a,GB_DEFER_ERR_BADARG
                ret

kdefer_register
                DEFER_REQUIRE_ROOT
                ld    (CORE_DEFER_SEND+4),hl
                call  DEFER_CURRENT_OWNER
                call  DEFER_VALIDATE_OWNER
                jp    nc,kdefer_context
                ld    (CORE_DEFER_SEND),de
                ld    hl,(CORE_DEFER_SEND+4)
                ld    a,h
                or    l
                jr    z,kdr_unregister
                DEFER_CHECK_CALLBACK
kdr_store      ld    a,e
                dec   a
                ld    c,a
                ld    hl,CORE_DEFER_HANDLER_LO
                add   a,l
                ld    l,a
                ld    a,(CORE_DEFER_SEND+4)
                ld    (hl),a
                ld    hl,CORE_DEFER_HANDLER_HI
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(CORE_DEFER_SEND+5)
                ld    (hl),a
                xor   a
                ret
kdr_unregister ld    de,(CORE_DEFER_SEND)
                call  defer_purge_owner             ; cancel both directions before unpublishing
                xor   a
                ld    (CORE_DEFER_SEND+4),a
                ld    (CORE_DEFER_SEND+5),a
                ld    de,(CORE_DEFER_SEND)
                jr    kdr_store

; Validate the caller-page six-byte record before copying it. Queue entries are
; strictly FIFO; validation precedes the capacity check, so stale/no-handler is
; deterministic even when the queue is full.
kdefer_send
                DEFER_REQUIRE_ROOT
                ld    (CORE_DEFER_SEND+4),hl
                DEFER_CHECK_SEND_RECORD
kds_pointer_ok push  hl
                call  DEFER_CURRENT_OWNER
                call  DEFER_VALIDATE_OWNER
                pop   hl                            ; owner validation clobbers HL
                jp    nc,kdefer_context
                ld    (CORE_DEFER_SEND),de          ; implicit sender
                ld    e,(hl)
                inc   hl
                ld    d,(hl)
                inc   hl
                ld    a,(hl)                        ; type zero is reserved/invalid
                or    a
                jp    z,kdefer_bad
                ld    (CORE_DEFER_SEND+2),de
                call  DEFER_VALIDATE_OWNER
                jp    nc,kdefer_stale
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,CORE_APP_FLAGS
                add   a,l
                ld    l,a
                bit   CORE_APP_TERMINATING_BIT,(hl)
                jp    nz,kdefer_stale
                ld    hl,CORE_DEFER_HANDLER_LO
                ld    a,c
                add   a,l
                ld    l,a
                ld    b,(hl)
                ld    hl,CORE_DEFER_HANDLER_HI
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    b
                jp    z,kdefer_no_handler
                ld    a,(CORE_DEFER_COUNT)
                cp    CORE_DEFER_CAPACITY
                jp    nc,kdefer_full
                push  af                            ; destination = queue + count*8
                add   a,a
                add   a,a
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,CORE_DEFER_QUEUE
                add   hl,de
                ex    de,hl
                ld    hl,CORE_DEFER_SEND            ; sender + receiver
                ld    bc,4
                ldir
                ld    hl,(CORE_DEFER_SEND+4)        ; input pointer: skip receiver, copy type/p0/p1/p2
                inc   hl
                inc   hl
                ld    bc,4
                ldir
                pop   af
                inc   a
                ld    (CORE_DEFER_COUNT),a          ; publish only after all bytes are copied
                xor   a
                ret

kdefer_current
                ld    a,(CORE_DEFER_BUSY)
                or    a
                jr    z,kdefer_no_current
                ld    de,CORE_DEFER_CURRENT
                ret
kdefer_no_current
                ld    de,0
                ret

kdefer_free    ld    a,(CORE_DEFER_COUNT)
                ld    b,a
                ld    a,CORE_DEFER_CAPACITY
                sub   b
                ret

kdefer_find_service
                ld    c,0
                call  DEFER_FIND_SERVICE
                jr    kdefer_owner_for_handle
kdefer_find_accessory
                call  DEFER_FIND_ACCESSORY
kdefer_owner_for_handle
                or    a
                jr    z,kdefer_no_current
                dec   a
                ld    c,a
                ld    hl,CORE_WIN_OWNER
                add   a,l
                ld    l,a
                ld    e,(hl)
                ld    hl,CORE_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    d,(hl)
                call  DEFER_VALIDATE_OWNER
                ret   c
                jr    kdefer_no_current

kdefer_cancel_all
                DEFER_REQUIRE_ROOT
                call  DEFER_CURRENT_OWNER
                call  DEFER_VALIDATE_OWNER
                jr    nc,kdefer_context
                jp    defer_cancel_sender

kdefer_stale   ld    a,GB_DEFER_ERR_STALE
                ret
kdefer_no_handler
                ld    a,GB_DEFER_ERR_NO_HANDLER
                ret
kdefer_full    ld    a,GB_DEFER_ERR_FULL
                ret
kdefer_context ld    a,GB_DEFER_ERR_CONTEXT
                ret
