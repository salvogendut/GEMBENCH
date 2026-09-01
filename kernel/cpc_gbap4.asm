; CPC wrapper for the shared transactional GBAP v4 admission gate.
; The module runs below the banked application window and is reloaded before
; each launch, so normal paged modules may continue sharing this workspace.

                include "../lib/gbapp.inc"

GBAP4_GATE_BASE        equ #2200
GBAP4_GATE_LIMIT       equ #2700
GBAP4_GATE_SIZE        equ 1201
GBAP4_SYSINFO_SIZE     equ 48
                ifndef PREEMPTIVE
PREEMPTIVE             equ 0
                endif
                if PREEMPTIVE
GBAP4_PAGE_FREE        equ #3E0E
                else
GBAP4_PAGE_FREE        equ #3C0E
                endif

                include "gbap4_gate_core.asm"
