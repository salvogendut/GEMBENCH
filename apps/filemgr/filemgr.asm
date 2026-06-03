; filemgr - the GEOBENCH file manager (banked app). Lists the active drive's
; directory in a MOVABLE window: a half-height type icon + name per entry. The
; pointer/input come from the kernel. Click selects a row (red frame),
; double-click launches the entry's app (GB_LAUNCH). The title bar can be
; dragged: a rubber-band outline (GB_XORFRAME) follows the pointer, and on drop
; the window restores the desktop behind it (save-under) and reopens at the new
; spot. The close gadget / ESC quit.

                include "../../lib/gbapp.inc"

WIN_W           equ   56           ; window size
WIN_H           equ   150
ROW_OFF         equ   18           ; first row, below the title bar
ROW_PITCH       equ   18
DCLICK          equ   40
NONE            equ   #FF
WXMAX           equ   80-WIN_W     ; window drag clamps
WYMIN           equ   8
WYMAX           equ   200-WIN_H

                org   APP_BASE
fm_entry
                call  fm_savereg             ; save the desktop behind the window
                call  fm_draw
fm_reset
                ld    a,NONE
                ld    (sel_row),a
                xor   a
                ld    (dc_timer),a
                ld    (held_prev),a
                ld    (win_dragging),a

; --- event loop ----------------------------------------------------------
fm_loop
                call  GB_POLL                ; B=col, C=line, D=flags
                ld    a,b
                ld    (cur_col),a
                ld    a,c
                ld    (cur_line),a
                ld    a,d
                ld    (poll_flags),a
                ld    a,(dc_timer)
                or    a
                jr    z,fl_q
                dec   a
                ld    (dc_timer),a
fl_q
                ld    a,(poll_flags)
                bit   1,a                     ; ESC -> quit
                jp    nz,fm_done
                and   4                        ; fire held?
                ld    (held_now),a

                ld    a,(held_prev)           ; falling edge -> drop a window drag
                or    a
                jr    z,fl_nofall
                ld    a,(held_now)
                or    a
                jr    nz,fl_nofall
                ld    a,(win_dragging)
                or    a
                jr    z,fl_nofall
                call  win_drop
                jp    fm_loop
fl_nofall
                ld    a,(held_now)
                ld    (held_prev),a
                ld    a,(win_dragging)        ; dragging -> move the outline
                or    a
                jr    z,fl_click
                call  win_dragmove
                jp    fm_loop
fl_click
                ld    a,(poll_flags)          ; a fresh press?
                bit   0,a
                jp    z,fm_loop
                call  hit_close              ; close gadget -> quit
                jr    c,fm_done
                call  hit_title              ; title bar -> drag the window
                jr    c,fl_grab
                call  hit_row                ; a list row?
                jp    nc,fm_loop
                call  GB_CURHIDE
                call  select_row
                ld    a,(dc_timer)           ; double-click = open
                or    a
                jr    z,fl_setdc
                ld    a,(dc_idx)
                ld    b,a
                ld    a,(click_row)
                cp    b
                jr    nz,fl_setdc
                call  launch_row
                call  fm_draw
                jp    fm_reset
fl_setdc
                ld    a,(click_row)
                ld    (dc_idx),a
                ld    a,DCLICK
                ld    (dc_timer),a
                call  GB_CURSHOW
                jp    fm_loop
fl_grab
                call  win_grab
                jp    fm_loop
fm_done
                ret

; --- window drag ---------------------------------------------------------
win_grab
                ld    a,(cur_col)            ; grab offset within the window
                ld    hl,win_x
                sub   (hl)
                ld    (grab_dx),a
                ld    a,(cur_line)
                ld    hl,win_y
                sub   (hl)
                ld    (grab_dy),a
                ld    a,(win_x)
                ld    (out_x),a
                ld    a,(win_y)
                ld    (out_y),a
                call  GB_CURHIDE
                call  draw_xorframe          ; rubber-band over the window
                call  GB_CURSHOW
                ld    a,1
                ld    (win_dragging),a
                ret

win_dragmove
                ld    a,(cur_col)            ; new x = cursor - grab, clamped
                ld    hl,grab_dx
                sub   (hl)
                jr    nc,wm_xp
                xor   a
wm_xp
                cp    WXMAX+1
                jr    c,wm_xok
                ld    a,WXMAX
wm_xok
                ld    (new_x),a
                ld    a,(cur_line)
                ld    hl,grab_dy
                sub   (hl)
                jr    nc,wm_yp
                xor   a
wm_yp
                cp    WYMIN
                jr    nc,wm_ylo
                ld    a,WYMIN
wm_ylo
                cp    WYMAX+1
                jr    c,wm_yok
                ld    a,WYMAX
wm_yok
                ld    (new_y),a
                ld    a,(new_x)             ; moved?
                ld    hl,out_x
                cp    (hl)
                jr    nz,wm_go
                ld    a,(new_y)
                ld    hl,out_y
                cp    (hl)
                ret   z
wm_go
                call  GB_CURHIDE
                call  draw_xorframe          ; erase old outline (XOR is reversible)
                ld    a,(new_x)
                ld    (out_x),a
                ld    a,(new_y)
                ld    (out_y),a
                call  draw_xorframe          ; draw new outline
                jp    GB_CURSHOW

win_drop
                call  GB_CURHIDE
                call  draw_xorframe          ; erase the outline
                call  fm_restorereg          ; reveal the desktop at the old spot
                ld    a,(out_x)
                ld    (win_x),a
                ld    a,(out_y)
                ld    (win_y),a
                call  fm_savereg             ; save the desktop behind the new spot
                xor   a
                ld    (win_dragging),a
                jp    fm_draw

