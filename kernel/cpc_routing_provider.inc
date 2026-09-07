; Fixed CPC binding for the production MSX root loop and native input router.
PREEMPTIVE_CONTEXT equ 1
WM_GADGETS equ 1
SCR_COLS equ CPC_COLUMNS
SCR_LINES equ CPC_LINES
POLL_FLAGS equ CORE_INPUT_FLAGS
POLL_MX equ CORE_POINTER_X
POLL_MY equ CORE_POINTER_Y
APP_HANDLER equ CORE_FOCUS_HANDLER
BAR_HANDLER equ #3300
UI_MODAL equ #3302
in_fire equ #3303
in_quit equ #3304
poll_lastfire equ #3305
poll_byte equ #3306
poll_line equ #3307
cpc_poll_stamp equ #335A             ; 16-bit cadence; #3308 is now reserved
                ifdef CPC_RUNTIME
cpc_pointer_interval equ #335C
cpc_pointer_max_gap equ #335E        ; IRQ ticks, consecutive moving samples
cpc_pointer_moves equ #3360
cpc_pointer_moving equ #3362
cpc_pointer_sample_stamp equ #3363 ; actual sample time, independent of deadline
                assert cpc_pointer_sample_stamp+2<=CPC_REG_END,"pointer cadence state overflow"
                endif
wm_sav_x equ #3309
wm_sav_y equ #330A
wm_sav_w equ #330B
wm_sav_h equ #330C
sp_x equ #330D
sp_y equ #330E
ss_w equ #330F
ss_h equ #3310
ghost_on equ #3311
WM_DRAGX0 equ #3312
WM_DRAGY0 equ #3313
mwm_notify equ #3314
GB_MSG_MENU equ 1
GB_MSG_CLICK equ 4
GB_MSG_FRAME equ 5
GB_MSG_CLOSE equ 6
GB_MSG_DRAG equ 7
GB_MSG_MOVED equ 8
GB_MSG_SIZED equ 9
GB_MSG_MAXIMIZED equ 10
                ifdef CPC_FAULT_ROUTE_BANK
ROOT_HOME_NATIVE equ WM_TABLE+25
                else
ROOT_HOME_NATIVE equ WM_TABLE
                endif
                ifdef CPC_FAULT_ROUTE_CLICK
POLL_MENU_DISPATCH equ cpc_route_bad_menu
                else
POLL_MENU_DISPATCH equ menu_dispatch
                endif
                ifndef bank_set
bank_set equ foundation_bank_set
                endif
SCHED_YIELD_ENTRY equ sched_yield
cursor_erase equ cpc_window_pointer_hide
cursor_show equ cpc_window_pointer_show
                macro ROUTER_MAX_STORAGE
                mend
                macro GESTURE_STATE_STORAGE
                mend
                macro ROOT_LOOP_REPEAT
                ifdef CPC_RUNTIME
                jp wm_loop
                else
                jp cpc_route_repeat           ; diagnostic boundary/exit, not an alternate loop
                endif
                mend
                assert launch_arg+11<=BAR_HANDLER,"registration/routing state overlap"
                assert mwm_notify+1<=CORE_LOOKUP_CLASS,"routing/service scratch overlap"
                assert WM_ESZ==25,"root router requires the frozen native record"
                assert WM_FR_FRAME==5,"root frame offset changed"
