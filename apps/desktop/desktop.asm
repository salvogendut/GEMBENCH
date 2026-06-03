; desktop - the GEOBENCH desktop (banked app booted into PAGE_APP0). Draws the
; backdrop + Disk/Clock/Trash icons under the kernel's top bar, runs the
; pointer, lets you DRAG icons (hold fire, move a red outline, release to drop),
; and double-click the Disk icon to open the file manager (GB_RUN "FILEMGR").
;
; A press over an icon both registers a click (for double-click) and begins a
; drag; release drops the icon at its new spot (no move => it was just a click).

                include "../../lib/gbapp.inc"

DCLICK          equ   40
N_ICONS         equ   3
IC_W            equ   8            ; icon width (bytes) = 32 px
IC_H            equ   32           ; icon height (lines)
BOX_H           equ   44           ; icon + label height (hit-test / lift)
XMAX            equ   80-IC_W      ; drag clamp
YMIN            equ   9
YMAX            equ   200-BOX_H

                org   APP_BASE
dt_entry
                call  dt_paint
dt_reset
                xor   a
                ld    (drag_active),a
                ld    (dc_timer),a
                ld    (held_prev),a

; --- event loop ----------------------------------------------------------
dt_loop
                call  GB_POLL                ; B=col, C=line, D=flags
                ld    a,b
                ld    (cur_col),a
                ld    a,c
                ld    (cur_line),a
                ld    a,d
                ld    (poll_flags),a
                ld    a,(dc_timer)           ; tick the double-click window
                or    a
                jr    z,dl_q
                dec   a
                ld    (dc_timer),a
dl_q
                ld    a,(poll_flags)
                bit   1,a                     ; ESC -> quit
                jp    nz,dt_done
                and   4                        ; bit2 = fire held
                ld    (held_now),a

                ld    a,(held_prev)           ; falling edge -> drop a drag
                or    a
                jr    z,dl_nofall
                ld    a,(held_now)
                or    a
                jr    nz,dl_nofall
                ld    a,(drag_active)
                or    a
                jr    z,dl_nofall
                call  do_drop
                jp    dt_loop
dl_nofall
                ld    a,(held_now)
                ld    (held_prev),a
                ld    a,(drag_active)         ; dragging -> follow the pointer
                or    a
                jr    z,dl_click
                call  do_dragmove
                jp    dt_loop
dl_click
                ld    a,(poll_flags)          ; a fresh press?
                bit   0,a
                jp    z,dt_loop
                call  hit_icon               ; A = icon under the pointer, CF if hit
                jp    nc,dt_loop
                ld    (click_icon),a
                ld    a,(dc_timer)           ; second click on the same icon = open
                or    a
                jr    z,dl_first
                ld    a,(dc_idx)
                ld    b,a
                ld    a,(click_icon)
                cp    b
                jr    nz,dl_first
                ld    a,(click_icon)         ; double-click: only Disk (0) opens
                or    a
                jr    nz,dl_dcdone
                ld    hl,name_filemgr
                call  GB_RUN
                call  dt_paint
                jp    dt_reset
dl_dcdone
                xor   a
                ld    (dc_timer),a
                jp    dt_loop
dl_first
                ld    a,(click_icon)
                ld    (dc_idx),a
                ld    a,DCLICK
                ld    (dc_timer),a
                call  do_dragstart
                jp    dt_loop
dt_done
                ret

; --- painting ------------------------------------------------------------
; dt_paint: backdrop (below the top bar) + help + icons, pointer on top.
dt_paint
                ld    b,0
                ld    c,8
                ld    d,80
                ld    e,192
                xor   a
                call  GB_FILL
                ld    b,1
                ld    c,10
                ld    d,1
                ld    e,0
                ld    hl,help_msg
                call  GB_TEXT
                xor   a
                ld    (di_i),a
dp_loop
                ld    a,(di_i)
                call  draw_one_icon
                ld    a,(di_i)
                inc   a
                ld    (di_i),a
                cp    N_ICONS
                jr    c,dp_loop
                jp    GB_CURSHOW

; draw_one_icon: A = index -> full icon + its label at (ic_x[i], ic_y[i]).
draw_one_icon
                ld    (di_i),a
                ld    c,a
                ld    b,0
                ld    hl,ic_slot
                add   hl,bc
                ld    a,(hl)
                ld    (di_slot),a
                ld    hl,ic_x
                add   hl,bc
                ld    a,(hl)
                ld    (di_x),a
                ld    hl,ic_y
                add   hl,bc
                ld    a,(hl)
                ld    (di_y),a
                ld    a,(di_x)               ; icon
                ld    b,a
                ld    a,(di_y)
                ld    c,a
                ld    a,(di_slot)
                call  GB_ICON
                ld    a,(di_x)               ; label below it
                ld    b,a
                ld    a,(di_y)
                add   a,34
                ld    c,a
                ld    a,(di_i)
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,ic_lbl
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a                       ; HL = label string
                ld    d,1
                ld    e,0
                jp    GB_TEXT

