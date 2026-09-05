; MSX2 bindings for the existing shared focus/stack policy (#70).
; No allocations or extra CALLs. The lifetime provider supplies focus/count.
CORE_Z_ORDER equ WM_Z
CORE_FOCUS_HANDLER equ APP_HANDLER
CORE_INPUT_FLAGS equ POLL_FLAGS
CORE_POINTER_X equ POLL_MX
CORE_POINTER_Y equ POLL_MY
CORE_FOCUS_TARGET equ wm_slot
CORE_FOCUS_OLD equ wm_open_back
CORE_HIT_CURSOR equ wm_hz

; Keep the original instruction sequences in normal and cooperative builds.
; CPC integration must adopt the normal shared policy, not a platform fork.
CORE_Z_PRESERVE_SLOT equ PREEMPTIVE
CORE_FOCUS_VISIBLE_DAMAGE equ MSX_VISIBLE_COMPOSITOR

FOCUS_SET_BANK equ bank_set
FOCUS_MENU_CLEAR equ menu_clear
FOCUS_MENU_INSTALL equ menu_install
FOCUS_BUILD_DAMAGE equ wm_focus_damage
FOCUS_REPAINT equ wm_repaint_all
FOCUS_SET_CLIP equ wm_set_clip
FOCUS_REPAINT_TOP equ wm_repaint_top

                macro FOCUS_NATIVE_CELL
                call  wm_entry
                mend

                macro FOCUS_RECT
                call  wm_entry
                inc   hl
                mend

                macro FOCUS_EVENT_POINTER
                ld    de,WM_FR_EVENT
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                mend

                macro FOCUS_MENU_POINTER
                ld    de,WM_FR_MENU
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                mend
