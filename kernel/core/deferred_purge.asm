; Shared existing deferred-message policy (#73).
; Provider obligations: deferred_contract.inc.
; Compact messages matching an owner. Mode zero removes both sender and receiver
; (teardown/unregister); mode one removes only sender (explicit cancellation).
; Returns the number removed in A.
defer_purge_owner
                xor   a
                jr    defer_purge_start
defer_cancel_sender
                ld    a,1
defer_purge_start
                ld    (CORE_DEFER_SEND+4),a         ; match mode
                ld    (CORE_DEFER_PURGE_OWNER),de
                xor   a
                ld    (CORE_DEFER_INDEX),a
                ld    (CORE_DEFER_SEND+5),a         ; removed count
defer_purge_loop
                ld    a,(CORE_DEFER_INDEX)
                ld    c,a
                ld    a,(CORE_DEFER_COUNT)
                cp    c
                jr    z,defer_purge_done
                jr    c,defer_purge_done
                ld    a,c
                call  defer_record_ptr
                ld    de,(CORE_DEFER_PURGE_OWNER)
                ld    a,(hl)                        ; sender low/generation
                cp    e
                jr    nz,defer_purge_receiver
                inc   hl
                ld    a,(hl)
                cp    d
                jr    z,defer_purge_remove
                dec   hl
defer_purge_receiver
                ld    a,(CORE_DEFER_SEND+4)
                or    a
                jr    nz,defer_purge_keep
                inc   hl
                inc   hl                            ; receiver low/generation
                ld    a,(hl)
                cp    e
                jr    nz,defer_purge_keep
                inc   hl
                ld    a,(hl)
                cp    d
                jr    nz,defer_purge_keep
defer_purge_remove
                ld    a,(CORE_DEFER_INDEX)
                ld    c,a
                call  defer_remove_index
                ld    hl,CORE_DEFER_SEND+5
                inc   (hl)
                jr    defer_purge_loop              ; compacted next record has same index
defer_purge_keep
                ld    hl,CORE_DEFER_INDEX
                inc   (hl)
                jr    defer_purge_loop
defer_purge_done
                ld    a,(CORE_DEFER_SEND+5)
                ret
