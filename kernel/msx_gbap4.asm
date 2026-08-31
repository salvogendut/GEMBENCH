; MSX2 wrapper for the shared transactional GBAP v4 admission gate.

                include "../lib/gbapp.inc"
                include "../lib/msx/glue.inc"

GBAP4_GATE_BASE        equ MSX_GBAP4_GATE
GBAP4_GATE_LIMIT       equ MSX_GBAP4_GATE_LIMIT
GBAP4_GATE_SIZE        equ MSX_GBAP4_GATE_SIZE
GBAP4_SYSINFO_SIZE     equ MSX_SYSINFO_SIZE
GBAP4_PAGE_FREE        equ MSX_PAGE_FREE

                include "gbap4_gate_core.asm"
