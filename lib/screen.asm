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
                ld    a,(bm_x)               ; cull if fully outside the clip rect, so
                ld    b,a                     ; an icon under a higher window is not drawn
                ld    a,(bm_y)               ; over it during a partial repaint
                ld    c,a
                ld    a,(bm_w)
                ld    d,a
                ld    a,(bm_h)
                ld    e,a
                call  rect_cull
                ret   c
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
                ld    a,(bm_keep)            ; C = keep-mask: #FF lets the backdrop show through
                ld    c,a                      ; an icon's pen-0 pixels (desktop, #128); #00 = opaque
                ld    a,(bm_w)
                ld    (bl_cnt),a
                ; Composite one row. mask has BOTH Mode-1 bit planes set for every non-pen-0
                ; pixel; screen = (screen AND (~mask AND keep)) OR icon. keep=#00 makes this a
                ; plain opaque copy (so the File Manager etc. are unchanged, #182).
bl_byte
                ld    a,(hl)                  ; icon byte: bit1 plane (low nibble)
                and   #0F
                ld    b,a
                ld    a,(hl)                  ; re-read: bit0 plane (high nibble -> low)
                rrca
                rrca
                rrca
                rrca
                and   #0F
                or    b                        ; per-pixel opaque (low nibble)
                ld    b,a
                rlca
                rlca
                rlca
                rlca                           ; opaque << 4 (high nibble)
                or    b                        ; mask = both planes set where opaque
                cpl                            ; ~mask
                and   c                        ; & keep-mask (transparent only on the desktop)
                ld    b,a
                ld    a,(de)                  ; screen byte
                and   b                        ; keep background where kept-transparent
                or    (hl)                     ; add the icon's opaque pixels
                ld    (de),a
                inc   hl
                inc   de
                ld    a,(bl_cnt)
                dec   a
                ld    (bl_cnt),a
                jr    nz,bl_byte
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
; fill_block: fill an fb_w x fb_h byte rectangle at (fb_x, fb_y) with fb_val.
; (fb_val is a Mode 1 byte: #00 blue, #F0 white, #0F black, #FF red.)
fill_block
                call  clip_fb_copy           ; fbw_* = fb_* clipped to the clip rect
                ret   c                        ; fully outside -> nothing to fill
                ld    a,(fbw_h)
                ld    (fb_rows),a
                ld    a,(fbw_y)
                ld    (fb_cy),a
fbk_loop
                ld    a,(fbw_x)
                ld    d,a
                ld    a,(fb_cy)
                ld    e,a
                call  scr_addr
                ld    a,(fbw_w)
                ld    b,a
                ld    a,(fb_val)
                ld    c,a
fbk_row
                ld    (hl),c
                inc   hl
                djnz  fbk_row
                ld    a,(fb_cy)
                inc   a
                ld    (fb_cy),a
                ld    a,(fb_rows)
                dec   a
                ld    (fb_rows),a
                jr    nz,fbk_loop
                ret

                if BACKDROP_TILE
; fill_pattern: like fill_block, but fills with the 16x16 backdrop tile at BD_TILE
; (16 rows x 4 Mode-1 bytes) instead of a constant, phased off ABSOLUTE screen x,y so
; adjacent fills line up (the desktop backdrop + every WM damage-repair use it). The
; tile byte for screen (x,y) is BD_TILE[(y & 15)*4 + (x & 3)]. Same clip as fill_block.
fill_pattern
                call  clip_fb_copy           ; fbw_* = fb_* clipped to the clip rect
                ret   c                        ; fully outside -> nothing to fill
                ld    a,(fbw_h)
                ld    (fb_rows),a
                ld    a,(fbw_y)
                ld    (fb_cy),a
fp_row
                ; tile offset = (fb_cy & 15)*4 + (fbw_x & 3); saved across scr_addr.
                ld    a,(fb_cy)
                and   15
                add   a,a
                add   a,a
                ld    c,a
                ld    a,(fbw_x)
                and   3
                add   a,c
                ld    (fp_off),a
                ld    a,(fbw_x)              ; HL = screen addr for (fbw_x, fb_cy)
                ld    d,a
                ld    a,(fb_cy)
                ld    e,a
                call  scr_addr
                ; DE = tile byte ptr = BD_TILE + offset. The row base (BD_TILE 4-aligned +
                ; a *4 offset) has low 2 bits 0, and a tile row never crosses a 256-byte
                ; page, so the column phase wraps by masking E's low 2 bits.
                ld    a,(fp_off)
                ld    e,a
                ld    d,0
                push  hl
                ld    hl,BD_TILE
                add   hl,de
                ld    d,h
                ld    e,l                      ; DE = tile ptr
                pop   hl                       ; HL = screen
                ld    a,(fbw_w)
                ld    b,a                      ; B = byte count
fp_col
                ld    a,(de)                  ; tile byte -> screen byte
                ld    (hl),a
                inc   hl
                inc   e                        ; advance the tile ptr; wrap every 4 bytes
                ld    a,e
                and   3
                jr    nz,fp_nw
                dec   e
                dec   e
                dec   e
                dec   e                        ; back to the start of this 4-byte tile row
fp_nw
                djnz  fp_col
                ld    a,(fb_cy)
                inc   a
                ld    (fb_cy),a
                ld    a,(fb_rows)
                dec   a
                ld    (fb_rows),a
                jr    nz,fp_row
                ret
                endif
fp_off          defb  0                        ; tile offset for the current row (scratch)

                include "screen_clip.asm"    ; clip_fb_copy + rect_cull (shared with lib/msx/, #287)

; ---------------------------------------------------------------------------
; save_block / restore_block: copy a sb_w x sb_h byte rectangle at (sb_x, sb_y)
; between the screen and a RAM buffer (sb_buf) - the basis for cursor/sprite
; save-under.
;
; READING screen RAM is shadowed by the upper ROM at #C000, so save_block pages
; the upper ROM out around the reads (DI + Gate Array ROM/mode register: #8D =
; mode 1, upper ROM off + lower ROM off; #85 = mode 1, upper ROM on + lower ROM
; off). WRITING always reaches RAM, so restore_block needs none of that.
;
; The ROM/mode byte MUST keep the lower ROM OFF (bit2 set) - GEOBENCH runs with
; low RAM visible at #0000-#3FFF (cursor sprite at CUR_LOW=#1500, FAT scratch,
; etc.). The old #89/#81 cleared bit2, paging the firmware LOWER ROM over that
; low RAM (the #152 "#7F81 also enabled the lower ROM" gotcha). It was usually
; masked because a deferred interrupt fired after EI and reset the banking before
; the caller read low RAM - but a SHORT save_block (a bottom-clipped cursor, just
; 1-2 rows) finishes too fast for that, so the composite then read firmware bytes
; as the sprite = garbage on the pointer's top rows near the screen bottom.

save_block
                di
                ld    bc,#7F8D               ; upper ROM off + lower ROM off (mode 1)
                out   (c),c
                ld    a,(sb_h)
                ld    (sb_rows),a
                ld    a,(sb_y)
                ld    (sb_cy),a
                ld    hl,(sb_buf)
                ld    (sb_ptr),hl
sv_loop
                ld    a,(sb_x)
                ld    d,a
                ld    a,(sb_cy)
                ld    e,a
                call  scr_addr               ; HL = screen (source)
                ld    de,(sb_ptr)            ; DE = buffer (dest)
                ld    a,(sb_w)
                ld    c,a
                ld    b,0
                ldir
                ld    (sb_ptr),de
                ld    a,(sb_cy)
                inc   a
                ld    (sb_cy),a
                ld    a,(sb_rows)
                dec   a
                ld    (sb_rows),a
                jr    nz,sv_loop
                ld    bc,#7F85               ; upper ROM back on (lower ROM stays off)
                out   (c),c
                ei
                ret

restore_block
                ld    a,(sb_h)
                ld    (sb_rows),a
                ld    a,(sb_y)
                ld    (sb_cy),a
                ld    hl,(sb_buf)
                ld    (sb_ptr),hl
rs_loop2
                ld    a,(sb_x)
                ld    d,a
                ld    a,(sb_cy)
                ld    e,a
                call  scr_addr               ; HL = screen (dest)
                ld    d,h
                ld    e,l                     ; DE = screen
                ld    hl,(sb_ptr)            ; HL = buffer (source)
                ld    a,(sb_w)
                ld    c,a
                ld    b,0
                ldir
                ld    (sb_ptr),hl
                ld    a,(sb_cy)
                inc   a
                ld    (sb_cy),a
                ld    a,(sb_rows)
                dec   a
                ld    (sb_rows),a
                jr    nz,rs_loop2
                ret

; ---------------------------------------------------------------------------
; (y >> 3) * 80 for char rows 0..24.
row80
                dw    0,80,160,240,320,400,480,560,640,720,800,880,960
                dw    1040,1120,1200,1280,1360,1440,1520,1600,1680,1760,1840,1920

; --- Blit parameters / scratch -------------------------------------------
; #196: relocated to the low-RAM scratch pool (#14A4..) - all write-before-read per
; blit, label-accessed only, so they cost 0 resident image bytes (see gbkern.asm:153).
bm_src          equ   #14A4        ; source bitmap pointer (advanced by blit)
bm_x            equ   #14A6        ; destination x in bytes (0..79)
bm_y            equ   #14A7        ; destination y (0..199)
bm_w            equ   #14A8        ; width in bytes
bm_h            equ   #14A9        ; height in rows
bl_rows         equ   #14AA
bl_y            equ   #14AB
bl_cnt          equ   #14AC        ; blit_bitmap column counter (transparent composite, #128)
bm_keep         equ   #14AD        ; #FF = pen-0 transparent (desktop), #00 = opaque (#182)

; --- fill_block parameters / scratch -------------------------------------
; #196: fb_x/y/w/h relocated to low RAM (#14B8..) - set before every fill (via fill_xywh
; or k_backdrop) and re-read on reuse, exactly as in resident RAM; label-accessed only.
fb_x            equ   #14B8        ; x in bytes
fb_y            equ   #14B9        ; y line
fb_w            equ   #14BA        ; width in bytes
fb_h            equ   #14BB        ; height in rows
fb_val          db    0            ; Mode 1 fill byte
fb_rows         equ   #14AE        ; #196: relocated to low RAM (fill loop scratch)
fb_cy           equ   #14AF        ; #196: relocated to low RAM

; --- clip rectangle (issue #45 phase 4) ----------------------------------
; fill_block clips its rect to this window before drawing, so a partial repaint
; (a moved/closed window's damage area) only erases inside that area - the rest of
; the screen is untouched, so unchanged windows/icons don't flicker. Default =
; whole screen (no clipping). The WM narrows it around a repaint, then resets it.
clip_x          equ   #1338        ; clip rect, byte col / line / byte-w / lines
clip_y          equ   #1339
clip_w          equ   #133A
clip_h          equ   #133B
fbw_x           equ   #14B0        ; #196: fill_block's clipped working rect, relocated to low
fbw_y           equ   #14B1        ; RAM (computed per fill from fb_* + clip; write-before-read)
fbw_w           equ   #14B2
fbw_h           equ   #14B3

; --- save_block / restore_block parameters / scratch ---------------------
sb_x            db    0            ; rectangle x in bytes
sb_y            db    0            ; rectangle y
sb_w            db    0            ; width in bytes
sb_h            db    0            ; height in rows
sb_buf          dw    0            ; RAM buffer pointer
sb_rows         equ   #14B4        ; #196: relocated to low RAM (save/restore loop scratch)
sb_cy           equ   #14B5        ; #196: relocated to low RAM
sb_ptr          equ   #14B6        ; #196: relocated to low RAM (2 bytes -> #14B6..#14B7)
