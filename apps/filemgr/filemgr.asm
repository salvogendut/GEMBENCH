; filemgr - the GEOBENCH file manager (a separate banked app).
;
; Opens a window via the kernel and lists the active drive's directory: a
; half-height type icon + the (name-only) filename per entry. The pointer +
; input come from the kernel (GB_CURSHOW/GB_POLL); a click selects a row (red
; frame), a double-click "opens" it (stub: shows OPEN <name> at the foot of the
; window - real app launch lands once the apps + write layer exist).

                include "../../lib/gbapp.inc"

ROW_Y0          equ   44           ; first row line (below the title bar)
ROW_PITCH       equ   18           ; row pitch (16px icon band + 2px gap)
ROW_MAXY        equ   150          ; stop adding rows past here
STATUS_Y        equ   158          ; "OPEN <name>" status line
DCLICK          equ   40           ; double-click window (frames ~0.8s)
NONE            equ   #FF

                org   APP_BASE
app_entry
                ld    b,4                     ; window at (4,26), 56x150
                ld    c,26
                ld    d,56
                ld    e,150
                ld    hl,win_title
                call  GB_WINDOW

                xor   a                        ; build the list, counting rows
                ld    (n_entries),a
                ld    a,ROW_Y0
                ld    (row_y),a
                call  GB_DIR1                ; HL -> name; CF set if present
                jr    nc,list_done
list_loop
                push  hl                       ; HL = entry name
                ld    a,(row_y)               ; type icon at (col 6, line)
                ld    c,a
                ld    b,6
                call  GB_BLITE
                ld    a,(row_y)               ; name to the right, centred
                add   a,5
                ld    c,a
                ld    b,15
                ld    d,1
                ld    e,0
                pop   hl
                call  GB_TEXT
                ld    hl,n_entries
                inc   (hl)
                ld    a,(row_y)
                add   a,ROW_PITCH
                ld    (row_y),a
                cp    ROW_MAXY
                jr    nc,list_done
                call  GB_DIRN
                jr    c,list_loop
list_done
                call  GB_CURSHOW             ; pointer on top
                ld    a,NONE
                ld    (sel_row),a
                xor   a
                ld    (dc_timer),a

; --- event loop ----------------------------------------------------------
ev_loop
                call  GB_POLL                ; B=col, C=line, D=flags
                ld    a,(dc_timer)           ; count down the double-click window
                or    a
                jr    z,ev_flags
                dec   a
                ld    (dc_timer),a
ev_flags
                bit   1,d                     ; ESC -> quit
                jp    nz,app_done
                bit   0,d                     ; fresh click?
                jr    z,ev_loop

                ld    a,b                     ; close gadget? cols [4,8) lines [26,40)
                cp    4
                jr    c,ev_row
                cp    8
                jr    nc,ev_row
                ld    a,c
                cp    26
                jr    c,ev_row
                cp    40
                jr    nc,ev_row
                jp    app_done
ev_row
                ld    a,c                     ; row = (line - ROW_Y0) / ROW_PITCH
                sub   ROW_Y0
                jr    c,ev_loop
                ld    e,0
ev_rdiv
                cp    ROW_PITCH
                jr    c,ev_rdone
                sub   ROW_PITCH
                inc   e
                jr    ev_rdiv
ev_rdone
                ld    a,(n_entries)          ; row < n_entries ?
                cp    e
                jr    c,ev_loop
                jr    z,ev_loop
                ld    a,e
                ld    (click_row),a
                call  select_row             ; highlight it

                ld    a,(dc_timer)           ; double-click = same row, timer live
                or    a
                jr    z,ev_firstclick
                ld    a,(dc_row)
                ld    b,a
                ld    a,(click_row)
                cp    b
                jr    nz,ev_firstclick
                call  dispatch_row           ; second click -> open
                xor   a
                ld    (dc_timer),a
                jp    ev_loop
ev_firstclick
                ld    a,(click_row)
                ld    (dc_row),a
                ld    a,DCLICK
                ld    (dc_timer),a
                jp    ev_loop
app_done
                ret                            ; back to the desktop kernel

; --- selection -----------------------------------------------------------
; select_row: frame click_row in red; erase the previous selection's frame.
select_row
                ld    a,(sel_row)
                cp    NONE
                jr    z,sr_draw
                ld    b,a                     ; same row already selected?
                ld    a,(click_row)
                cp    b
                ret   z
                ld    a,b                     ; erase old frame (pen 0)
                call  row_frame_y
                xor   a
                call  draw_frame
sr_draw
                ld    a,(click_row)
                call  row_frame_y
                ld    a,3                     ; pen 3 (red accent)
                call  draw_frame
                ld    a,(click_row)
                ld    (sel_row),a
                ret

; row_frame_y: A = row -> frame_y = ROW_Y0 + row*ROW_PITCH - 1.
row_frame_y
                ld    b,a
                add   a,a                     ; row*2
                ld    c,a
                ld    a,b
                add   a,a
                add   a,a
                add   a,a
                add   a,a                     ; row*16
                add   a,c                     ; row*18
                add   a,ROW_Y0-1
                ld    (frame_y),a
                ret

; draw_frame: A = pen -> frame around the interior at frame_y.
draw_frame
                ld    (df_pen),a
                ld    b,5                     ; x (window interior left)
                ld    a,(frame_y)
                ld    c,a
                ld    d,54                     ; w (interior width)
                ld    e,17                     ; h (~ row pitch)
                ld    a,(df_pen)
                jp    GB_FRAME

; --- dispatch (stub) -----------------------------------------------------
; dispatch_row: re-enumerate to click_row, show "OPEN <name>" at the foot.
dispatch_row
                ld    hl,status_clr          ; wipe the status line
                ld    b,3
                ld    c,STATUS_Y
                ld    d,1
                ld    e,0
                call  GB_TEXT
                call  GB_DIR1                ; walk to the clicked entry
                ld    a,(click_row)
                or    a
                jr    z,dr_have
                ld    b,a
dr_loop
                push  bc
                call  GB_DIRN
                pop   bc
                djnz  dr_loop
dr_have
                push  hl                       ; HL = entry name
                ld    hl,open_msg
                ld    b,3
                ld    c,STATUS_Y
                ld    d,1
                ld    e,0
                call  GB_TEXT
                pop   hl
                ld    b,12
                ld    c,STATUS_Y
                ld    d,1
                ld    e,0
                jp    GB_TEXT

win_title       db    "DISK A",0
open_msg        db    "OPEN",0
status_clr      db    "                   ",0
row_y           db    0
n_entries       db    0
sel_row         db    0
click_row       db    0
dc_timer        db    0
dc_row          db    0
frame_y         db    0
df_pen          db    0
app_end
                save  "build/FILEMGR.RAW",APP_BASE,app_end-APP_BASE
