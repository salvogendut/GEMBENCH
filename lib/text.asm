; ---------------------------------------------------------------------------
; lib/text.asm - draw bitmap-font text straight to screen (Mode 1).
;
; Independent of the firmware text VDU, so text can sit at any byte column and
; any layout (windows, overscan). Glyphs come from a font set loaded at runtime
; (see kernel/gbkern.asm font_init); font_apply_header caches its geometry here.
;
; The font is fixed-width but the width need not be a whole Mode 1 byte (a 6 px
; glyph is 1.5 bytes), so each glyph row is blitted pixel-accurately: the glyph
; bits are shifted into a 16-bit register at the right sub-byte phase, then each
; touched Mode 1 byte is read-modify-written. Per pixel the value is the pen
; (glyph ink), the paper (glyph cell background) or the untouched screen (the
; pixel lies outside this glyph's width). penbyte/paperbyte are the solid Mode 1
; bytes for the current pen/paper.
;
; A glyph row byte holds the leftmost `font_w` pixels in its top bits (bit 7 =
; leftmost). Text starts at a byte column (tc_x); glyphs then advance by font_w
; pixels, so successive glyphs land at sub-byte positions.
;
; Requires lib/screen.asm (scr_addr). Assembled in; no org.
;
; Interface:
;   HL = font buffer base : font_apply_header   (after loading a font set)
;   B = pen, C = paper : set_text_pens          (call before drawing)
;   A = char, tc_x = byte col, tc_y = line : draw_char
;   HL = string (0-term), tc_x/tc_y set : draw_text  (advances tc_x past text)
; ---------------------------------------------------------------------------

; font_apply_header: HL = base of a loaded font set. Cache the geometry the
; renderer needs (glyph base, first char, width, height, coverage mask).
font_apply_header
                push  hl
                ld    de,16                  ; glyph data follows the 16-byte header
                add   hl,de
                ld    (font_glyphs),hl
                pop   hl
                push  hl
                ld    de,5
                add   hl,de
                ld    a,(hl)                 ; +5 first char code
                ld    (font_first),a
                inc   hl
                inc   hl                       ; +7 width in pixels
                ld    a,(hl)
                ld    (font_w),a
                ld    b,a                     ; covmask = #FF << (8 - width)
                ld    a,8
                sub   b
                ld    b,a
                ld    a,#FF
                inc   b
fah_cm
                dec   b
                jr    z,fah_cmdone
                add   a,a
                jr    fah_cm
fah_cmdone
                ld    (font_covmask),a
                inc   hl                       ; +8 height in rows
                ld    a,(hl)
                ld    (font_h),a
                pop   hl
                ret

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

; draw_text: HL = 0-terminated string at (tc_x, tc_y). Advances a pixel cursor
; by font_w per glyph; on return tc_x is the byte column just past the text.
draw_text
                push  hl                     ; save string pointer (HL is reused)
                ld    a,(tc_x)               ; pixel cursor = tc_x * 4
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                ld    (dc_px),hl
                pop   hl
dt_loop
                ld    a,(hl)
                or    a
                jr    z,dt_end
                push  hl
                call  draw_glyph
                ld    a,(font_w)             ; advance cursor by one glyph width
                ld    e,a
                ld    d,0
                ld    hl,(dc_px)
                add   hl,de
                ld    (dc_px),hl
                pop   hl
                inc   hl
                jr    dt_loop
dt_end
                ld    hl,(dc_px)             ; tc_x = cursor / 4 (byte column)
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                ld    (tc_x),a
                ret

; draw_char: A = char, at (tc_x, tc_y) in the current pen/paper.
draw_char
                ld    c,a
                ld    a,(tc_x)               ; pixel cursor = tc_x * 4
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                ld    (dc_px),hl
                ld    a,c
                ; fall through

; draw_glyph: A = char. Draws the glyph at (dc_px pixels, tc_y line).
draw_glyph
                ld    hl,font_first          ; glyph = font_glyphs + (char-first)*h
                sub   (hl)
                ld    e,a
                ld    d,0
                ld    a,(font_h)
                ld    b,a
                ld    hl,0
dg_mul
                add   hl,de
                djnz  dg_mul
                ld    de,(font_glyphs)
                add   hl,de
                ld    (dc_gp),hl
                ld    a,(font_h)
                ld    (dc_rows),a
                ld    a,(tc_y)
                ld    (dc_y),a
dg_row
                ld    hl,(dc_gp)             ; A = next glyph row byte
                ld    a,(hl)
                inc   hl
                ld    (dc_gp),hl
                call  blit_row
                ld    a,(dc_y)
                inc   a
                ld    (dc_y),a
                ld    a,(dc_rows)
                dec   a
                ld    (dc_rows),a
                jr    nz,dg_row
                ret

; blit_row: A = glyph row byte (top font_w bits = pixels), at (dc_px, dc_y).
; Shift the glyph + coverage into 16-bit registers at the pixel phase, then
; read-modify-write each Mode 1 byte the glyph touches.
blit_row
                ld    (br_glyph),a
                ld    a,(dc_px)              ; phase = pixel & 3
                and   3
                ld    (br_phase),a
                ld    hl,(dc_px)             ; byte column = pixel / 4
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l                     ; D = byte column, E = row -> scr_addr
                ld    d,a
                ld    a,(dc_y)
                ld    e,a
                call  scr_addr
                ld    (br_sp),hl
                ld    a,(br_glyph)           ; P = glyph << 8
                ld    h,a
                ld    l,0
                ld    a,(font_covmask)       ; C = covmask << 8
                ld    d,a
                ld    e,0
                ld    a,(br_phase)           ; shift both right by phase
                or    a
                jr    z,br_shifted
                ld    b,a
br_shloop
                srl   h
                rr    l
                srl   d
                rr    e
                djnz  br_shloop
br_shifted
                ld    (br_P),hl
                ld    (br_C),de
br_byteloop
                ld    de,(br_C)             ; no coverage left -> done
                ld    a,d
                or    e
                ret   z
                ld    hl,(br_P)             ; pn = top nibble of P (bits 15..12)
                ld    a,h
                rrca
                rrca
                rrca
                rrca
                and   #0F
                ld    (br_pn),a
                ld    a,d                     ; cn = top nibble of C
                rrca
                rrca
                rrca
                rrca
                and   #0F
                ld    (br_cn),a
                call  br_emit
                ld    hl,(br_sp)             ; advance to next Mode 1 byte
                inc   hl
                ld    (br_sp),hl
                ld    hl,(br_P)             ; P <<= 4
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    (br_P),hl
                ld    hl,(br_C)             ; C <<= 4
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    (br_C),hl
                jr    br_byteloop

; br_emit: from br_pn (glyph pixels) and br_cn (coverage), build one Mode 1
; byte and merge it into the screen byte at (br_sp). Covered+ink -> pen,
; covered+blank -> paper, uncovered -> keep screen.
br_emit
                ld    a,(br_pn)             ; pen pixels = pn & cn
                ld    b,a
                ld    a,(br_cn)
                and   b
                call  br_exp
                ld    b,a
                ld    a,(txt_penb)
                and   b
                ld    (br_acc),a
                ld    a,(br_pn)             ; paper pixels = (~pn) & cn
                cpl
                and   #0F
                ld    b,a
                ld    a,(br_cn)
                and   b
                call  br_exp
                ld    b,a
                ld    a,(txt_paperb)
                and   b
                ld    c,a
                ld    a,(br_acc)
                or    c
                ld    (br_acc),a
                ld    a,(br_cn)             ; keep pixels = ~cn
                cpl
                and   #0F
                call  br_exp
                ld    b,a
                ld    hl,(br_sp)
                ld    a,(hl)
                and   b
                ld    c,a
                ld    a,(br_acc)
                or    c
                ld    (hl),a
                ret

; br_exp: A (low nibble) -> A = (n<<4)|n, the Mode 1 pixel-select mask where
; each set bit selects that pixel in both bit planes.
br_exp
                and   #0F
                ld    c,a
                add   a,a
                add   a,a
                add   a,a
                add   a,a
                or    c
                ret

; --- State ---------------------------------------------------------------
tc_x            db    0            ; text byte column (start of text)
tc_y            db    0            ; text top line
txt_penb        db    0
txt_paperb      db    0
dc_px           dw    0            ; pixel-X cursor while drawing
dc_gp           dw    0            ; current glyph row pointer
dc_rows         db    0
dc_y            db    0
br_glyph        db    0
br_phase        db    0
br_P            dw    0            ; glyph pixels, 16-bit shift register
br_C            dw    0            ; coverage mask, 16-bit shift register
br_sp           dw    0            ; screen pointer for the current byte
br_pn           db    0
br_cn           db    0
br_acc          db    0

; --- Font geometry (cached from the loaded font header) ------------------
font_glyphs     dw    0            ; glyph data base (font buffer + 16)
font_first      db    32           ; first char code
font_w          db    6            ; width in pixels
font_h          db    8            ; height in rows
font_covmask    db    #FC          ; #FF << (8 - width)
