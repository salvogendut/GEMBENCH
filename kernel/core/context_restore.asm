; Shared Z80 context mechanism (#76); see context_contract.inc.
; Resume/restore the context chosen by the shared worker selector.
; The old SP is the bottom item on the provider's temporary stack.
sched_resume_old
                pop   hl
                ld    sp,hl
                ret

sched_restore_slot
                ld    a,c
                push  af                      ; target slot above the saved old SP
                CTX_ENTRY_FROM_FLAGS
                ld    a,(hl)                  ; target app page from WM entry +0
                CTX_MAP_BANK
                ld    a,(CORE_CONTEXT_SNAPSHOT)
                or    a
                jr    z,sched_restore_fault
                ld    c,a
                ld    e,a
                ld    b,0
                ld    d,b
                ld    hl,(CORE_CONTEXT_BOOT_SP)
                or    a
                sbc   hl,de                   ; target fixed-stack bottom
                push  hl                      ; keep target SP below mapper call frames
                ex    de,hl                   ; DE = fixed destination
                ld    hl,CORE_CONTEXT_STACK_DATA
                ldir
                pop   hl                      ; target SP
                pop   af                      ; target slot
                ld    (CORE_CONTEXT_CURRENT),a
                pop   de                      ; discard old SP
                ld    sp,hl
                ret

sched_restore_fault
                ; The old bank was already replaced. Map the old task again,
                ; then resume its still-intact fixed stack.
                pop   af                      ; discard target slot above the saved old SP
                ld    a,(CORE_CONTEXT_CURRENT)
                CTX_WINDOW_ENTRY
                ld    a,(hl)
                CTX_MAP_BANK
                ld    a,1
                ld    (CORE_CONTEXT_FAULT),a
                CTX_SAMPLE_FAULT
                jr    sched_resume_old

sched_switch_fault
                ld    a,1
                ld    (CORE_CONTEXT_FAULT),a
                CTX_SAMPLE_FAULT
                ret                             ; original SP is still active
