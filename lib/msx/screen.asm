; ---------------------------------------------------------------------------
; lib/msx/screen.asm - GEOBENCH V9938 Screen 6 driver for the MSX2 target (#287).
;
; The MSX counterpart of lib/screen.asm: same entry points, same low-RAM
; parameter cells (bm_*, fb_*, sb_*, clip_*), so every caller in the shared
; kernel body compiles unchanged. The difference is the surface: Screen 6
; (512x212, 4 colours, 2bpp) lives in VRAM behind the V9938 ports, not in a
; CPU-addressable framebuffer.
;
;   - layout is LINEAR: vram = y*128 + xbyte (no CPC CRTC interleave)
;   - in-byte encoding is 2-bit fields, leftmost pixel in bits 7-6:
;       a byte of one pen p is p*#55: p0->#00 p1->#55 p2->#AA p3->#FF
;   - rectangle fills use the HMMV blitter command
;   - row copies stream through port #98 with autoincrement (OTIR/INIR pacing
;     is safe in bitmap modes); read-modify-write rows bounce via MSX_ROWBUF
;   - every primitive waits for the command engine (CE) before touching VRAM,
;     since a previous HMMV may still be running
;   - multi-byte VDP address/register sequences run under DI: the BIOS ISR
;     reads status port #99, which would reset the two-byte address latch
;
; Coordinates keep the CPC conventions: x in BYTE columns (0..127 here),
; y in lines (0..211). Clipping/culling is the shared lib/screen_clip.asm.
; ---------------------------------------------------------------------------

; --- VDP access helpers ----------------------------------------------------

; vdp_setwr: D = xbyte, E = y -> set the VRAM write address to y*128 + xbyte.
; Leaves autoincrement writing via port #98. Clobbers A. DI/EI inside.
vdp_setwr
                di
                ld    a,e                     ; R#14 = A16..A14 = y>>7 (bit14 of y*128)
                rlca
                and   1
                out   (VDP_CTRL),a
                ld    a,14|#80
                out   (VDP_CTRL),a
                ld    a,e                     ; low byte = (y&1)<<7 | xbyte
                rrca                          ; CF = y bit0... use bit0 via rrca into b7
                ld    a,0
                rra                           ; A = (y&1) ? #80 : 0  (rrca left CF = y&1)
                or    d
                out   (VDP_CTRL),a
                ld    a,e                     ; high byte = (y>>1) & #3F, +#40 for write
                srl   a
                and   #3F
                or    #40
                out   (VDP_CTRL),a
                ei
                ret

