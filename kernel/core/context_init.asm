; Shared Z80 context mechanism (#76); see context_contract.inc.
sched_init_impl
                xor   a
                ld    hl,CORE_CONTEXT_LOCK
                ld    de,CORE_CONTEXT_LOCK+1
                ld    bc,7
                ld    (hl),a
                ldir                          ; clear all eight scheduler bytes
                ld    a,#FF
                ld    (CORE_CONTEXT_CURRENT),a
                ld    a,1
                ld    (CORE_CONTEXT_LOCK),a          ; kernel owns execution at boot
                ld    a,CORE_CONTEXT_QUANTUM_TICKS
                ld    (CORE_CONTEXT_QUANTUM),a
                if CORE_CONTEXT_TIMER
                CTX_IRQ_INSTALL       ; one install for the scheduler lifetime
                endif
                ret
