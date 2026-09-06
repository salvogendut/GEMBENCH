; #77 CPC bindings for unmodified shared focus/damage policy. Menu and chrome
; are composition hooks: the diagnostic binds instrumented fixtures, not apps.
CORE_FOCUS_TARGET equ #3210
CORE_FOCUS_OLD equ #3211
CORE_HIT_CURSOR equ #3212
CORE_INPUT_FLAGS equ #3213
CORE_POINTER_X equ #3214
CORE_POINTER_Y equ #3215
CORE_FOCUS_HANDLER equ #3216
CORE_MOVE_X equ #3218
CORE_MOVE_Y equ #3219
CORE_SIZE_W equ #321A
CORE_SIZE_H equ #321B
CORE_REPAINT_INDEX equ #321C
CORE_REPAINT_BANK equ #321D
CORE_POINTER_SUPPRESSED equ #321E
CORE_POINTER_PAINTLOCK equ #321F
CORE_DAMAGE_EXTRA equ CPC_COMPOSITOR_EXTRA
CORE_DAMAGE_EXTRA_PENDING equ CPC_COMPOSITOR_EXTRA_PENDING
CORE_Z_PRESERVE_SLOT equ 1
CORE_FOCUS_VISIBLE_DAMAGE equ 1
CORE_REPAINT_REGIONS equ 1
                ifdef CPC_FAULT_WM_POINTER
CORE_REPAINT_ERASE_POINTER equ 0
                else
CORE_REPAINT_ERASE_POINTER equ 1 ; CPC save-under, not the MSX sprite plane
                endif
CORE_WINDOW_DAMAGE_PAD equ 8
CORE_PAINT_ALIVE_BIT equ 0
CORE_PAINT_MANAGED_BIT equ 1
FOCUS_SET_BANK equ foundation_bank_set
FOCUS_MENU_CLEAR equ CPC_WINDOW_MENU_CLEAR
FOCUS_MENU_INSTALL equ CPC_WINDOW_MENU_INSTALL
FOCUS_BUILD_DAMAGE equ wm_focus_damage
FOCUS_REPAINT equ wm_repaint_all
FOCUS_SET_CLIP equ wm_set_clip
FOCUS_REPAINT_TOP equ wm_repaint_top
PAINT_PREPARE equ sched_compositor_prepare
PAINT_REGION_BEGIN equ sched_region_begin
PAINT_REGION_NEXT equ sched_region_next
PAINT_SET_BANK equ foundation_bank_set
PAINT_CHROME_DRAW equ CPC_WINDOW_CHROME_DRAW
PAINT_CALL equ cpc_window_call
PAINT_POINTER_ERASE equ cpc_window_pointer_hide
PAINT_POINTER_SHOW equ cpc_window_pointer_show
                macro FOCUS_NATIVE_CELL
                call sched_wm_entry
                mend
                macro FOCUS_RECT
                call sched_wm_entry
                inc hl
                mend
                macro FOCUS_EVENT_POINTER
                ld de,9
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                mend
                macro FOCUS_MENU_POINTER
                ld de,11
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                mend
                macro PAINT_WINDOW_TOKEN
                call sched_wm_entry
                mend
                macro PAINT_WINDOW_RECT
                call sched_wm_entry
                inc hl
                mend
                macro PAINT_CLOSE_RECT
                call sched_wm_entry
                ld b,(hl)
                inc hl
                mend
                macro PAINT_WINDOW_FLAGS
                push hl
                ld de,WM_FR_FLAGS
                add hl,de
                ld a,(hl)
                pop hl
                mend
                macro PAINT_WINDOW_NATIVE
                ld a,(hl)
                mend
                macro PAINT_REPAINT_POINTER
                ld de,7
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                mend
                macro PAINT_IRQ_ENTER
                di
                mend
                macro PAINT_IRQ_LEAVE
                ei
                mend
                include "core/window_focus_contract.inc"
                include "core/window_damage_contract.inc"
