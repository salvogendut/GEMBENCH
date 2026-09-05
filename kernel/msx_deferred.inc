; MSX2 bindings for shared deferred-message policy (#73).
; Public pointer validation stays here; macros preserve the old instructions.
CORE_DEFER_CAPACITY equ GB_DEFER_MAX
CORE_APP_TERMINATING_BIT equ 2
CORE_DEFER_EVENT equ GB_MSG_DEFER
CORE_MESSAGE equ GB_MSG
DEFER_CURRENT_OWNER equ owner_current
DEFER_VALIDATE_OWNER equ owner_validate
DEFER_SET_BANK equ bank_set
DEFER_CALL equ md_call
DEFER_FIND_SERVICE equ ksh_find
DEFER_FIND_ACCESSORY equ ksh_find_accessory
CORE_DEFER_SEND equ MSX_DEFER_SEND
CORE_DEFER_COUNT equ MSX_DEFER_COUNT
CORE_DEFER_BUSY equ MSX_DEFER_BUSY
CORE_DEFER_CURRENT equ MSX_DEFER_CURRENT
CORE_DEFER_QUEUE equ MSX_DEFER_QUEUE
CORE_DEFER_PURGE_OWNER equ MSX_DEFER_PURGE_OWNER
CORE_DEFER_INDEX equ MSX_DEFER_INDEX
CORE_DEFER_ACTIVATE equ MSX_DEFER_ACTIVATE

                macro DEFER_REQUIRE_ROOT
                if PREEMPTIVE_CONTEXT
                ld    a,(SCHED_CURRENT)
                or    a
                jp    nz,kdefer_context          ; workers cannot publish callbacks
                endif
                mend

                macro DEFER_CHECK_CALLBACK
                ld    a,h                       ; callbacks must live in the mapped app page
                cp    #40
                jr    c,kdefer_bad
                cp    #80
                jr    nc,kdefer_bad
                mend

                macro DEFER_CHECK_SEND_RECORD
                ld    a,h
                cp    #40
                jp    c,kdefer_bad
                cp    #80
                jr    c,kds_page1_pointer
                cp    MSX_APP_FIXED_BOTTOM/256
                jp    c,kdefer_bad               ; reject kernel glue/scheduler fixed RAM
                push  hl
                ld    de,5                       ; the complete six-byte record must remain TPA
                add   hl,de
                ex    de,hl
                ld    hl,(BOOT_SP)               ; stable copy of the DOS/Nextor TPA ceiling
                or    a
                sbc   hl,de
                pop   hl
                jp    c,kdefer_bad
                jp    z,kdefer_bad               ; ceiling itself belongs to DOS
                jr    kds_pointer_ok
kds_page1_pointer
                cp    #7F
                jr    nz,kds_pointer_ok
                ld    a,l
                cp    #FB                       ; record through HL+5 must remain below #8000
                jp    nc,kdefer_bad
                mend

                macro DEFER_ACTIVATE_WINDOW
                call  wm_entry
                ld    de,WM_FR_FLAGS
                add   hl,de
                bit   0,(hl)
                ret   z
                ld    a,c
                call  wm_set_clip                ; repaint only the raised endpoint window
                ld    a,c
                call  wm_raise
                jp    wm_repaint_top
                mend

                include "core/deferred_contract.inc"
