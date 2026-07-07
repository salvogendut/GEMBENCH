; -----------------------------------------------------------------------
; spike.asm - PCW boot + video proof-of-life payload (#331 Phase 1)
;
; Loaded at #1000 by kernel/pcwboot.asm from GEOBENCH.DSK's reserved
; track sectors.  Proves the whole Phase-1 chain: custom boot sector ->
; polled uPD765 load -> roller-RAM programming -> CGA-mode color.
;
; PCW video: 720x256 1bpp via "roller RAM" - a 512-byte table of one
; 16-bit word per scanline.  Word w -> source row address
;     A = ((w & #E000) << 1) | ((w & #1FF8) << 1) | (w & 7)
; i.e. w = (A>>1 & #FFF8) | (A & 7), with A3 forced 0.  Within a row
; the 90 byte-columns step by 8 (char-cell interleave), so a "cellrow"
; of 8 scanlines is one contiguous 720-byte run: byte(xcol,y) =
; cellrow_base + xcol*8 + (y&7).  720 = 16*45, so cellrow strides keep
; A3=0 and the standard layout encodes cleanly.
;
; With the 1985 emulator's video_mode=cga2 the same bitmap is shown as
; 2bpp / 360x256 / 4 colors: pixel i of each byte = (byte>>(6-2i))&3,
; palette 0=black 1=cyan 2=magenta 3=white - the MSX Screen 6 packing.
;
; Layout (physical = CPU address, identity banking at boot):
;   #5C00  roller table (512 bytes)
;   #6000  framebuffer, 32 cellrows x 720 = 23040 bytes (ends #B9FF)
;
; Pattern: four 64-line bands of solid pens 0..3, and the two middle
; cellrows overwritten with #1B = pens 0,1,2,3 - a 4-color ramp every
; 4 pixels that proves per-pixel CGA packing.
; -----------------------------------------------------------------------

RTABLE  equ #5C00
SCREEN  equ #6000

        org #1000

entry:
        di
        ld sp,#F000

; ---- build the roller table: word(y) = (base>>1) | (y&7) --------------
        ld hl,RTABLE
        ld bc,SCREEN/2          ; BC = cellrow base >> 1
        ld d,32                 ; 32 cellrows
rt_cell:
        ld e,0                  ; line within cell, 0..7
rt_line:
        ld a,c
        or e                    ; low word byte = (base>>1)|line
        ld (hl),a
        inc hl
        ld a,b
        ld (hl),a
        inc hl
        inc e
        ld a,e
        cp 8
        jr c,rt_line
        push hl
        ld hl,360               ; next cellrow: base += 720 -> base>>1 += 360
        add hl,bc
        ld b,h
        ld c,l
        pop hl
        dec d
        jr nz,rt_cell

; ---- fill the framebuffer: 4 bands of solid pens ----------------------
        ld hl,SCREEN
        ld c,0                  ; cellrow counter
fb_cell:
        ld a,c
        rrca
        rrca
        rrca
        and 3                   ; band = cellrow>>3
        push hl
        ld hl,valtab
        add a,l
        ld l,a
        jr nc,fb_nv
        inc h
fb_nv:  ld a,(hl)
        pop hl
        ld b,a                  ; B = fill byte
        ld de,720
fb_fill:
        ld (hl),b
        inc hl
        dec de
        ld a,d
        or e
        jr nz,fb_fill
        inc c
        ld a,c
        cp 32
        jr c,fb_cell

; ---- middle stripe: per-pixel 4-color ramp ----------------------------
        ld hl,SCREEN+15*720     ; cellrows 15+16 (lines 120..135)
        ld de,1440
mid:    ld (hl),#1B             ; pixels = pens 0,1,2,3
        inc hl
        dec de
        ld a,d
        or e
        jr nz,mid

; ---- point the hardware at it -----------------------------------------
        ld a,#2E                ; roller base: ((1)<<14)|(#0E<<9) = #5C00
        out (#F5),a
        xor a
        out (#F6),a             ; vertical scroll 0
        ld a,#40
        out (#F7),a             ; bit6 screen enable, bit7 normal video
        ld a,7
        out (#F8),a             ; display enable on

hang:   jr hang

; Pad the image past 11K so it spans three tracks (T0 R2-9, T1, T2) -
; valtab then loads from the last track, proving the boot loader's
; multi-track SEEK + read path.  Wrong/missing later sectors = black
; or garbage bands instead of the 4-color pattern.
        defs 11000,#E5

valtab: db #00,#55,#AA,#FF      ; solid-pen fill bytes, 4px each

spike_end:
        save"build/pcwspike.bin",#1000,spike_end-entry
