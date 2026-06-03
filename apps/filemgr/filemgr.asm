; filemgr - the GEOBENCH file manager, a separate banked app. Opens a window
; via the kernel and lists the active drive's directory: a half-height type
; icon plus the (name-only) filename for each entry, all drawn by kernel
; services across the app/kernel bank boundary.
;
; Selection / double-click / type dispatch come once the kernel exposes input.

                include "../../lib/gbapp.inc"

                org   APP_BASE
app_entry
                ld    b,4                     ; window at (4,26), 56x150
                ld    c,26
                ld    d,56
                ld    e,150
                ld    hl,win_title
                call  GB_WINDOW

                ld    a,44                    ; first row line
                ld    (cur_y),a
                call  GB_DIR1                ; HL -> name; CF set if an entry
                jr    nc,app_done
list_loop
                push  hl                       ; save the name pointer
                ld    a,(cur_y)               ; type icon at (col 6, line)
                ld    c,a
                ld    b,6
                call  GB_BLITE
                ld    a,(cur_y)               ; name to the right, centred on the icon
                add   a,5
                ld    c,a
                ld    b,15
                ld    d,1                     ; pen 1 (white)
                ld    e,0                     ; paper 0 (blue)
                pop   hl
                call  GB_TEXT
                ld    a,(cur_y)               ; next row
                add   a,18
                ld    (cur_y),a
                cp    164                      ; stop near the window bottom
                jr    nc,list_done
                call  GB_DIRN
                jr    c,list_loop
list_done
                call  GB_CURSHOW             ; pointer on top, then poll for input
ev_loop
                call  GB_POLL                ; B=col, C=line, D=flags
                bit   1,d                     ; quit (ESC)?
                jr    nz,app_done
                bit   0,d                     ; a fresh click?
                jr    z,ev_loop
                ld    a,b                     ; close gadget hit? (title bar, left)
                cp    4
                jr    c,ev_loop
                cp    8
                jr    nc,ev_loop
                ld    a,c
                cp    26
                jr    c,ev_loop
                cp    40
                jr    nc,ev_loop
app_done
                ret                            ; back to the desktop kernel

win_title       db    "DISK A",0
cur_y           db    0
app_end
                save  "build/FILEMGR.RAW",APP_BASE,app_end-APP_BASE
