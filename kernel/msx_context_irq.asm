; MSX-DOS IM1 adapter. All entries require interrupts already excluded.
; The original DOS JP target sees the raw interrupt stack on the selected
; task's fixed stack, never the temporary scheduler stack. H.TIMI is unsuitable:
; BIOS would map ROM over the low-RAM state needed by the shared mechanism.
MSX_IRQ_VECTOR equ #0038
sched_irq_install
                ld hl,(MSX_IRQ_VECTOR+1)
                ld (sched_irq_chain+1),hl
                ld hl,sched_irq_vector
                ld (MSX_IRQ_VECTOR+1),hl
                ret
sched_irq_uninstall
                ld hl,(sched_irq_chain+1)
                ld (MSX_IRQ_VECTOR+1),hl
                ret
sched_irq_chain
                jp 0                         ; patched original DOS handler
