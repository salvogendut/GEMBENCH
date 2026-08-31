; Standalone fixed-RAM scheduler payload for issue #477.

                ifdef PLATFORM_PCW
                assert 0,"GEMBENCH only builds the MSX2 scheduler"
                endif
                ifndef PLATFORM_MSX
PLATFORM_MSX    equ   1
                endif

PREEMPTIVE      equ   1
PREEMPTIVE_CONTEXT equ 1
                ifndef PREEMPTIVE_TIMER
PREEMPTIVE_TIMER equ  1
                endif
                ifndef PREEMPTIVE_SWITCH
PREEMPTIVE_SWITCH equ 1
                endif

                include "../lib/msx/glue.inc"
                include "lowram.inc"
                include "scheduler.asm"

                save  "build/msx/GBSCHED.RAW",SCHED_BASE,sched_image_end-SCHED_BASE
