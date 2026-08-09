; ---------------------------------------------------------------------------
; lib/pcw/screen.asm - GEOBENCH roller-RAM/CGA2 driver for the PCW target (#331).
;
; The PCW counterpart of lib/screen.asm / lib/msx/screen.asm: same entry
; points, same low-RAM parameter cells (bm_*, fb_*, sb_*, clip_*), so every
; caller in the shared kernel body compiles unchanged. See lib/pcw/glue.inc
; for the surface: 90 byte-cols x 248 lines, Screen-6-style 2bpp packing
; shown through the emulator's CGA2 palette, framebuffer in physical blocks
; 4-5 reached through the CPU slot-3 window.
;
;   - native icon/backdrop bitmaps stay in Screen-6-style GB pen space and are
;     permuted to CGA2 hardware pens on write. Portable .PIC payloads instead
;     stay in canonical Mode-1 packing and use restore_pic_block's lookup table
;   - fill bytes (fb_val) arrive ALREADY permuted - pen_to_byte here returns
;     hardware-space bytes, and fills write them raw
;   - save_block/restore_block round-trip raw screen (hardware-space) bytes
;   - pcw_addr maps the right framebuffer block into slot 3 per row; nothing
;     may rely on slot 3 surviving a call (input remaps it for the keyboard)
;   - runs fully DI, so the window swaps can't be interleaved
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; pcw_addr: D = xbyte, E = y -> HL = CPU address in the slot-3 window, with
; the right framebuffer block mapped. Clobbers A, BC.
;   cellrow r = y>>3: block = 4 + (r>>4), HL = #C000 + (r&15)*1024 + D*8 + (y&7)
pcw_addr
                ld    a,e
                rrca
                rrca
                rrca
                and   #1F                     ; A = cellrow 0..31
                cp    16
                ld    c,PCW_BLK_SCR0
                jr    c,pa_blk
                ld    c,PCW_BLK_SCR1
pa_blk
                ld    b,a                     ; B = cellrow
                ld    a,c
                out   (PCW_BANK3),a           ; map the framebuffer block
                ld    a,b
                and   15
                add   a,a
                add   a,a                     ; (r & 15) * 4 -> high-byte offset
                or    #C0
                ld    h,a
                ld    a,e
                and   7
                ld    l,a                     ; HL = cellrow base + line
                ld    b,0                     ; BC = xbyte * 8
                ld    c,d
                sla   c
                rl    b
                sla   c
                rl    b
                sla   c
                rl    b
                add   hl,bc
                ret

; ---------------------------------------------------------------------------
; pcw_perm: A = GB-pen-space byte -> A = CGA2 hardware-space byte.
; Per 2-bit field: hw.b1 = gb.b0, hw.b0 = NOT gb.b1 (the pen map 0->1 1->3
; 2->0 3->2). Clobbers B, C.
pcw_perm
                ld    c,a
                and   #55
                add   a,a                     ; (gb & #55) << 1
                ld    b,a
                ld    a,c
                cpl
                and   #AA
                rrca                          ; (~gb & #AA) >> 1 (bit0 is clear)
                or    b
                ret

; --- pen_to_byte: A = GB pen (0..3) -> A = solid hardware byte ---------------
; (pens 0..3 -> #55 cyan, #FF white, #00 black, #AA magenta.) Clobbers A, E
; only - the same contract as the MSX driver's pen_to_byte.
pen_to_byte
                and   3
                ld    e,a
                cpl
                and   2
                rrca                          ; A = h0 = NOT pen.b1
                srl   e                       ; CF = pen.b0
                jr    nc,ptb_h1
                or    2                       ; h1 = pen.b0
ptb_h1
                ld    e,a                     ; A = hw pen; byte = hw * #55
                add   a,a
                add   a,a
                or    e                       ; * 5 (both fields of a nibble)
                ld    e,a
                add   a,a
                add   a,a
                add   a,a
                add   a,a
                or    e                       ; * #11 -> all four 2-bit fields
                ret

; ---------------------------------------------------------------------------
; blit_bitmap: copy a bm_w x bm_h byte bitmap at (bm_x, bm_y) to the screen,
; permuting each byte. bm_src is row-major GB-pen-space (MSX-format) bytes.
; bm_keep=#FF composites transparently: GB pen-0 fields keep the background.
blit_bitmap
                ld    a,(bm_x)               ; cull if fully outside the clip rect
                ld    b,a
                ld    a,(bm_y)
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
                ld    a,(bm_x)               ; HL = screen dest (stride 8/byte)
                ld    d,a
                ld    a,(bl_y)
                ld    e,a
                call  pcw_addr
                ld    de,(bm_src)            ; DE = source row (stride 1)
                ld    a,(bm_w)
                ld    (bl_cnt),a
                ld    a,(bm_keep)            ; pick the row loop once per row
                or    a
                jr    nz,bl_tbyte
bl_obyte
                ; --- opaque: permute and write --------------------------------
                ld    a,(de)
                call  pcw_perm
                ld    (hl),a
                inc   de
                ld    bc,8                    ; x-neighbours are 8 bytes apart
                add   hl,bc
                ld    a,(bl_cnt)
                dec   a
                ld    (bl_cnt),a
                jr    nz,bl_obyte
                jr    bl_next
bl_tbyte
                ; --- transparent: GB pen-0 fields keep the background ---------
                ; mask = 11 in every non-pen-0 field of the GB-space icon byte;
                ; screen = (screen & ~mask) | (perm(icon) & mask). The mask is
                ; computed on GB bytes (pen 0 = 00) but selects 2-bit FIELDS, so
                ; it applies unchanged to the permuted hardware bytes.
                ld    a,(de)
                ld    c,a
                srl   a
                or    c
                and   #55
                ld    c,a
                add   a,a
                or    c                        ; A = opaque-field mask
                cpl                            ; A = ~mask
                ld    c,a
                ld    a,(hl)                  ; screen byte (hardware space)
                and   c                        ; A = kept background bits
                push  af
                ld    a,c
                cpl                            ; back to mask
                push  af
                ld    a,(de)
                call  pcw_perm                ; A = perm(icon); clobbers B,C
                pop   bc                       ; B = mask
                and   b                        ; icon bits in opaque fields only
                pop   bc                       ; B = kept background (pushed AF)
                or    b
                ld    (hl),a
                inc   de
                ld    bc,8
                add   hl,bc
                ld    a,(bl_cnt)
                dec   a
                ld    (bl_cnt),a
                jr    nz,bl_tbyte
bl_next
                ld    (bm_src),de            ; advance source past this row
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
; fb_val is a hardware-space byte (from pen_to_byte).
fill_block
                call  clip_fb_copy           ; fbw_* = fb_* clipped to the clip rect
                ret   c
                ld    a,(fbw_h)
                ld    (fb_rows),a
                ld    a,(fbw_y)
                ld    (fb_cy),a
fbk_loop
                ld    a,(fbw_x)
                ld    d,a
                ld    a,(fb_cy)
                ld    e,a
                call  pcw_addr
                ld    a,(fbw_w)
                ld    b,a
                ld    a,(fb_val)
                ld    c,a
                ld    de,8                    ; x-neighbours are 8 bytes apart
fbk_row
                ld    (hl),c
                add   hl,de
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
; fill_pattern: select the 16x16 backdrop tile at absolute screen phase.
fill_pattern
                ld    hl,BD_TILE
                ld    (fp_base+1),hl
                xor   a
                ld    (fp_xphase+1),a
                ld    (fp_yphase+1),a
                jr    fp_begin
                endif

                if TITLEBAR_TILE
; fill_title_pattern: select the 16x14 title tile at window-relative phase.
fill_title_pattern
                ld    hl,DATA_TITLE
                ld    (fp_base+1),hl
                ld    a,(kw_x)
                neg
                ld    (fp_xphase+1),a
                ld    a,(kw_y)
                neg
                ld    (fp_yphase+1),a
                endif

                if BACKDROP_TILE | TITLEBAR_TILE
; Common canonical tile renderer; PCW pen bytes are permuted on write.
fp_begin
                call  clip_fb_copy
                ret   c
                ld    a,(fbw_h)
                ld    (fb_rows),a
                ld    a,(fbw_y)
                ld    (fb_cy),a
fp_row
                ld    a,(fb_cy)              ; tile offset for this row
fp_yphase       add   a,0
                and   15
                add   a,a
                add   a,a
                ld    c,a
                ld    a,(fbw_x)
fp_xphase       add   a,0
                and   3
                add   a,c
                ld    (fp_off),a
                ld    a,(fbw_x)
                ld    d,a
                ld    a,(fb_cy)
                ld    e,a
                call  pcw_addr
                ld    a,(fp_off)             ; DE = tile ptr (row never crosses a page)
                ld    e,a
                ld    d,0
                push  hl
fp_base         ld    hl,BD_TILE
                add   hl,de
                ld    d,h
                ld    e,l
                pop   hl
                ld    a,(fbw_w)
                ld    (fp_cnt),a
fp_col
                ld    a,(de)                 ; tile byte -> permute -> screen
                call  pcw_perm
                ld    (hl),a
                ld    bc,8                    ; x-neighbours are 8 bytes apart
                add   hl,bc
                inc   e                       ; advance tile ptr; wrap every 4 bytes
                ld    a,e
                and   3
                jr    nz,fp_nw
                dec   e
                dec   e
                dec   e
                dec   e
fp_nw
                ld    a,(fp_cnt)
                dec   a
                ld    (fp_cnt),a
                jr    nz,fp_col
                ld    a,(fb_cy)
                inc   a
                ld    (fb_cy),a
                ld    a,(fb_rows)
                dec   a
                ld    (fb_rows),a
                jr    nz,fp_row
                ret
fp_off          db    0
fp_cnt          db    0
                endif

                include "../screen_clip.asm"  ; clip_fb_copy + rect_cull (shared)

; ---------------------------------------------------------------------------
; save_block / restore_block: copy a sb_w x sb_h byte rectangle at (sb_x, sb_y)
; between the screen and a RAM buffer (sb_buf). Raw hardware-space bytes -
; no permuting, and the buffer must NOT live in slot 3 (#C000+).
save_block
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
                call  pcw_addr               ; HL = screen (source, stride 8)
                ld    de,(sb_ptr)
                ld    a,(sb_w)
                ld    b,a
sv_row
                ld    a,(hl)
                ld    (de),a
                inc   de
                ld    a,l                     ; HL += 8 (B is the counter)
                add   a,8
                ld    l,a
                jr    nc,sv_nc
                inc   h
sv_nc
                djnz  sv_row
                ld    (sb_ptr),de
                ld    a,(sb_cy)
                inc   a
                ld    (sb_cy),a
                ld    a,(sb_rows)
                dec   a
                ld    (sb_rows),a
                jp    nz,sv_loop
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
                call  pcw_addr               ; HL = screen (dest, stride 8)
                ld    de,(sb_ptr)
                ld    a,(sb_w)
                ld    b,a
rs_row
                ld    a,(de)
                ld    (hl),a
                inc   de
                ld    a,l                     ; HL += 8 (B is the counter)
                add   a,8
                ld    l,a
                jr    nc,rs_nc
                inc   h
rs_nc
                djnz  rs_row
                ld    (sb_ptr),de
                ld    a,(sb_cy)
                inc   a
                ld    (sb_cy),a
                ld    a,(sb_rows)
                dec   a
                ld    (sb_rows),a
                jp    nz,rs_loop2
                ret

; restore_pic_block: translate canonical CPC Mode-1 picture bytes directly to
; PCW CGA2 hardware bytes while copying. The source bank remains canonical.
restore_pic_block
                ld    a,(sb_h)
                ld    (sb_rows),a
                ld    a,(sb_y)
                ld    (sb_cy),a
                ld    hl,(sb_buf)
                ld    (sb_ptr),hl
rpw_loop
                ld    a,(sb_x)
                ld    d,a
                ld    a,(sb_cy)
                ld    e,a
                call  pcw_addr
                ld    de,(sb_ptr)
                ld    a,(sb_w)
                ld    b,a
rpw_row
                ld    a,(de)
                inc   de
                ld    (rpw_lut+1),a            ; patch the aligned table's low address byte
rpw_lut         ld    a,(pic_m1_to_native)
                ld    (hl),a
                ld    a,l
                add   a,8
                ld    l,a
                jr    nc,rpw_nc
                inc   h
rpw_nc
                djnz  rpw_row
                ld    (sb_ptr),de
                ld    a,(sb_cy)
                inc   a
                ld    (sb_cy),a
                ld    a,(sb_rows)
                dec   a
                ld    (sb_rows),a
                jr    nz,rpw_loop
                ret

; --- k_cls: clear the whole desktop to pen 0 --------------------------------
k_cls
                xor   a
                call  pen_to_byte
                ld    (fb_val),a
                xor   a
                ld    (fb_x),a
                ld    (fb_y),a
                ld    a,PCW_COLS
                ld    (fb_w),a
                ld    a,PCW_LINES
                ld    (fb_h),a
                jp    fill_block

; --- set_palette: fixed CGA2 palette - nothing to program --------------------
set_palette
                ret

; ---------------------------------------------------------------------------
; pcw_video_init: build the roller table, paint the letterbox strip, clear
; the desktop, and turn the display on. Called once at boot (display starts
; disabled, so no garbage is shown while this runs).
;
; Roller word for line y: cellrow r = y>>3 lives at phys A = #10000 + r*1024,
; word = ((A'>>1) & #FFF8) | (y&7) with A' = A + (y&7). Since A is 1K-aligned:
; word = (#8000 + r*512) | (y&7)  (A>>1: bit16 -> bit15, r*1024 -> r*512).
; Lines 248-255 point at cellrow 31 (the static letterbox strip).
pcw_video_init
                ld    a,#80|1                 ; roller table lives in phys block 1,
                out   (PCW_BANK1),a           ; written through slot 1 (boot-time only:
                ld    hl,PCW_RTABLE           ; nothing else is paged this early)
                ld    de,#8000                ; cellrow 0 word base (A=#10000 -> #8000)
                ld    b,32                    ; 32 cellrows (31 = letterbox)
vi_cell
                ld    c,0                     ; line within cell
vi_line
                ld    a,e
                or    c                       ; low byte | line
                ld    (hl),a
                inc   hl
                ld    a,d
                ld    (hl),a
                inc   hl
                inc   c
                ld    a,c
                cp    8
                jr    c,vi_line
                inc   d                       ; next cellrow: word base += 512
                inc   d
                djnz  vi_cell
                ; letterbox strip: cellrow 31 = solid black (hardware pen 0)
                ld    a,PCW_BLK_SCR1
                out   (PCW_BANK3),a
                ld    hl,#C000+15*1024        ; cellrow 31 in the slot-3 window
                ld    de,720
vi_strip
                ld    (hl),0
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,vi_strip
                ; full-screen clip + clear, then enable the display
                xor   a
                ld    (clip_x),a
                ld    (clip_y),a
                ld    a,PCW_COLS
                ld    (clip_w),a
                ld    a,PCW_LINES
                ld    (clip_h),a
                call  k_cls
                ld    a,PCW_RTREG
                out   (PCW_ROLLER),a          ; roller table at phys #3E00
                xor   a
                out   (PCW_SCROLL),a          ; vertical scroll 0
                ld    a,#40
                out   (PCW_DISPCTL),a         ; screen enable, normal video
                ld    a,7
                out   (PCW_SYSCTL),a          ; display enable on
                ret


; --- k_line (GB_LINE, #331): software Bresenham through the slot-3 window ----
; Endpoints + pen come from the PCW_GLINE cells (screen pixels, top-left
; origin: x 0..359, y 0..247) - the Clock's inline asm fills them, exactly
; like the MSX GLINE_* glue. Out-of-range pixels are skipped, never plotted
; (a stray coordinate must not hang or corrupt - the CPC saver lesson).
k_line
                ld    a,(PCW_GLINE+8)         ; pen -> uniform hardware byte
                call  pen_to_byte
                ld    (kl_hwb),a
                ld    hl,(PCW_GLINE+0)
                ld    (kl_x),hl
                ld    a,(PCW_GLINE+2)
                ld    (kl_y),a
                ld    hl,(PCW_GLINE+4)
                ld    (kl_x1),hl
                ld    a,(PCW_GLINE+6)
                ld    (kl_y1),a
                ld    hl,(PCW_GLINE+4)        ; dx = |x1 - x0|, sx = direction
                ld    de,(PCW_GLINE+0)
                or    a
                sbc   hl,de
                ld    a,1
                jr    nc,kl_dxok
                ld    a,l                     ; negate HL
                cpl
                ld    l,a
                ld    a,h
                cpl
                ld    h,a
                inc   hl
                xor   a                       ; sx = 0 -> step left
kl_dxok
                ld    (kl_sx),a
                ld    (kl_dx),hl
                ld    a,(PCW_GLINE+2)         ; dy = |y1 - y0|, sy = direction
                ld    c,a
                ld    a,(PCW_GLINE+6)
                sub   c
                ld    b,1
                jr    nc,kl_dyok
                neg
                ld    b,0                     ; sy = 0 -> step up
kl_dyok
                ld    l,a
                ld    h,0
                ld    (kl_dy),hl
                ld    a,b
                ld    (kl_sy),a
                ld    hl,(kl_dx)              ; err = dx - dy
                ld    de,(kl_dy)
                or    a
                sbc   hl,de
                ld    (kl_err),hl
kl_loop
                call  kl_plot
                ld    hl,(kl_x)               ; both endpoints reached?
                ld    de,(kl_x1)
                or    a
                sbc   hl,de
                jr    nz,kl_step
                ld    a,(kl_y)
                ld    hl,kl_y1
                cp    (hl)
                ret   z
kl_step
                ld    hl,(kl_err)             ; e2 = 2*err
                add   hl,hl
                ld    (kl_e2),hl
                ld    de,(kl_dy)              ; e2 + dy >= 0 -> step x
                add   hl,de
                bit   7,h
                jr    nz,kl_ystep
                ld    hl,(kl_err)             ; err -= dy
                ld    de,(kl_dy)
                or    a
                sbc   hl,de
                ld    (kl_err),hl
                ld    hl,(kl_x)               ; x += sx
                ld    a,(kl_sx)
                or    a
                jr    z,kl_xdec
                inc   hl
                jr    kl_xset
kl_xdec
                dec   hl
kl_xset
                ld    (kl_x),hl
kl_ystep
                ld    hl,(kl_dx)              ; dx - e2 >= 0 -> step y
                ld    de,(kl_e2)
                or    a
                sbc   hl,de
                bit   7,h
                jr    nz,kl_loop
                ld    hl,(kl_err)             ; err += dx
                ld    de,(kl_dx)
                add   hl,de
                ld    (kl_err),hl
                ld    a,(kl_y)                ; y += sy
                ld    hl,kl_sy
                bit   0,(hl)
                jr    z,kl_ydec
                inc   a
                jr    kl_yset
kl_ydec
                dec   a
kl_yset
                ld    (kl_y),a
                jr    kl_loop

; kl_plot: pixel (kl_x, kl_y) in the kl_hwb pen; off-screen = skipped.
kl_plot
                ld    a,(kl_y)
                cp    PCW_LINES
                ret   nc
                ld    hl,(kl_x)
                ld    de,360
                or    a
                sbc   hl,de                   ; x >= 360 (incl. negative ints
                ret   nc                      ; seen as huge) -> skip
                ld    hl,(kl_x)               ; byte col = x >> 2
                srl   h
                rr    l
                srl   h
                rr    l
                ld    d,l
                ld    a,(kl_y)
                ld    e,a
                call  pcw_addr                ; HL = the byte (block mapped)
                ld    a,(kl_x)                ; per-pixel field by x & 3
                and   3
                ld    c,a
                ld    b,0
                push  hl
                ld    hl,kl_keep
                add   hl,bc
                ld    a,(hl)
                pop   hl
                ld    c,a                     ; C = keep-mask (other pixels)
                cpl
                ld    b,a                     ; B = this pixel's field mask
                ld    a,(hl)
                and   c
                ld    c,a
                ld    a,(kl_hwb)
                and   b
                or    c
                ld    (hl),a
                ret
kl_keep         db    %00111111,%11001111,%11110011,%11111100
kl_hwb          db    0
kl_x            dw    0
kl_x1           dw    0
kl_y            db    0
kl_y1           db    0
kl_sx           db    0
kl_sy           db    0
kl_dx           dw    0
kl_dy           dw    0
kl_err          dw    0
kl_e2           dw    0

; --- parameter / scratch cells: same low-RAM homes as the CPC/MSX drivers ----
bm_src          equ   #14A4        ; source bitmap pointer (advanced by blit)
bm_x            equ   #14A6        ; destination x in bytes (0..89)
bm_y            equ   #14A7        ; destination y (0..247)
bm_w            equ   #14A8        ; width in bytes
bm_h            equ   #14A9        ; height in rows
bl_rows         equ   #14AA
bl_y            equ   #14AB
bl_cnt          equ   #14AC
bm_keep         equ   #14AD        ; #FF = pen-0 transparent (desktop), #00 = opaque

fb_x            equ   #14B8
fb_y            equ   #14B9
fb_w            equ   #14BA
fb_h            equ   #14BB
fb_val          db    0            ; hardware-space fill byte (from pen_to_byte)
fb_rows         equ   #14AE
fb_cy           equ   #14AF

clip_x          equ   #1338        ; clip rect (shared contract addresses)
clip_y          equ   #1339
clip_w          equ   #133A
clip_h          equ   #133B
fbw_x           equ   #14B0
fbw_y           equ   #14B1
fbw_w           equ   #14B2
fbw_h           equ   #14B3

sb_x            db    0
sb_y            db    0
sb_w            db    0
sb_h            db    0
sb_buf          dw    0

                include "pic_lut.inc"
sb_rows         equ   #14B4
sb_cy           equ   #14B5
sb_ptr          equ   #14B6