; --- drag ----------------------------------------------------------------
; do_dragstart: lift click_icon (fill its box with backdrop) and show the
; outline at its position; record the grab offset.
do_dragstart
                ld    a,(click_icon)
                ld    (drag_idx),a
                ld    c,a
                ld    b,0
                ld    hl,ic_x
                add   hl,bc
                ld    a,(hl)
                ld    (out_x),a
                ld    hl,ic_y
                add   hl,bc
                ld    a,(hl)
                ld    (out_y),a
                ld    a,(cur_col)            ; grab offset within the icon
                ld    hl,out_x
                sub   (hl)
                ld    (grab_dx),a
                ld    a,(cur_line)
                ld    hl,out_y
                sub   (hl)
                ld    (grab_dy),a
                ld    a,1
                ld    (drag_active),a
                call  GB_CURHIDE
                ld    a,(out_x)             ; erase the icon + label
                ld    b,a
                ld    a,(out_y)
                ld    c,a
                ld    d,IC_W+2
                ld    e,BOX_H
                xor   a
                call  GB_FILL
                call  draw_outline           ; red outline at (out_x,out_y)
                jp    GB_CURSHOW

; do_dragmove: move the outline to (cursor - grab offset), clamped.
do_dragmove
                ld    a,(cur_col)
                ld    hl,grab_dx
                sub   (hl)
                jr    nc,dm_xp
                xor   a
dm_xp
                cp    XMAX+1
                jr    c,dm_xok
                ld    a,XMAX
dm_xok
                ld    (new_x),a
                ld    a,(cur_line)
                ld    hl,grab_dy
                sub   (hl)
                jr    nc,dm_yp
                xor   a
dm_yp
                cp    YMIN
                jr    nc,dm_ylo
                ld    a,YMIN
dm_ylo
                cp    YMAX+1
                jr    c,dm_yok
                ld    a,YMAX
dm_yok
                ld    (new_y),a
                ld    a,(new_x)             ; nothing moved -> leave it
                ld    hl,out_x
                cp    (hl)
                jr    nz,dm_go
                ld    a,(new_y)
                ld    hl,out_y
                cp    (hl)
                ret   z
dm_go
                call  GB_CURHIDE
                xor   a                        ; erase old outline (backdrop pen)
                call  draw_outline_pen
                ld    a,(new_x)
                ld    (out_x),a
                ld    a,(new_y)
                ld    (out_y),a
                call  draw_outline           ; draw new outline (red)
                jp    GB_CURSHOW

; do_drop: commit the icon's new position, erase the outline, redraw.
do_drop
                ld    a,(drag_idx)
                ld    c,a
                ld    b,0
                ld    hl,ic_x
                add   hl,bc
                ld    a,(out_x)
                ld    (hl),a
                ld    hl,ic_y
                add   hl,bc
                ld    a,(out_y)
                ld    (hl),a
                xor   a
                ld    (drag_active),a
                call  GB_CURHIDE
                call  dt_paint               ; (preserves dc_timer; keeps clicks)
                ret

; draw_outline: red (pen 3) box at (out_x,out_y); draw_outline_pen uses A as pen.
draw_outline
                ld    a,3
draw_outline_pen
                ld    (ol_pen),a
                ld    a,(out_x)
                ld    b,a
                ld    a,(out_y)
                ld    c,a
                ld    d,IC_W
                ld    e,IC_H
                ld    a,(ol_pen)
                jp    GB_FRAME

; hit_icon: cur_col/cur_line -> A = icon index, CF set if over an icon box.
hit_icon
                xor   a
                ld    (hi_i),a
hi_loop
                ld    a,(hi_i)
                ld    c,a
                ld    b,0
                ld    hl,ic_x
                add   hl,bc
                ld    a,(hl)
                ld    (hi_x),a
                ld    hl,ic_y
                add   hl,bc
                ld    a,(hl)
                ld    (hi_y),a
                ld    a,(cur_col)
                ld    hl,hi_x
                cp    (hl)
                jr    c,hi_next
                ld    a,(hi_x)
                add   a,IC_W
                ld    b,a
                ld    a,(cur_col)
                cp    b
                jr    nc,hi_next
                ld    a,(cur_line)
                ld    hl,hi_y
                cp    (hl)
                jr    c,hi_next
                ld    a,(hi_y)
                add   a,BOX_H
                ld    b,a
                ld    a,(cur_line)
                cp    b
                jr    nc,hi_next
                ld    a,(hi_i)
                scf
                ret
hi_next
                ld    a,(hi_i)
                inc   a
                ld    (hi_i),a
                cp    N_ICONS
                jr    c,hi_loop
                or    a
                ret

; --- data ----------------------------------------------------------------
help_msg        db    "Hold fire to drag - double-click Disk",0
lbl_disk        db    "Disk A",0
lbl_clock       db    "Clock",0
lbl_trash       db    "Trash",0
name_filemgr    db    "FILEMGR BIN"

ic_x            db    8,60,60       ; icon positions (byte col) - mutable (drag)
ic_y            db    24,24,150     ; icon positions (line)
ic_slot         db    0,2,3          ; IST slots: floppy, clock, trash
ic_lbl          dw    lbl_disk,lbl_clock,lbl_trash

cur_col         db    0
cur_line        db    0
poll_flags      db    0
held_now        db    0
held_prev       db    0
drag_active     db    0
drag_idx        db    0
grab_dx         db    0
grab_dy         db    0
out_x           db    0
out_y           db    0
new_x           db    0
new_y           db    0
ol_pen          db    0
dc_timer        db    0
dc_idx          db    0
click_icon      db    0
hi_i            db    0
hi_x            db    0
hi_y            db    0
di_i            db    0
di_x            db    0
di_y            db    0
di_slot         db    0
dt_end
                save  "build/DESKTOP.RAW",APP_BASE,dt_end-APP_BASE
