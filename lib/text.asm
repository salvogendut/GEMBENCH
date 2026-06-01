; ---------------------------------------------------------------------------
; lib/text.asm - draw 8x8 bitmap-font text straight to screen (Mode 1).
;
; Independent of the firmware text VDU, so text can sit at any byte column and
; any layout (windows, overscan). Glyphs come from lib/font.asm.
;
; A glyph row is 8 mono pixels = 2 Mode 1 bytes. For a nibble of 4 pixels,
; the Mode 1 byte is  (penbyte AND e) OR (paperbyte AND NOT e)  where e is the
; nibble "doubled" into both Mode 1 bit planes: e = (n<<4)|n. penbyte/paperbyte
; are the solid-pen Mode 1 bytes for the current pen/paper.
;
; Requires lib/screen.asm (scr_addr) and lib/font.asm. Assembled in; no org.
;
; Interface:
;   B = pen, C = paper : set_text_pens          (call before drawing)
;   A = char, tc_x = byte col, tc_y = line : draw_char
;   HL = string (0-term), tc_x/tc_y set : draw_text   (advances tc_x by 2/char)
; ---------------------------------------------------------------------------

; set_text_pens: B = pen, C = paper -> cache the solid Mode 1 bytes.
set_text_pens
                ld    a,b
                call  pen_to_byte
                ld    (txt_penb),a
                ld    a,c
                call  pen_to_byte
                ld    (txt_paperb),a
                ret

; pen_to_byte: A = pen (0..3) -> A = Mode 1 byte of 4 pixels all that pen.
pen_to_byte
                ld    e,0
                bit   0,a
                jr    z,ptb1
                ld    e,#F0
ptb1
                bit   1,a
                jr    z,ptb2
                ld    a,e
                or    #0F
                ld    e,a
ptb2
                ld    a,e
                ret

; draw_text: HL = 0-terminated string. Draws each char, advancing tc_x by 2.
draw_text
                ld    a,(hl)
                or    a
                ret   z
                push  hl
                call  draw_char
                pop   hl
                inc   hl
                ld    a,(tc_x)
                add   a,2
                ld    (tc_x),a
                jr    draw_text

; draw_char: A = char, at (tc_x, tc_y) in the current pen/paper.
draw_char
                sub   FONT_FIRST             ; glyph = font_data + (char-32)*8
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    de,font_data
                add   hl,de
                ld    (dc_gp),hl
                ld    a,8
                ld    (dc_rows),a
                ld    a,(tc_y)
                ld    (dc_y),a
dc_row
                ld    hl,(dc_gp)            ; A = next glyph row byte
                ld    a,(hl)
                inc   hl
                ld    (dc_gp),hl
                ld    (dc_glyph),a

                rrca                          ; left byte: e = (g & #F0) | (g >> 4)
                rrca
                rrca
                rrca
                and   #0F
                ld    c,a
                ld    a,(dc_glyph)
                and   #F0
                or    c
                call  blend
                ld    (dc_left),a

                ld    a,(dc_glyph)           ; right byte: e = (lo << 4) | lo
                and   #0F
                ld    c,a
                add   a,a
                add   a,a
                add   a,a
                add   a,a
                or    c
                call  blend
                ld    (dc_right),a

                ld    a,(tc_x)               ; write the two bytes to screen
                ld    d,a
                ld    a,(dc_y)
                ld    e,a
                call  scr_addr
                ld    a,(dc_left)
                ld    (hl),a
                inc   hl
                ld    a,(dc_right)
                ld    (hl),a

                ld    a,(dc_y)
                inc   a
                ld    (dc_y),a
                ld    a,(dc_rows)
                dec   a
                ld    (dc_rows),a
                jr    nz,dc_row
                ret

; blend: A = expand mask -> A = (penbyte AND mask) OR (paperbyte AND NOT mask).
blend
                ld    c,a
                ld    a,(txt_penb)
                and   c
                ld    b,a
                ld    a,c
                cpl
                ld    c,a
                ld    a,(txt_paperb)
                and   c
                or    b
                ret

; --- State ---------------------------------------------------------------
tc_x            db    0            ; text byte column
tc_y            db    0            ; text top line
txt_penb        db    0
txt_paperb      db    0
dc_gp           dw    0
dc_rows         db    0
dc_y            db    0
dc_glyph        db    0
dc_left         db    0
dc_right        db    0
