; Fixed MSX2 scheduler composition. Z80 context and worker policy are shared.
; The app-carried image remains at #C900..#CEFF; no CPC placement is implied.
                include "msx_context.inc"
                include "msx_visibility.inc"
                include "core/context_contract.inc"

                org   SCHED_BASE
                jp    sched_init_impl
                jp    sched_yield
                jp    k_task_enable
                jp    sched_irq_uninstall
                jp    sched_compositor_prepare
                jp    sched_region_begin
                jp    sched_region_next
                jp    sched_region_test

                include "core/context_init.asm"
                include "core/context_save.asm"
                include "core/worker_select.asm"
                include "core/context_restore.asm"
                include "core/context_tasks.asm"

                include "core/visibility_prepare.asm"
                include "core/visible_regions.asm"
                include "core/window_visibility.asm"

                include "msx_context_irq.asm"
sched_irq_vector
                include "core/context_irq.asm"
                include "msx_context_helpers.asm"

sched_image_end
                assert sched_image_end-SCHED_BASE<=SCHED_LIMIT,"scheduler exceeds fixed slot"
                assert sched_image_end<=CORE_CONTEXT_CODE_END,"context image exceeds fixed allocation"
