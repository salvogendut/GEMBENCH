                include "cpc_services_provider.inc"
cpc_services_begin
                include "core/deferred_api.asm"
                include "core/deferred_dispatch.asm"
                ifdef CPC_RUNTIME
                include "cpc_shell_provider.inc"
                include "core/shell_service.asm"
                else
                include "core/service_lookup.asm"
                endif
cpc_root_dispatch_phase
                include "core/root_dispatch_phase.asm"
                ret
cpc_services_end
cpc_defer_call
                ifdef CPC_FAULT_SERVICE_DELIVERY
                ret                         ; fault: provider loses the callback
                else
                jp (hl)
                endif
cpc_timer_visible
                ifdef CPC_FAULT_SERVICE_VISIBLE
                ld a,1                      ; fault: component hidden by another window
                or a
                ret
                else
                jp sched_region_test
                endif
cpc_timer_payload
                ifndef CPC_RUNTIME
                incbin "TIMER.BIN"          ; SAME app-linked SDAS collector as MSX
cpc_timer_payload_end
                assert cpc_timer_payload_end-cpc_timer_payload==116,"timer collector size changed"
                endif
