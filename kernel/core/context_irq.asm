; Shared Z80 context mechanism (#76); see context_contract.inc.
sched_irq_body
                push  af
                push  hl                      ; quantum bookkeeping must preserve worker HL
                ld    a,(CORE_CONTEXT_CURRENT)
                or    a
                jr    z,sched_irq_fast
sched_irq_worker
                if !CORE_CONTEXT_SWITCH
                jp    sched_irq_fast          ; diagnostic: prove the firmware trampoline alone
                endif
                ld    hl,CORE_CONTEXT_QUANTUM
                dec   (hl)
                jr    nz,sched_irq_fast
                ld    (hl),CORE_CONTEXT_QUANTUM_TICKS
                ld    a,(CORE_CONTEXT_LOCK)
                or    a
                jr    z,sched_irq_switch
sched_irq_fast
                pop   hl
                CTX_IRQ_FINISH

sched_irq_switch
                pop   hl
                inc   a                       ; A is zero after the CORE_CONTEXT_LOCK test
                ld    (CORE_CONTEXT_IRQ_PENDING),a      ; common restore must complete this firmware tick
                push  bc
                push  de
                push  hl
                push  ix
                push  iy
                ex    af,af'
                push  af
                ex    af,af'
                exx
                push  bc
                push  de
                push  hl
                exx
                ld    hl,21                   ; interrupted PC high byte after ten PUSHes
                add   hl,sp
                ld    a,(hl)
                cp    CORE_CONTEXT_APP_FIRST_HI                     ; only code in the mapped app bank is preemptible
                jr    c,sched_irq_defer
                cp    CORE_CONTEXT_APP_END_HI
                jr    nc,sched_irq_defer
                ld    a,(CORE_CONTEXT_CURRENT)
                CTX_WINDOW_ENTRY
                ld    a,(CORE_CONTEXT_BANK)
                cp    (hl)                    ; reject kernel modules mapped over the app bank
                jr    nz,sched_irq_defer
                call  sched_switch_context
sched_irq_restore
                xor   a
                ld    (CORE_CONTEXT_LOCK),a
                jp    sched_context_restore
sched_irq_defer
                jp    sched_context_restore
