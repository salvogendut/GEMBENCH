; Same serialized parameter policy and entry/exit convention as MSX2.
CORE_PARAM_APP_NATIVE equ CORE_APP_CODE_NATIVE
CORE_PARAM_OWNER_MAX equ CPC_OWNER_MAX
CORE_PARAM_MAPPED_NATIVE equ BANK_CUR
CORE_PARAM_CURRENT equ SCHED_CURRENT
CORE_PARAM_LOCK equ SCHED_LOCK
CORE_PARAM_TIMER_OWNER equ #23CA
CORE_PARAM_TIMER_RECT equ #23CB
CORE_PARAM_TIMER_GEN equ #23CF
CORE_PARAM_DROPPED equ #21EC
CORE_PARAM_DROPPED_GEN equ #203F
CORE_PARAM_COLUMNS equ CPC_COLUMNS
CORE_PARAM_WIDTH equ CPC_WIDTH
CORE_PARAM_HEIGHT equ CPC_LINES
PARAM_CURRENT_OWNER equ owner_current
PARAM_WINDOW_CALL equ cpc_parameter_window
PARAM_DRAW_TEXT equ cpc_draw_text
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
                macro PARAM_DRAW_LINE
                call cpc_draw_line
                mend