draw_xorframe
                ld    a,(out_x)
                ld    b,a
                ld    a,(out_y)
                ld    c,a
                ld    d,WIN_W
                ld    e,WIN_H
                jp    GB_XORFRAME

fm_savereg
                ld    a,(win_x)
                ld    b,a
                ld    a,(win_y)
                ld    c,a
                ld    d,WIN_W
                ld    e,WIN_H
                ld    hl,win_buf
                jp    GB_SAVERECT
fm_restorereg
                ld    a,(win_x)
                ld    b,a
                ld    a,(win_y)
                ld    c,a
                ld    d,WIN_W
                ld    e,WIN_H
                ld    hl,win_buf
                jp    GB_RESTORERECT

; --- draw the window + list, pointer on top ------------------------------
fm_draw
                ld    a,(win_x)
                ld    b,a
                ld    a,(win_y)
                ld    c,a
                ld    d,WIN_W
                ld    e,WIN_H
                ld    hl,win_title
                call  GB_WINDOW
                xor   a
                ld    (n_entries),a
                ld    a,(win_y)
                add   a,ROW_OFF
                ld    (row_y),a
                call  GB_DIR1
                jr    nc,fd_done
fd_loop
                push  hl
                ld    a,(win_x)
                add   a,2
                ld    b,a
                ld    a,(row_y)
                ld    c,a
                call  GB_BLITE
                ld    a,(win_x)
                add   a,11
                ld    b,a
                ld    a,(row_y)
                add   a,5
                ld    c,a
                ld    d,1
                ld    e,0
                pop   hl
                call  GB_TEXT
                ld    hl,n_entries
                inc   (hl)
                ld    a,(row_y)
                add   a,ROW_PITCH
                ld    (row_y),a
                ld    a,(win_y)
                add   a,WIN_H-20
                ld    b,a
                ld    a,(row_y)
                cp    b
                jr    nc,fd_done
                call  GB_DIRN
                jr    c,fd_loop
fd_done
                ld    a,NONE
                ld    (sel_row),a
                jp    GB_CURSHOW

; --- selection -----------------------------------------------------------
select_row
                ld    a,(sel_row)
                cp    NONE
                jr    z,sr_draw
                ld    b,a
                ld    a,(click_row)
                cp    b
                ret   z
                ld    a,b
                call  row_frame_y
                xor   a
                call  draw_frame
sr_draw
                ld    a,(click_row)
                call  row_frame_y
                ld    a,3
                call  draw_frame
                ld    a,(click_row)
                ld    (sel_row),a
                ret
row_frame_y
                ld    b,a
                add   a,a
                ld    c,a
                ld    a,b
                add   a,a
                add   a,a
                add   a,a
                add   a,a
                add   a,c                     ; row*18
                ld    b,a
                ld    a,(win_y)
                add   a,ROW_OFF-1
                add   a,b
                ld    (frame_y),a
                ret
draw_frame
                ld    (df_pen),a
                ld    a,(win_x)
                inc   a
                ld    b,a
                ld    a,(frame_y)
                ld    c,a
                ld    d,WIN_W-2
                ld    e,17
                ld    a,(df_pen)
                jp    GB_FRAME

; --- hit tests -----------------------------------------------------------
hit_close                                      ; CF if over the close gadget
                ld    a,(cur_col)
                ld    hl,win_x
                cp    (hl)
                jr    c,h_no
                ld    a,(win_x)
                add   a,4
                ld    b,a
                ld    a,(cur_col)
                cp    b
                jr    nc,h_no
                jr    in_titleband
hit_title                                      ; CF if over the title bar (not close)
                ld    a,(win_x)
                add   a,4
                ld    b,a
                ld    a,(cur_col)
                cp    b
                jr    c,h_no
                ld    a,(win_x)
                add   a,WIN_W
                ld    b,a
                ld    a,(cur_col)
                cp    b
                jr    nc,h_no
in_titleband
                ld    a,(cur_line)
                ld    hl,win_y
                cp    (hl)
                jr    c,h_no
                ld    a,(win_y)
                add   a,14
                ld    b,a
                ld    a,(cur_line)
                cp    b
                jr    nc,h_no
                scf
                ret
h_no
                or    a
                ret
hit_row                                        ; CF set + click_row if over a row
                ld    a,(win_y)
                add   a,ROW_OFF
                ld    b,a
                ld    a,(cur_line)
                sub   b
                jr    c,h_no
                ld    e,0
hr_div
                cp    ROW_PITCH
                jr    c,hr_done
                sub   ROW_PITCH
                inc   e
                jr    hr_div
hr_done
                ld    a,(n_entries)
                cp    e
                jr    c,h_no
                jr    z,h_no
                ld    a,e
                ld    (click_row),a
                scf
                ret

; --- launch ---------------------------------------------------------------
launch_row
                call  GB_DIR1
                ld    a,(click_row)
                or    a
                jr    z,lr_go
                ld    b,a
lr_loop
                push  bc
                call  GB_DIRN
                pop   bc
                djnz  lr_loop
lr_go
                jp    GB_LAUNCH

; --- data ----------------------------------------------------------------
win_title       db    "DISK A",0
win_x           db    4
win_y           db    26
row_y           db    0
n_entries       db    0
sel_row         db    0
click_row       db    0
dc_timer        db    0
dc_idx          db    0
frame_y         db    0
df_pen          db    0
cur_col         db    0
cur_line        db    0
poll_flags      db    0
held_now        db    0
held_prev       db    0
win_dragging    db    0
grab_dx         db    0
grab_dy         db    0
out_x           db    0
out_y           db    0
new_x           db    0
new_y           db    0
win_buf         defs  WIN_W*WIN_H
app_end
                save  "build/FILEMGR.RAW",APP_BASE,app_end-APP_BASE
