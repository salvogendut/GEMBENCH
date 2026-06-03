; hello - proto file manager: a separate banked app that opens a window via the
; kernel and lists the real disk directory using the kernel's services
; (GB_WINDOW, GB_DIR1/GB_DIRN, GB_TEXT). Proves window + directory + font
; services work together across the app/kernel bank boundary.

                include "../../lib/gbapp.inc"

                org   APP_BASE
app_entry
                ld    b,4                     ; window at (4,26), 56x150
                ld    c,26
                ld    d,56
                ld    e,150
                ld    hl,win_title
                call  GB_WINDOW

                ld    a,44                    ; first list line (below title bar)
                ld    (cur_y),a
                call  GB_DIR1                ; HL -> "NAME.EXT", CF set if present
                jr    nc,app_done
list_loop
                push  hl                       ; HL = entry name
                ld    b,7                     ; col
                ld    a,(cur_y)
                ld    c,a                       ; line
                ld    d,1                     ; pen 1 (white)
                ld    e,0                     ; paper 0 (blue interior)
                pop   hl
                call  GB_TEXT
                ld    a,(cur_y)               ; next row
                add   a,9
                ld    (cur_y),a
                cp    172                      ; stop near the window bottom
                jr    nc,app_done
                call  GB_DIRN
                jr    c,list_loop
app_done
                ret                            ; back to the desktop kernel

win_title       db    "DISK A",0
cur_y           db    0
app_end
                save  "build/HELLO.RAW",APP_BASE,app_end-APP_BASE
