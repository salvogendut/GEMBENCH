; CPC fixed bindings for the existing owner/page/window identity mechanisms.
; This subset does NOT implement Desktop/lifetime teardown or service cleanup.
CORE_PAGE_CAPACITY equ #20
CORE_LEGACY_BUSY equ #1440
CORE_ALLOC_HANDLE equ #22E9
CORE_ALLOC_INDEX equ #22EC
CORE_ALLOC_NATIVE equ #22EB
CORE_ALLOC_OWNER equ #22E6
CORE_ALLOC_PURPOSE equ #22E8
CORE_APP_ACCESSORY equ #2348
CORE_APP_CODE_GEN equ #2320
CORE_APP_CODE_NATIVE equ #2310
CORE_APP_CODE_PAGE equ #2318
CORE_APP_FLAGS equ #2338
CORE_APP_PRIMARY_WIN equ #2330
CORE_APP_SERVICE equ #2340
CORE_APP_WINDOW_COUNT equ #2328
CORE_DEFER_HANDLER_HI equ #236E
CORE_DEFER_HANDLER_LO equ #2366
CORE_OWNER_ACTIVE equ #22C0
CORE_OWNER_GEN equ #22C8
CORE_PAGE_FREE equ #22E5
CORE_PAGE_GEN equ #2280
CORE_PAGE_NATIVE equ #2200
CORE_PAGE_OWNER equ #2240
CORE_PAGE_OWNER_GEN equ #2260
CORE_PAGE_PURPOSE equ #22A0
CORE_PAGE_STATE equ #2220
CORE_PAGE_TOTAL equ #22E4
CORE_PENDING_OWNER equ #22E0
CORE_WIN_OWNER_GEN equ #22D8
GB_OWNER_MAX equ CPC_OWNER_MAX
GB_APP_F_WINDOWLESS equ 8
GB_APP_F_PUBLISHED equ 1
GB_APP_ERR_STALE equ 2
GB_APP_ERR_OWNER equ 3
GB_PAGE_ERR_STALE equ 2
GB_PAGE_ERR_OWNER equ 3
GB_PAGE_ERR_FREE equ 4
GB_PAGE_RESOURCE equ 2
CORE_WIN_GEN equ #2358
CORE_APP_SLOT equ #2360
CORE_WINDOW_HANDLE equ #2361
CORE_WINDOW_SLOT equ #2363
CORE_CALLER_BANK equ #2364
CORE_APP_REMAIN equ #2365
CORE_CLOSE_OWNER equ #22E2
CORE_MAPPED_NATIVE equ BANK_CUR
CORE_PREVIOUS_FOCUS equ #134E
OWNER_PAGE_CURRENT_OWNER equ owner_current
                macro OWNER_PAGE_PUBLISH_FREE
                mend                        ; no public sysinfo advertised yet
                macro LIFETIME_REGISTER_SLOT
                ifdef CPC_REGISTRATION
                ifdef CPC_FAULT_REG_OWNER
                ld a,(WM_FOCUS)              ; deliberately bind the wrong slot
                else
                ld a,(wm_slot)               ; registration binds BEFORE assigning focus
                endif
                else
                ld a,(WM_FOCUS)
                endif
                mend
                macro LIFETIME_TEST_WINDOW_ALIVE
                push bc
                ld a,c
                call sched_wm_entry
                ld de,WM_FR_FLAGS
                add hl,de
                ld a,(hl)
                and 1
                pop bc
                mend
                include "core/owner_page_contract.inc"
                include "core/app_lifetime_contract.inc"
                include "cpc_parameter_provider.inc"
                org CPC_SUPPORT_BASE
cpc_support_begin
                include "core/page_count.asm"
                include "core/owner_identity.asm"
                include "core/page_pool.asm"
                include "core/app_code.asm"
                include "core/window_identity.asm"
                include "core/owner_context.asm"
cpc_parameter_window
                push hl
                call owner_current
                pop hl
                jp window_validate_owned      ; GB_PARAMS only calls native A=5
                include "core/parameters.asm"
                include "core/parameter_contract.inc"
cpc_support_used_end
                assert cpc_support_used_end<=CPC_SUPPORT_END,"CPC support allocation overflow"
                save "SUPPORT.RAW",cpc_support_begin,cpc_support_used_end-cpc_support_begin
