; Aliases only: extraction must not change MSX bytes or app-linked collectors.
CORE_LOOKUP_ACCESSORY_CLASS equ GB_SHELL_ACCESSORY_CLASS
CORE_LOOKUP_CLASS_MASK equ WM_SHELL_MASK
CORE_LOOKUP_CLASS equ wm_slot
CORE_LOOKUP_ID equ MSX_APP_SLOT
CORE_LOOKUP_CURSOR equ wm_hz
CORE_LOOKUP_SLOT equ wm_rp_i
ROOT_DISPATCH_ONE equ defer_dispatch_one
ROOT_MAP_FOCUS equ wm_map_focus
ROOT_FULL_CLIP equ clip_set_full
ROOT_HOME_NATIVE equ MSX_TPASEG
POLL_MENU_DISPATCH equ menu_dispatch
                macro ROOT_LOOP_REPEAT
                jr wm_loop
                mend
                macro ROUTER_MAX_STORAGE
wm_sav_x        db 0
wm_sav_y        db 0
wm_sav_w        db 0
wm_sav_h        db 0
                mend
                macro GESTURE_STATE_STORAGE
mw_desc         dw 0
mwm_notify      db 0
                mend
