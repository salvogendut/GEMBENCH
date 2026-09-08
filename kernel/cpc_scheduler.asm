; Same composition/order as MSX2, with CPC-only hardware providers.
                include "cpc_context.inc"
                include "cpc_visibility.inc"
                include "core/context_contract.inc"
                org CPC_SCHED_BASE
cpc_scheduler_begin
                jp sched_init_impl
                jp sched_yield
                jp k_task_enable
                jp sched_irq_uninstall
                jp sched_compositor_prepare
                jp sched_region_begin
                jp sched_region_next
                jp sched_region_test
                include "core/context_init.asm"
                include "core/context_save.asm"
                include "core/worker_select.asm"
                include "core/context_restore.asm"
                include "core/context_tasks.asm"
                include "core/visibility_prepare.asm"
                include "core/visible_regions.asm"
                include "core/window_visibility.asm"
sched_irq_install
                ld a,#C3
                ld (#0038),a
                ld hl,cpc_irq_entry
                ld (#0039),hl
                im 1
                ret
sched_irq_uninstall
                di
                ret                         ; takeover build exits only by reset
sched_irq_vector
                include "core/context_irq.asm"
sched_wm_entry
                ld hl,WM_TABLE
                or a
                ret z
                ld b,a
                ld de,WM_ESZ
sched_we_add
                add hl,de
                djnz sched_we_add
                ret
sched_md_call
                jp (hl)
sched_bank_set
                jp foundation_bank_set
cpc_scheduler_end
                assert cpc_scheduler_end<=CPC_SCHED_END,"CPC scheduler exceeds fixed allocation"
                save "SCHED.RAW",cpc_scheduler_begin,cpc_scheduler_end-cpc_scheduler_begin
