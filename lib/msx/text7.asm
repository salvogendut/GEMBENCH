; ---------------------------------------------------------------------------
; lib/msx/text7.asm - bitmap-font text for the MSX2 Screen 7 driver.
;
; Same pipeline as lib/text.asm (the .FNT glyph format is 1bpp and platform
; neutral; the shift-register sub-byte placement is identical). What changes
; is the emission: each glyph row's touched span (up to six native bytes) is
; read from VRAM, composited with Screen 7's two 4-bit pixels per byte, and
; written back -
; one VRAM read burst + one write burst per row.
;
; Requires lib/msx/screen.asm (vdp_setrd/vdp_setwr/vdp_wait_ce, pen_to_byte,
; rect_cull). Interface identical to the CPC file: font_apply_header,
; set_text_pens, draw_char, draw_text (+ tc_x/tc_y).
; ---------------------------------------------------------------------------

; font_apply_header: HL = base of a loaded font set (identical to the CPC).
font_apply_header
                push  hl
                ld    de,16
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

; set_text_pens: B = pen, C = paper -> cache Screen-7 palette indices.
set_text_pens
                ld    a,b
                and   #0F
                ld    (txt_penb),a
                ld    a,c
                and   #0F
                ld    (txt_paperb),a
                ret

; draw_text / draw_char / draw_glyph: identical control flow to the CPC file.
draw_text
                push  hl
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
                ld    a,(font_w)
                ld    e,a
                ld    d,0
                ld    hl,(dc_px)
                add   hl,de
                ld    (dc_px),hl
                pop   hl
                inc   hl
                jr    dt_loop
dt_end
                ld    hl,(dc_px)             ; tc_x = cursor / 4
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                ld    (tc_x),a
                ret

draw_char
                ld    c,a
                ld    a,(tc_x)
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                ld    (dc_px),hl
                ld    a,c
                ; fall through

draw_glyph
                push  af
                ld    hl,(dc_px)             ; glyph byte col = dc_px / 4
                srl   h
                rr    l
                srl   h
                rr    l
                ld    b,l
                ld    a,(tc_y)
                ld    c,a
                ld    a,(font_w)
                srl   a
                srl   a
                add   a,2
                ld    d,a
                ld    a,(font_h)
                ld    e,a
                call  rect_cull
                jr    c,dg_culled
                pop   af
                ld    hl,font_first
                jr    dg_go
dg_culled       pop   af
                ret
dg_go
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
                ld    hl,(dc_gp)
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

; blit_row: A = glyph row byte at (dc_px, dc_y). Read the 6-byte VRAM span,
; run the shared shift-register composite against it, write it back.
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
                ld    a,l
                ld    (br_col),a
                call  vdp_wait_ce
                ld    a,(br_col)             ; read the native span into br_buf
                ld    d,a
                ld    a,(dc_y)
                ld    e,a
                call  vdp_setrd
                ld    hl,br_buf
                ld    b,6
                ld    c,VDP_DATA
br_rd           ini
                jr    nz,br_rd
                ld    hl,br_buf
                ld    (br_sp),hl             ; br_sp walks the scratch, not the screen
                ld    a,(br_glyph)           ; P = glyph << 8
                ld    h,a
                ld    l,0
                ld    a,(font_covmask)       ; C = covmask << 8
                ld    d,a
                ld    e,0
                ld    a,(br_phase)
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
                ld    de,(br_C)
                ld    a,d
                or    e
                jr    z,br_flush             ; no coverage left -> write the span back
                ld    hl,(br_P)
                ld    a,h
                rrca
                rrca
                rrca
                rrca
                and   #0F
                ld    (br_pn),a
                ld    a,d
                rrca
                rrca
                rrca
                rrca
                and   #0F
                ld    (br_cn),a
                call  br_emit
                ld    hl,(br_P)
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    (br_P),hl
                ld    hl,(br_C)
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    (br_C),hl
                jr    br_byteloop
br_flush
                ld    a,(br_col)             ; write the composited native span back
                ld    d,a
                ld    a,(dc_y)
                ld    e,a
                call  vdp_setwr
                ld    hl,br_buf
                ld    b,6
                ld    c,VDP_DATA
br_wr           outi
                jr    nz,br_wr
                ret

; br_emit: merge four glyph pixels into two Screen-7 bytes at (br_sp).
; Pixels outside br_cn coverage retain their full 4-bit palette indices.
br_emit
                ld    hl,(br_sp)
                ; first pair: glyph bits 3/2, coverage bits 3/2
                ld    a,(br_pn)
                bit   3,a
                jr    z,bre_p0paper
                ld    a,(txt_penb)
                jr    bre_p0
bre_p0paper     ld    a,(txt_paperb)
bre_p0          and   #0F
                rlca
                rlca
                rlca
                rlca
                ld    c,a
                ld    a,(br_pn)
                bit   2,a
                jr    z,bre_p1paper
                ld    a,(txt_penb)
                jr    bre_p1
bre_p1paper     ld    a,(txt_paperb)
bre_p1          and   #0F
                or    c
                ld    c,a
                ld    a,(br_cn)
                ld    b,0
                bit   3,a
                jr    z,bre_m1
                ld    b,#F0
bre_m1          bit   2,a
                jr    z,bre_apply1
                ld    a,b
                or    #0F
                ld    b,a
bre_apply1      ld    a,b
                cpl
                and   (hl)
                ld    d,a
                ld    a,c
                and   b
                or    d
                ld    (hl),a
                inc   hl
                ; second pair: glyph bits 1/0, coverage bits 1/0
                ld    a,(br_pn)
                bit   1,a
                jr    z,bre_p2paper
                ld    a,(txt_penb)
                jr    bre_p2
bre_p2paper     ld    a,(txt_paperb)
bre_p2          and   #0F
                rlca
                rlca
                rlca
                rlca
                ld    c,a
                ld    a,(br_pn)
                bit   0,a
                jr    z,bre_p3paper
                ld    a,(txt_penb)
                jr    bre_p3
bre_p3paper     ld    a,(txt_paperb)
bre_p3          and   #0F
                or    c
                ld    c,a
                ld    a,(br_cn)
                ld    b,0
                bit   1,a
                jr    z,bre_m3
                ld    b,#F0
bre_m3          bit   0,a
                jr    z,bre_apply2
                ld    a,b
                or    #0F
                ld    b,a
bre_apply2      ld    a,b
                cpl
                and   (hl)
                ld    d,a
                ld    a,c
                and   b
                or    d
                ld    (hl),a
                inc   hl
                ld    (br_sp),hl
                ret

; --- State (same shared low-RAM homes as the CPC renderer) -------------------
tc_x            db    0
tc_y            db    0
txt_penb        db    0
txt_paperb      db    0
dc_px           equ   #14C2
dc_gp           equ   #14C4
dc_rows         equ   #14C6
dc_y            equ   #14C7
br_glyph        equ   #14C8
br_phase        equ   #14C9
br_P            equ   #14BC
br_C            equ   #14BE
br_sp           equ   #14C0
br_pn           equ   #14CA
br_cn           equ   #14CB
br_acc          equ   #14CC        ; retained scratch address for map stability
br_col          db    0            ; byte column of the span (resident scratch)
br_buf          ds    6            ; the six-byte Screen-7 span being composited

font_glyphs     dw    0
font_first      db    32
font_w          db    6
font_h          db    8
font_covmask    db    #FC
