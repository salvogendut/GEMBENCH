                include "cpc_lifetime_provider.inc"
cpc_lifetime_begin
                include "core/app_lifetime.asm"
                include "core/window_close.asm"
                include "core/owner_reclaim.asm"
                include "core/deferred_queue.asm"
                include "core/deferred_purge.asm"
                include "core/fsctx_cleanup.asm"
cpc_lifetime_end
cpc_lifetime_drag_unsupported
                ld a,GB_APP_ERR_UNSUPPORTED
                ret
cpc_lifetime_purge
                ifndef CPC_FAULT_LIFE_PURGE
                jp defer_purge_owner
                else
                ret                           ; deliberate missing cleanup
                endif
cpc_lifetime_contexts
                ifndef CPC_FAULT_LIFE_FSCTX
                jp fsctx_owner_cleanup
                else
                ret                           ; deliberate missing cleanup
                endif