; vdp_setrd: D = xbyte, E = y -> set the VRAM read address (reads via port #98).
vdp_setrd
                di
                ld    a,e
                rlca
                and   1
                out   (VDP_CTRL),a
                ld    a,14|#80
                out   (VDP_CTRL),a
                ld    a,e
                rrca
                ld    a,0
                rra
                or    d
                out   (VDP_CTRL),a
                ld    a,e
                srl   a
                and   #3F
                out   (VDP_CTRL),a
                ei
                ret

; vdp_setwr16: HL = absolute VRAM address (0..65535) -> write mode. For the
; sprite tables (#F000+). Clobbers A. DI/EI inside.
vdp_setwr16
                di
                ld    a,h
                rlca
                rlca
                and   3                       ; A16..A14
                out   (VDP_CTRL),a
                ld    a,14|#80
                out   (VDP_CTRL),a
                ld    a,l
                out   (VDP_CTRL),a
                ld    a,h
                and   #3F
                or    #40
                out   (VDP_CTRL),a
                ei
                ret

; vdp_reg: A = value, C = register number. Clobbers A.
vdp_reg
                di
                out   (VDP_CTRL),a
                ld    a,c
                or    #80
                out   (VDP_CTRL),a
                ei
                ret

; vdp_wait_ce: block until the command engine is idle (S#2 bit0 clear).
; Restores R#15 = 0 (the BIOS ISR expects S#0). Clobbers A.
vdp_wait_ce
                di
                ld    a,2
                out   (VDP_CTRL),a
                ld    a,15|#80
                out   (VDP_CTRL),a
vwc_poll        in    a,(VDP_CTRL)
                rrca
                jr    c,vwc_poll
                xor   a
                out   (VDP_CTRL),a
                ld    a,15|#80
                out   (VDP_CTRL),a
                ei
                ret

; vdp_hmmv: fill the rectangle DX=(vc_dx) DY=(vc_dy) NX=(vc_nx) NY=(vc_ny)
; with byte (vc_clr) via the HMMV command. Waits CE first. Pixel units.
vdp_hmmv
                call  vdp_wait_ce
                ld    a,36                    ; R#17 = 36, autoincrement -> R#36..R#46
                ld    c,17
                call  vdp_reg
                di
                ld    hl,vc_dx
                ld    bc,#0B00|VDP_IND        ; B = 11 bytes, C = indirect data port
vhm_out         outi
                jr    nz,vhm_out
                ei
                ret

; --- pen_to_byte: A = pen (0..3) -> A = solid Screen 6 byte (pen * #55) -----
pen_to_byte
                and   3
                ld    e,a
                add   a,a
                add   a,a
                or    e                       ; pen * 5 (bits in both low fields)
                ld    e,a
                add   a,a
                add   a,a
                add   a,a
                add   a,a
                or    e                       ; * #11 -> all four 2-bit fields
                ret

; --- blit_bitmap: bm_w x bm_h bytes at (bm_x, bm_y) from (bm_src) -----------
; Opaque (bm_keep=0): stream each row straight to VRAM. Transparent
; (bm_keep=#FF, desktop icons): read the row back, composite in MSX_ROWBUF
; with the pen-0 mask, write it out.
blit_bitmap
                ld    a,(bm_x)               ; cull against the clip rect (shared code)
                ld    b,a
                ld    a,(bm_y)
                ld    c,a
                ld    a,(bm_w)
                ld    d,a
                ld    a,(bm_h)
                ld    e,a
                call  rect_cull
                ret   c
                call  vdp_wait_ce
                ld    a,(bm_h)
                ld    (bl_rows),a
                ld    a,(bm_y)
                ld    (bl_y),a
bl_loop
                ld    a,(bm_keep)
                or    a
                jr    nz,bl_trans
                ; --- opaque row: set write addr, OTIR the source row --------
                ld    a,(bm_x)
                ld    d,a
                ld    a,(bl_y)
                ld    e,a
                call  vdp_setwr
                ld    hl,(bm_src)
                ld    a,(bm_w)
                ld    b,a
                ld    c,VDP_DATA
bl_orow         outi
                jr    nz,bl_orow
                ld    (bm_src),hl            ; advance past this row
                jr    bl_next
bl_trans
                ; --- transparent row: read back, composite, write -----------
                ld    a,(bm_x)
                ld    d,a
                ld    a,(bl_y)
                ld    e,a
                call  vdp_setrd
                ld    hl,MSX_ROWBUF
                ld    a,(bm_w)
                ld    b,a
                ld    c,VDP_DATA
bl_trd          ini
                jr    nz,bl_trd
                ld    de,MSX_ROWBUF          ; DE = screen row copy
                ld    hl,(bm_src)            ; HL = icon row
                ld    a,(bm_w)
                ld    (bl_cnt),a
bl_tbyte
                ld    a,(hl)                  ; mask: both bits of every non-pen-0 field
                ld    c,a
                srl   a
                or    c
                and   #55
                ld    c,a
                add   a,a
                or    c                        ; A = opaque mask
                cpl                            ; ~mask = keep-background bits
                ld    c,a
                ld    a,(de)                  ; screen byte
                and   c                        ; keep background where transparent
                or    (hl)                     ; add the icon's opaque pixels
                ld    (de),a
                inc   hl
                inc   de
                ld    a,(bl_cnt)
                dec   a
                ld    (bl_cnt),a
                jr    nz,bl_tbyte
                ld    (bm_src),hl            ; advance the icon row
                ld    a,(bm_x)               ; write the composited row back
                ld    d,a
                ld    a,(bl_y)
                ld    e,a
                call  vdp_setwr
                ld    hl,MSX_ROWBUF
                ld    a,(bm_w)
                ld    b,a
                ld    c,VDP_DATA
bl_twr          outi
                jr    nz,bl_twr
bl_next
                ld    a,(bl_y)
                inc   a
                ld    (bl_y),a
                ld    a,(bl_rows)
                dec   a
                ld    (bl_rows),a
                jp    nz,bl_loop
                ret

; --- fill_block: fb_w x fb_h bytes at (fb_x, fb_y) with fb_val --------------
; One HMMV after clipping - the V9938 does the whole rectangle.
fill_block
                call  clip_fb_copy           ; fbw_* = fb_* clipped (shared code)
                ret   c
                ld    a,(fbw_x)              ; DX = xbyte * 4 (pixels)
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                ld    (vc_dx),hl
                ld    a,(fbw_y)
                ld    l,a
                ld    h,0
                ld    (vc_dy),hl
                ld    a,(fbw_w)              ; NX = wbytes * 4
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                ld    (vc_nx),hl
                ld    a,(fbw_h)
                ld    l,a
                ld    h,0
                ld    (vc_ny),hl
                ld    a,(fb_val)
                ld    (vc_clr),a
                xor   a
                ld    (vc_arg),a
                ld    a,#C0                  ; HMMV
                ld    (vc_cmd),a
                jp    vdp_hmmv

; --- fill_pattern: like fill_block but from the 16x16 BD_TILE ---------------
; Builds each row in MSX_ROWBUF from the tile at absolute phase (the tile byte
; for (x,y) is BD_TILE[(y&15)*4 + (x&3)]), then streams it out.
fill_pattern
                call  clip_fb_copy
                ret   c
                call  vdp_wait_ce
                ld    a,(fbw_h)
                ld    (fb_rows),a
                ld    a,(fbw_y)
                ld    (fb_cy),a
fp_row
                ld    a,(fb_cy)              ; DE = tile row base + column phase
                and   15
                add   a,a
                add   a,a
                ld    c,a
                ld    a,(fbw_x)
                and   3
                add   a,c
                ld    e,a
                ld    d,0
                ld    hl,BD_TILE
                add   hl,de
                ex    de,hl                   ; DE = tile ptr (phase-corrected)
                ld    hl,MSX_ROWBUF          ; build the row
                ld    a,(fbw_w)
                ld    b,a
fp_col
                ld    a,(de)
                ld    (hl),a
                inc   hl
                inc   e                       ; advance tile ptr; wrap every 4 bytes
                ld    a,e
                and   3
                jr    nz,fp_nw
                dec   e
                dec   e
                dec   e
                dec   e
fp_nw
                djnz  fp_col
                ld    a,(fbw_x)              ; stream the row to VRAM
                ld    d,a
                ld    a,(fb_cy)
                ld    e,a
                call  vdp_setwr
                ld    hl,MSX_ROWBUF
                ld    a,(fbw_w)
                ld    b,a
                ld    c,VDP_DATA
fp_out          outi
                jr    nz,fp_out
                ld    a,(fb_cy)
                inc   a
                ld    (fb_cy),a
                ld    a,(fb_rows)
                dec   a
                ld    (fb_rows),a
                jr    nz,fp_row
                ret

                include "../screen_clip.asm"  ; clip_fb_copy + rect_cull (shared, #287)

; --- save_block / restore_block ----------------------------------------------
; Same caller-RAM buffer contract as the CPC (w*h bytes, byte geometry is
; identical at 4px/byte). No ROM juggling: VRAM reads go through the port.
save_block
                call  vdp_wait_ce
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
                call  vdp_setrd
                ld    hl,(sb_ptr)            ; HL = buffer (dest)
                ld    a,(sb_w)
                ld    b,a
                ld    c,VDP_DATA
sv_row          ini
                jr    nz,sv_row
                ld    (sb_ptr),hl
                ld    a,(sb_cy)
                inc   a
                ld    (sb_cy),a
                ld    a,(sb_rows)
                dec   a
                ld    (sb_rows),a
                jr    nz,sv_loop
                ret

restore_block
                call  vdp_wait_ce
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
                call  vdp_setwr
                ld    hl,(sb_ptr)            ; HL = buffer (source)
                ld    a,(sb_w)
                ld    b,a
                ld    c,VDP_DATA
rs_row          outi
                jr    nz,rs_row
                ld    (sb_ptr),hl
                ld    a,(sb_cy)
                inc   a
                ld    (sb_cy),a
                ld    a,(sb_rows)
                dec   a
                ld    (sb_rows),a
                jr    nz,rs_loop2
                ret

; --- k_cls (GB_CLS): clear the whole bitmap to pen 0 -------------------------
k_cls
                ld    hl,0
                ld    (vc_dx),hl
                ld    (vc_dy),hl
                ld    hl,512
                ld    (vc_nx),hl
                ld    hl,212
                ld    (vc_ny),hl
                xor   a
                ld    (vc_clr),a
                ld    (vc_arg),a
                ld    a,#C0
                ld    (vc_cmd),a
                jp    vdp_hmmv

; --- set_palette: KCFG_INKS (CPC firmware ink numbers) -> V9938 palette ------
; KCFG_INKS stays in the CPC colour space on both platforms (the canonical
; config values); each ink maps through cpc2grb to a 9-bit GRB pair. Also seeds
; the cursor-sprite entries (12 = black outline, 13 = white fill) and the
; border (R#7, both 2-bit fields = the pen whose ink matches the border ink,
; else pen 0).
set_palette
                ld    b,4                     ; pens 0..3
                ld    c,0
sp_pen
                push  bc
                ld    a,c                     ; palette index = pen
                ld    c,16                    ; R#16 = palette pointer
                call  vdp_reg
                pop   bc
                push  bc
                ld    hl,KCFG_INKS
                ld    e,c
                ld    d,0
                add   hl,de
                ld    a,(hl)                  ; A = CPC ink number for this pen
                call  ink_to_grb              ; DE = GRB pair
                di
                ld    a,e
                out   (VDP_PAL),a
                ld    a,d
                out   (VDP_PAL),a
                ei
                pop   bc
                inc   c
                djnz  sp_pen
                ld    a,12                    ; cursor entries: 12 black, 13 white
                ld    c,16
                call  vdp_reg
                di
                xor   a
                out   (VDP_PAL),a            ; 12: R=0,B=0
                out   (VDP_PAL),a            ;     G=0
                ld    a,#77
                out   (VDP_PAL),a            ; 13: R=7,B=7
                ld    a,#07
                out   (VDP_PAL),a            ;     G=7
                ei
                ; border: R#7 = matching pen replicated into both 2-bit fields
                ld    a,(KCFG_INKS+4)
                ld    e,a
                ld    hl,KCFG_INKS
                ld    b,4
                ld    c,0
sp_bloop        ld    a,(hl)
                cp    e
                jr    z,sp_bfound
                inc   hl
                inc   c
                djnz  sp_bloop
                ld    c,0                     ; no pen matches -> pen 0
sp_bfound
                ld    a,c
                add   a,a
                add   a,a
                or    c                       ; pen * 5 = both fields
                ld    c,7
                jp    vdp_reg

; ink_to_grb: A = CPC firmware ink number (0..26) -> DE: E = (R<<4)|B, D = G.
ink_to_grb
                cp    27
                jr    c,itg_ok
                xor   a                       ; out of range -> black
itg_ok
                add   a,a
                ld    l,a
                ld    h,0
                ld    de,cpc2grb
                add   hl,de
                ld    e,(hl)
                inc   hl
                ld    d,(hl)
                ret

; CPC firmware colours 0..26 as V9938 GRB pairs (byte0 = R<<4|B, byte1 = G).
; CPC channel levels 0/50%/100% -> 0/4/7.
cpc2grb
                db    #00,#00                 ;  0 black
                db    #04,#00                 ;  1 blue
                db    #07,#00                 ;  2 bright blue
                db    #40,#00                 ;  3 red
                db    #44,#00                 ;  4 magenta
                db    #47,#00                 ;  5 mauve
                db    #70,#00                 ;  6 bright red
                db    #74,#00                 ;  7 purple
                db    #77,#00                 ;  8 bright magenta
                db    #00,#04                 ;  9 green
                db    #04,#04                 ; 10 cyan
                db    #07,#04                 ; 11 sky blue
                db    #40,#04                 ; 12 yellow
                db    #44,#04                 ; 13 white
                db    #47,#04                 ; 14 pastel blue
                db    #70,#04                 ; 15 orange
                db    #74,#04                 ; 16 pink
                db    #77,#04                 ; 17 pastel magenta
                db    #00,#07                 ; 18 bright green
                db    #04,#07                 ; 19 sea green
                db    #07,#07                 ; 20 bright cyan
                db    #40,#07                 ; 21 lime
                db    #44,#07                 ; 22 pastel green
                db    #47,#07                 ; 23 pastel cyan
                db    #70,#07                 ; 24 bright yellow
                db    #74,#07                 ; 25 pastel yellow
                db    #77,#07                 ; 26 bright white

; --- msx_video_init: post-CHGMOD screen setup (called once from boot) --------
; 212-line mode (R#9 LN), 16x16 sprites (R#1 SI), park the pointer sprites and
; terminate the sprite scan. The stub already ran CHGMOD 6 via the BIOS.
msx_video_init
                ld    a,(#FFE8)               ; RG9SAV: current R#9 mirror
                or    #80                     ; LN = 212 lines
                ld    (#FFE8),a
                ld    c,9
                call  vdp_reg
                ld    a,(#F3E0)               ; RG1SAV: current R#1 mirror
                or    #02                     ; SI = 16x16 sprites
                ld    (#F3E0),a
                ld    c,1
                call  vdp_reg
                ld    hl,SPR_ATTR             ; park sprites 0/1, terminate at 2
                call  vdp_setwr16
                di
                ld    a,217                   ; sprite 0: parked (below line 212)
                out   (VDP_DATA),a
                xor   a
                out   (VDP_DATA),a            ; x = 0
                out   (VDP_DATA),a            ; pattern 0
                out   (VDP_DATA),a            ; (reserved)
                ld    a,217                   ; sprite 1: parked
                out   (VDP_DATA),a
                xor   a
                out   (VDP_DATA),a
                ld    a,4                     ; pattern 4
                out   (VDP_DATA),a
                xor   a
                out   (VDP_DATA),a
                ld    a,216                   ; sprite 2: y=216 terminates the scan
                out   (VDP_DATA),a
                ei
                ret

; --- HMMV register block (streamed to R#36..R#46) ----------------------------
vc_dx           dw    0                       ; R36-37 DX (pixels)
vc_dy           dw    0                       ; R38-39 DY
vc_nx           dw    0                       ; R40-41 NX (pixels)
vc_ny           dw    0                       ; R42-43 NY
vc_clr          db    0                       ; R44 colour byte
vc_arg          db    0                       ; R45 direction
vc_cmd          db    #C0                     ; R46 command

; --- parameter / scratch cells: same low-RAM homes as the CPC driver ---------
bm_src          equ   #14A4        ; source bitmap pointer (advanced by blit)
bm_x            equ   #14A6        ; destination x in bytes (0..127)
bm_y            equ   #14A7        ; destination y (0..211)
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
fb_val          db    0            ; Screen 6 fill byte (pen * #55)
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
sb_rows         equ   #14B4
sb_cy           equ   #14B5
sb_ptr          equ   #14B6
