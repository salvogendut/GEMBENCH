; MSX2 receiving-side GB_PARAMS bindings (#75). SDK/ABI remain target-neutral.
CORE_PARAM_APP_NATIVE equ MSX_APP_CODE_NATIVE
CORE_PARAM_OWNER_MAX equ GB_APP_MAX
CORE_PARAM_MAPPED_NATIVE equ BANK_CUR
CORE_PARAM_CURRENT equ SCHED_CURRENT
CORE_PARAM_LOCK equ SCHED_LOCK
CORE_PARAM_TIMER_OWNER equ MSX_TIMER_OWNER
CORE_PARAM_TIMER_RECT equ MSX_TIMER_RECT
CORE_PARAM_TIMER_GEN equ MSX_TIMER_GEN
CORE_PARAM_DROPPED equ MSX_TIMER_DROPPED
CORE_PARAM_DROPPED_GEN equ MSX_TIMER_DROPPED_GEN
CORE_PARAM_COLUMNS equ 128
CORE_PARAM_WIDTH equ 512
CORE_PARAM_HEIGHT equ 212
PARAM_CURRENT_OWNER equ GB_OWNER
PARAM_WINDOW_CALL equ GB_APP
PARAM_DRAW_TEXT equ GB_TEXT

; Entry/exit retain exact IFF2, IX, scheduler-lock and status/boolean behavior.
                macro PARAM_ENTER
                push ix
                ld a,i
                push af
                di
                ld a,(CORE_PARAM_LOCK)
                push af
                ld a,1
                ld (CORE_PARAM_LOCK),a
                mend
                macro PARAM_LEAVE
                ld d,a
                di
                pop af
                ld (CORE_PARAM_LOCK),a
                pop af
                ld a,d
                pop ix
                jp po,up_return
                ei
                mend

; Canonical line record -> private MSX graphics workspace, then public leaf.
                macro PARAM_DRAW_LINE
                ld hl,up_request+2
                ld de,GLINE_X0             ; legacy backend is private to MSX
                ld bc,9
                ldir
                call GB_LINE
                mend
