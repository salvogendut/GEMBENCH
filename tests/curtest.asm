; ---------------------------------------------------------------------------
; curtest - validate the bitmap cursor (masked sprite + save-under).
;
;   blit a floppy at (10,50) and an untouched reference at (10,96)
;   show the arrow over the top floppy, then move it twice across the floppy
;
; PASS: the arrow is drawn with transparency (no blue box around it), and the
; floppy underneath is intact wherever the arrow has been (matches reference).
;
; Build: rasm tests/curtest.asm -eo   (-> build/curtest.dsk, CURTEST.BIN)
; ---------------------------------------------------------------------------

                include "../lib/firmware.inc"

                org   #4000
curtest
                jp    start
                include "../lib/screen.asm"
                include "../lib/cursor_arrow.asm"
                include "../lib/cursor.asm"
                include "../lib/icon_floppy.asm"

start
                ld    a,1
                call  SCR_SET_MODE
                call  TXT_CUR_DISABLE
                call  set_palette

                ld    hl,icon_floppy         ; floppy at (10,50)
                ld    b,10
                ld    c,50
                call  blit_at
                ld    hl,icon_floppy         ; reference floppy at (10,96)
                ld    b,10
                ld    c,96
                call  blit_at

                ld    hl,90                  ; arrow over the floppy
                ld    (cursor_x),hl
                ld    hl,290
                ld    (cursor_y),hl
                call  cursor_show

                ld    de,110                 ; move it right (still over floppy)
                ld    hl,290
                call  cursor_move_to
                ld    de,130                 ; and again
                ld    hl,286
                call  cursor_move_to
idle            jr    idle

blit_at
                ld    (bm_src),hl
                ld    a,b
                ld    (bm_x),a
                ld    a,c
                ld    (bm_y),a
                ld    a,8
                ld    (bm_w),a
                ld    a,32
                ld    (bm_h),a
                jp    blit_bitmap

set_palette
                ld    a,0
                ld    b,1
                ld    c,1
                call  SCR_SET_INK
                ld    a,1
                ld    b,26
                ld    c,26
                call  SCR_SET_INK
                ld    a,2
                ld    b,0
                ld    c,0
                call  SCR_SET_INK
                ld    a,3
                ld    b,6
                ld    c,6
                call  SCR_SET_INK
                ld    b,1
                ld    c,1
                call  SCR_SET_BORDER
                ret

end
                save  "CURTEST.BIN",curtest,end-curtest,DSK,"build/curtest.dsk"
