; ---------------------------------------------------------------------------
; scrtest - validate lib/screen.asm (direct-memory blit) in isolation.
;
; Sets Mode 1, then blits a 4-band test bitmap straight to screen RAM:
;   band 0 (rows 0-3)   pen 1 (white)   bytes #F0
;   band 1 (rows 4-7)   pen 2 (black)   bytes #0F
;   band 2 (rows 8-11)  pen 3 (red)     bytes #FF
;   band 3 (rows 12-15) pen1/pen2 vertical stripes  bytes #A5
;
; If the bands appear at the right place, right size and right colours, the
; screen-address maths and the pixel encoding are both correct.
;
; Build: rasm tests/scrtest.asm -eo   (-> build/scrtest.dsk, SCRTEST.BIN)
; Run:   ../1984/1984 --6128 --disk-a=build/scrtest.dsk --autostart=SCRTEST
; ---------------------------------------------------------------------------

                include "../lib/firmware.inc"

                org   #4000
scrtest
                jp    start
                include "../lib/screen.asm"

INK_DESKTOP     equ   1            ; blue
INK_LIGHT       equ   26           ; white
INK_DARK        equ   0            ; black
INK_ACCENT      equ   6            ; red

start
                ld    a,1
                call  SCR_SET_MODE
                call  TXT_CUR_DISABLE
                call  set_palette

                ld    hl,test_bmp            ; blit the test bitmap at (20,80)
                ld    (bm_src),hl
                ld    a,20
                ld    (bm_x),a
                ld    a,80
                ld    (bm_y),a
                ld    a,8
                ld    (bm_w),a
                ld    a,16
                ld    (bm_h),a
                call  blit_bitmap
idle            jr    idle

set_palette
                ld    a,0
                ld    b,INK_DESKTOP
                ld    c,INK_DESKTOP
                call  SCR_SET_INK
                ld    a,1
                ld    b,INK_LIGHT
                ld    c,INK_LIGHT
                call  SCR_SET_INK
                ld    a,2
                ld    b,INK_DARK
                ld    c,INK_DARK
                call  SCR_SET_INK
                ld    a,3
                ld    b,INK_ACCENT
                ld    c,INK_ACCENT
                call  SCR_SET_INK
                ld    b,INK_DESKTOP
                ld    c,INK_DESKTOP
                call  SCR_SET_BORDER
                ret

; 8 bytes wide x 16 rows, already Mode-1 encoded.
test_bmp
                db    #F0,#F0,#F0,#F0,#F0,#F0,#F0,#F0   ; pen 1
                db    #F0,#F0,#F0,#F0,#F0,#F0,#F0,#F0
                db    #F0,#F0,#F0,#F0,#F0,#F0,#F0,#F0
                db    #F0,#F0,#F0,#F0,#F0,#F0,#F0,#F0
                db    #0F,#0F,#0F,#0F,#0F,#0F,#0F,#0F   ; pen 2
                db    #0F,#0F,#0F,#0F,#0F,#0F,#0F,#0F
                db    #0F,#0F,#0F,#0F,#0F,#0F,#0F,#0F
                db    #0F,#0F,#0F,#0F,#0F,#0F,#0F,#0F
                db    #FF,#FF,#FF,#FF,#FF,#FF,#FF,#FF   ; pen 3
                db    #FF,#FF,#FF,#FF,#FF,#FF,#FF,#FF
                db    #FF,#FF,#FF,#FF,#FF,#FF,#FF,#FF
                db    #FF,#FF,#FF,#FF,#FF,#FF,#FF,#FF
                db    #A5,#A5,#A5,#A5,#A5,#A5,#A5,#A5   ; pen1/pen2 stripes
                db    #A5,#A5,#A5,#A5,#A5,#A5,#A5,#A5
                db    #A5,#A5,#A5,#A5,#A5,#A5,#A5,#A5
                db    #A5,#A5,#A5,#A5,#A5,#A5,#A5,#A5

end
                save  "SCRTEST.BIN",scrtest,end-scrtest,DSK,"build/scrtest.dsk"
