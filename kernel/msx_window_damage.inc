; MSX2 bindings for shared damage construction/repaint dispatch (#72).
; No allocations or extra calls. Window tokens remain native table pointers.
CORE_MOVE_X equ sp_x
CORE_MOVE_Y equ sp_y
CORE_SIZE_W equ ss_w
CORE_SIZE_H equ ss_h
CORE_REPAINT_INDEX equ wm_rp_i
CORE_REPAINT_BANK equ wm_rp_back
; Driver EQU declarations occur later. Checks beside kern_end prove agreement.
CORE_CLIP_X equ #1338
CORE_CLIP_Y equ #1339
CORE_CLIP_W equ #133A
CORE_CLIP_H equ #133B
CORE_SCREEN_COLS equ SCR_COLS
CORE_SCREEN_LINES equ SCR_LINES
CORE_WINDOW_DAMAGE_PAD equ 8        ; existing one-icon-cell right overdraw
CORE_DAMAGE_EXTRA equ MSX_COMPOSITOR_EXTRA
CORE_DAMAGE_EXTRA_PENDING equ MSX_COMPOSITOR_EXTRA_PENDING
CORE_REGION_SLOT equ MSX_REGION_SLOT
CORE_POINTER_SUPPRESSED equ cur_supp
CORE_POINTER_PAINTLOCK equ cur_paintlock
CORE_REPAINT_REGIONS equ MSX_VISIBLE_COMPOSITOR
; Separate hardware choice: a future software pointer must erase before paint
; even when it uses the shared visible-region policy. MSX sprites need not.
CORE_REPAINT_ERASE_POINTER equ 1-MSX_VISIBLE_COMPOSITOR
CORE_PAINT_ALIVE_BIT equ 0
CORE_PAINT_MANAGED_BIT equ 1

PAINT_PREPARE equ SCHED_VIS_REFRESH_ENTRY ; captures sources AND refreshes ranks
PAINT_REGION_BEGIN equ SCHED_REGION_BEGIN_ENTRY
PAINT_REGION_NEXT equ SCHED_REGION_NEXT_ENTRY
PAINT_SET_BANK equ bank_set
PAINT_CHROME_DRAW equ wm_chrome_draw
PAINT_CALL equ md_call
PAINT_POINTER_ERASE equ cursor_erase
PAINT_POINTER_SHOW equ cursor_show
PAINT_RECT_CULL equ rect_cull

                macro PAINT_WINDOW_TOKEN
                call  wm_entry
                mend

                macro PAINT_WINDOW_RECT
                call  wm_entry
                inc   hl
                mend

                macro PAINT_CLOSE_RECT
                call  wm_entry
                ld    b,(hl)
                inc   hl
                mend

                macro PAINT_WINDOW_FLAGS
                push  hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                ld    a,(hl)
                pop   hl
                mend

                macro PAINT_WINDOW_NATIVE
                ld    a,(hl)
                mend

                macro PAINT_RECT_ARGUMENTS
                inc   hl
                ld    b,(hl)
                inc   hl
                ld    c,(hl)
                inc   hl
                ld    d,(hl)
                inc   hl
                ld    e,(hl)
                mend

                macro PAINT_REPAINT_POINTER
                ld    de,WM_FR_REPAINT
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                mend

                macro PAINT_IRQ_ENTER
                di
                mend

                macro PAINT_IRQ_LEAVE
                ei
                mend
