; #77 fixed CPC state/hooks for the existing lifecycle and storage-free cleanup.
; No public app loader, deferred delivery or FSCTX operations are advertised.
GB_APP_F_ROOT equ 2
GB_APP_ERR_ROOT equ 5
GB_APP_ERR_BADARG equ 6
GB_APP_ERR_UNSUPPORTED equ 1
GB_DEFER_RECORD_SIZE equ 8
CORE_DEFER_CAPACITY equ 8
CORE_DEFER_COUNT equ #2376
CORE_DEFER_BUSY equ #2377
CORE_DEFER_CURRENT equ #2378
CORE_DEFER_QUEUE equ #2380
CORE_DEFER_SEND equ #23C0
CORE_DEFER_PURGE_OWNER equ #23C6
CORE_DEFER_INDEX equ #23C8
CORE_DEFER_ACTIVATE equ #23C9
CORE_APP_TERMINATING_BIT equ 2
CORE_DEFER_EVENT equ 12
CORE_MESSAGE equ #1302             ; native message reservation; delivery not linked
CORE_FSCTX_TABLE equ #2600
CORE_FSCTX_MAX equ 4
CORE_FSCTX_RECORD_SIZE equ 144
CORE_FSCTX_ACTIVE equ 0
CORE_FSCTX_OWNER equ 2
                assert CORE_DEFER_ACTIVATE+1<=CORE_PARAM_TIMER_OWNER,"defer/timer overlap"
                assert CORE_FSCTX_TABLE+CORE_FSCTX_MAX*CORE_FSCTX_RECORD_SIZE<=#2840,"FS context reservation overflow"
                assert #2840<=CPC_ARCH_STATE_END,"FS context/architecture overlap"
                include "core/deferred_contract.inc"
                include "core/fsctx_cleanup_contract.inc"

LIFETIME_CURRENT_OWNER equ owner_current
LIFETIME_CLOSE_WINDOW equ app_window_close_slot
LIFETIME_SET_BANK equ foundation_bank_set
LIFETIME_REMOVE_Z equ wm_z_remove
LIFETIME_FOCUS_TOP equ wm_focus_top
LIFETIME_MAP_FOCUS equ wm_map_focus
LIFETIME_REPAINT equ wm_repaint_all
OWNER_PAGE_PURGE_MESSAGES equ cpc_lifetime_purge
OWNER_PAGE_CLOSE_CONTEXTS equ cpc_lifetime_contexts
                macro LIFETIME_PREPARE_CLOSE
                call wm_set_clip
                ld a,b
                ld (CORE_ALLOC_NATIVE),a
                ld de,WM_FR_FLAGS-4
                add hl,de
                mend
                macro LIFETIME_DROP_WORKER
                bit 3,(hl)
                jr z,cpc_lifetime_not_worker
                push hl
                ld hl,SCHED_RUNNABLE
                dec (hl)
                pop hl
cpc_lifetime_not_worker
                mend
                macro LIFETIME_DRAG_CURRENT
                ifdef CPC_RUNTIME
                call mw_move_silent
                else
                ; No input/managed-drag provider yet. Explicit failure, not a
                ; success-only placeholder. This private link has no public ABI.
                jp cpc_lifetime_drag_unsupported
                endif
                mend
