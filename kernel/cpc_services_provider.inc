; Private CPC native service binding, no public jump table or TPA buffers yet.
; Root/kernel serialization is the same as MSX. Executable callbacks belong
; below #7F00; six-byte send records also accept ordinary C locals on the fixed
; main stack. Neither stack guards nor IRQ/temporary stacks are client buffers.
GB_DEFER_ERR_STALE equ 2
GB_DEFER_ERR_NO_HANDLER equ 3
GB_DEFER_ERR_FULL equ 4
GB_DEFER_ERR_BADARG equ 5
GB_DEFER_ERR_CONTEXT equ 6
DEFER_CURRENT_OWNER equ owner_current
DEFER_VALIDATE_OWNER equ owner_validate
DEFER_SET_BANK equ foundation_bank_set
DEFER_CALL equ cpc_defer_call
DEFER_FIND_SERVICE equ ksh_find
DEFER_FIND_ACCESSORY equ ksh_find_accessory
ROOT_DISPATCH_ONE equ defer_dispatch_one
ROOT_MAP_FOCUS equ wm_map_focus
ROOT_FULL_CLIP equ clip_set_full
CORE_LOOKUP_ACCESSORY_CLASS equ #A0
CORE_LOOKUP_CLASS_MASK equ #E0
CORE_LOOKUP_CLASS equ #3350
CORE_LOOKUP_ID equ CORE_APP_SLOT
CORE_LOOKUP_CURSOR equ #3351
CORE_LOOKUP_SLOT equ #3352
                ifndef CPC_RUNTIME
CPC_TIMER_COLLECT equ #4C00
                endif
CPC_FULLSCREEN equ #130A
                macro DEFER_REQUIRE_ROOT
                ld a,(SCHED_CURRENT)
                or a
                jp nz,kdefer_context
                mend
                macro DEFER_CHECK_CALLBACK
                ld a,h
                cp #40
                jr c,kdefer_bad
                cp #7F
                jr nc,kdefer_bad
                mend
                macro DEFER_CHECK_SEND_RECORD
                ld a,h
                cp #40
                jr nc,cpc_kds_aperture
                push hl
                ld de,CPC_MAIN_STACK
                or a
                sbc hl,de
                pop hl
                jp c,kdefer_bad
                push hl
                ld de,CPC_MAIN_TOP-5          ; six-byte span ends before stack top
                or a
                sbc hl,de
                pop hl
                jp nc,kdefer_bad
                jr kds_pointer_ok
cpc_kds_aperture
                cp #7F
                jp nc,kdefer_bad
                cp #7E
                jr nz,kds_pointer_ok
                ld a,l
                cp #FB
                jp nc,kdefer_bad
                mend
                macro DEFER_ACTIVATE_WINDOW
                call wm_entry
                ld de,WM_FR_FLAGS
                add hl,de
                bit 0,(hl)
                ret z
                ld a,c
                call wm_set_clip
                ld a,c
                call wm_raise
                jp wm_repaint_top
                mend
                assert CORE_LOOKUP_SLOT+1<=CPC_REG_END,"service/chrome state overlap"
                ifndef CPC_RUNTIME
                assert CPC_TIMER_COLLECT+116<=CPC_APP_LIMIT,"app-linked collector crosses snapshot"
                endif
