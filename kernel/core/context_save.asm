; Shared Z80 context mechanism (#76); see context_contract.inc.
; sched_switch_context: switch from one fully saved app context to the next
; runnable WM slot. The interrupt wrapper must have pushed, in order:
;
;   AF, BC, DE, HL, IX, IY, AF', BC', DE', HL'
;
; and CALLed this routine. The CALL return address is intentionally part of the
; copied stack. Restoring another snapshot and RET therefore continues in that
; task's copy of the yield/interrupt wrapper, which restores its registers and
; either returns from a yield or completes the pending firmware tick. I and the
; interrupt mode are kernel-owned, not task-local.
;
; Preconditions: IRQ excluded and temporary scratch dead (an IRQ additionally
; requires LOCK=0); CURRENT names a runnable slot, its app bank is mapped,
; and participating app layouts reserve #7F00-#7FFF.
; Clobbers every register (the wrapper has already saved them).
sched_switch_context
                ld    hl,0
                add   hl,sp
                ex    de,hl                   ; DE = old SP
                ld    hl,(CORE_CONTEXT_BOOT_SP)
                or    a
                sbc   hl,de                   ; HL = live fixed-stack bytes
                ld    a,h
                or    a
                jp    nz,sched_switch_fault
                ld    a,l                     ; zero is impossible (CALL is live)
                or    a
                jp    z,sched_switch_fault
                ld    hl,CORE_CONTEXT_STACK_MAX      ; always retain the observed high-water mark
                cp    (hl)
                jr    c,sched_stack_sampled
                ld    (hl),a
                CTX_SAMPLE_STACK
sched_stack_sampled

                ld    sp,CORE_CONTEXT_TMP_TOP        ; kernel scratch is dead while unlocked
                push  de                      ; old SP, below scheduler call frames
                ld    (CORE_CONTEXT_SNAPSHOT),a      ; current app bank is still mapped
                ld    c,a
                ld    b,0
                ex    de,hl                   ; HL = old SP
                ld    de,CORE_CONTEXT_STACK_DATA
                ldir
