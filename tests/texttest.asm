; ---------------------------------------------------------------------------
; texttest - validate lib/text.asm (direct bitmap-font text).
;
; Draws strings in several pen/paper combinations at byte-column positions.
; PASS: readable text, correct colours, correct positions.
;
; Build: rasm tests/texttest.asm -eo   (-> build/texttest.dsk, TEXTTEST.BIN)
; ---------------------------------------------------------------------------

                include "../lib/firmware.inc"

                org   #4000
texttest
                jp    start
                include "../lib/screen.asm"
                include "../lib/font.asm"
                include "../lib/text.asm"

start
                ld    a,1
                call  SCR_SET_MODE
                call  TXT_CUR_DISABLE
                call  set_palette

                ld    b,1                     ; white on blue
                ld    c,0
                call  set_text_pens
                ld    a,4
                ld    (tc_x),a
                ld    a,20
                ld    (tc_y),a
                ld    hl,s1
                call  draw_text

                ld    b,2                     ; black on white
                ld    c,1
                call  set_text_pens
                ld    a,4
                ld    (tc_x),a
                ld    a,40
                ld    (tc_y),a
                ld    hl,s2
                call  draw_text

                ld    b,3                     ; red on blue
                ld    c,0
                call  set_text_pens
                ld    a,4
                ld    (tc_x),a
                ld    a,60
                ld    (tc_y),a
                ld    hl,s3
                call  draw_text
idle            jr    idle

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

s1              db    "GEOBENCH bitmap font!",0
s2              db    "Black on white 0123456789",0
s3              db    "The quick brown fox.",0

end
                save  "TEXTTEST.BIN",texttest,end-texttest,DSK,"build/texttest.dsk"
