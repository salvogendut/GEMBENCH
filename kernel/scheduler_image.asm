; Standalone fixed-RAM scheduler payload for issue #477.

PREEMPTIVE      equ   1
PREEMPTIVE_CONTEXT equ 1
                ifndef PREEMPTIVE_TIMER
PREEMPTIVE_TIMER equ  1
                endif
                ifndef PREEMPTIVE_SWITCH
PREEMPTIVE_SWITCH equ 1
                endif

                ifdef PLATFORM_MSX
                include "../lib/msx/glue.inc"
                else
                ifdef PLATFORM_PCW
                include "../lib/pcw/glue.inc"
                endif
                endif
                include "lowram.inc"
                include "scheduler.asm"

                ifdef PLATFORM_MSX
                save  "build/msx/GBSCHED.RAW",SCHED_BASE,sched_image_end-SCHED_BASE
                else
                ifdef PLATFORM_PCW
                save  "build/pcw/GBSCHED.RAW",SCHED_BASE,sched_image_end-SCHED_BASE
                else
                save  "build/GBSCHED.RAW",SCHED_BASE,sched_image_end-SCHED_BASE
                endif
                endif
