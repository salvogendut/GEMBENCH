; ---------------------------------------------------------------------------
; lib/screen.asm - GEOBENCH direct screen-memory access (Mode 1)
;
; The firmware draws one call per pixel/line, which is far too slow for real
; bitmap icons. These routines write straight to screen RAM instead, so a
; bitmap row is a byte copy rather than a string of firmware calls.
;
; CPC Mode 1 screen (default base #C000, 16 KB):
;   - 320x200, 4 pens, 2 bits per pixel, 4 pixels per byte -> 80 bytes / line.
;   - Lines are interleaved in 8 banks of #800:
;         addr = #C000 + (y AND 7)*#800 + (y >> 3)*80 + xbyte
;   - In-byte pixel encoding (pen = bit0 + 2*bit1):
;         pixel 0: bit7 = pen bit0, bit3 = pen bit1
;         pixel 1: bit6 / bit2
;         pixel 2: bit5 / bit1
;         pixel 3: bit4 / bit0
;     so a byte of one pen p:  p0->#00  p1->#F0  p2->#0F  p3->#FF
;   Bitmaps are stored already encoded in this byte format (the host tool does
;   the encoding), so blitting is a plain memory copy.
;
; Writes to #C000.. always reach screen RAM even with the upper ROM paged in,
; so blitting needs no ROM juggling. (Reading screen RAM, for save-under, will -
; that comes later.)
;
; Requires nothing. Assembled into the consumer; no org.
;
; Interface:
;   D = xbyte (0..79), E = y (0..199) : scr_addr -> HL = screen address
;   blit params in bm_src/bm_x/bm_y/bm_w/bm_h, then call blit_bitmap
; ---------------------------------------------------------------------------

SCREEN_BASE     equ   #C000

; ---------------------------------------------------------------------------
; scr_addr: D = xbyte, E = y -> HL = screen address. Clobbers A, BC.
scr_addr
                ld    a,e
                and   7
                add   a,a                    ; (y AND 7) * 8 ...
                add   a,a
                add   a,a
                or    #C0                     ; ... + base high byte (#C000 >> 8)
                ld    h,a
                ld    l,0                     ; HL = #C000 + (y AND 7)*#800
                ld    a,e
                srl   a
                srl   a
                srl   a                       ; A = y >> 3  (char row 0..24)
                add   a,a                     ; word index into row80
                ld    c,a
                ld    b,0
                push  hl
                ld    hl,row80
                add   hl,bc
                ld    c,(hl)
                inc   hl
                ld    b,(hl)                  ; BC = (y >> 3) * 80
                pop   hl
                add   hl,bc
                ld    b,0                     ; + xbyte
                ld    c,d
                add   hl,bc
                ret

; ---------------------------------------------------------------------------
; blit_bitmap: copy a bm_w x bm_h byte bitmap at (bm_x, bm_y) straight to the
; screen. bm_src points at row-major, already-encoded bytes.
blit_bitmap
                ld    a,(bm_h)
                ld    (bl_rows),a
                ld    a,(bm_y)
                ld    (bl_y),a
bl_loop
                ld    a,(bm_x)               ; dest = scr_addr(bm_x, bl_y)
                ld    d,a
                ld    a,(bl_y)
                ld    e,a
                call  scr_addr
                ld    d,h                     ; DE = dest
                ld    e,l
                ld    hl,(bm_src)            ; HL = source row
                ld    a,(bm_w)
                ld    c,a
                ld    b,0
                ldir                          ; copy one row
                ld    (bm_src),hl            ; advance source past this row
                ld    a,(bl_y)
                inc   a
                ld    (bl_y),a
                ld    a,(bl_rows)
                dec   a
                ld    (bl_rows),a
                jr    nz,bl_loop
                ret

; ---------------------------------------------------------------------------
; (y >> 3) * 80 for char rows 0..24.
row80
                dw    0,80,160,240,320,400,480,560,640,720,800,880,960
                dw    1040,1120,1200,1280,1360,1440,1520,1600,1680,1760,1840,1920

; --- Blit parameters / scratch -------------------------------------------
bm_src          dw    0            ; source bitmap pointer (advanced by blit)
bm_x            db    0            ; destination x in bytes (0..79)
bm_y            db    0            ; destination y (0..199)
bm_w            db    0            ; width in bytes
bm_h            db    0            ; height in rows
bl_rows         db    0
bl_y            db    0
