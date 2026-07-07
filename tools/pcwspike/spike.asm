; -----------------------------------------------------------------------
; spike.asm - PCW driver testbench payload (#331 Phase 2)
;
; Loaded at #1000 by kernel/pcwboot.asm from GEOBENCH.DSK's reserved
; tracks. Exercises lib/pcw/screen.asm - the real GEOBENCH PCW video
; driver - end to end, headless. Expected screenshot:
;
;   cyan desktop (k_cls, GB pen 0), letterbox black strip at the bottom
;   three rects: white / black / magenta          (fill_block pens 1,2,3)
;   a cyan/magenta 16px checker field             (fill_pattern, BD_TILE)
;   a test glyph blitted TRANSPARENT over the checker (pen-0 shows it)
;   the same glyph OPAQUE on the desktop          (pen-0 = cyan box)
;   a black bar crossing y=120..135               (block 4/5 boundary)
;   a small magenta patch ONLY inside a clip window (clip honored)
;   NO magenta at the save/restore spot           (round trip works)
;
; NOTE: the stack must NOT live in slot 3 (#C000+) - the driver remaps
; that window per drawing row. SP sits below #8000 instead.
; -----------------------------------------------------------------------

BACKDROP_TILE   equ   1

                org #1000

                include "../../lib/pcw/glue.inc"

entry:
        di
        ld sp,#8000             ; NOT #F000 - slot 3 is the screen window
        ld a,(#0F01)            ; debug: count boot cycles (survives reload)
        inc a
        ld (#0F01),a
        ld a,0
        ld (#0F00),a            ; debug: stage beacon

        call pcw_video_init     ; roller table + cls + display on
        ld a,1
        ld (#0F00),a

        ; --- three solid rects: pens 1 / 2 / 3 -------------------------
        ld a,1
        ld bc,#0410             ; x=4  y=16
        ld de,#1420             ; w=20 h=32
        call fill_t
        ld a,2
        ld bc,#1E10             ; x=30
        ld de,#1420
        call fill_t
        ld a,3
        ld bc,#3810             ; x=56
        ld de,#1420
        call fill_t

        ; --- checker field via fill_pattern ----------------------------
        ld a,4                  ; x=4
        ld (fb_x),a
        ld a,64
        ld (fb_y),a
        ld a,60
        ld (fb_w),a
        ld a,48
        ld (fb_h),a
        ld a,2
        ld (#0F00),a
        call fill_pattern
        ld a,3
        ld (#0F00),a

        ; --- glyph: transparent over the checker, opaque on desktop ----
        ld a,#FF
        ld (bm_keep),a
        ld hl,glyph
        ld (bm_src),hl
        ld a,10
        ld (bm_x),a
        ld a,72
        ld (bm_y),a
        ld a,4
        ld (bm_w),a
        ld a,16
        ld (bm_h),a
        call blit_bitmap

        xor a
        ld (bm_keep),a
        ld hl,glyph
        ld (bm_src),hl
        ld a,40
        ld (bm_x),a
        ld a,72
        ld (bm_y),a
        ld a,4
        ld (bm_w),a
        ld a,16
        ld (bm_h),a
        call blit_bitmap
        ld a,4
        ld (#0F00),a

        ; --- bar crossing the block 4/5 boundary (y 120..135) ----------
        ld a,2
        ld bc,#0478             ; x=4 y=120
        ld de,#5010             ; w=80 h=16
        call fill_t

        ; --- save / scribble / restore: must leave no trace ------------
        ld a,56
        ld (sb_x),a
        ld a,160
        ld (sb_y),a
        ld a,8
        ld (sb_w),a
        ld a,16
        ld (sb_h),a
        ld hl,#2000
        ld (sb_buf),hl
        ld a,5
        ld (#0F00),a
        call save_block
        ld a,6
        ld (#0F00),a
        ld a,3                  ; scribble magenta over the saved area
        ld bc,#38A0             ; x=56 y=160
        ld de,#0810
        call fill_t
        ld a,7
        ld (#0F00),a
        call restore_block      ; and undo it
        ld a,8
        ld (#0F00),a

        ; --- clip window: fill way past it, only the window paints -----
        ld a,70
        ld (clip_x),a
        ld a,160
        ld (clip_y),a
        ld a,10
        ld (clip_w),a
        ld a,16
        ld (clip_h),a
        ld a,3
        ld bc,#3C96             ; x=60 y=150
        ld de,#1E28             ; w=30 h=40 - mostly outside the clip
        call fill_t
        xor a                   ; reset clip to full screen
        ld (clip_x),a
        ld (clip_y),a
        ld a,PCW_COLS
        ld (clip_w),a
        ld a,PCW_LINES
        ld (clip_h),a

        ld a,9
        ld (#0F00),a
hang:   jr hang

; fill_t: A = pen, B = x, C = y, D = w, E = h -> fill_block
fill_t:
        push de
        push bc
        call pen_to_byte        ; clobbers A,E only
        ld (fb_val),a
        pop bc
        ld a,b
        ld (fb_x),a
        ld a,c
        ld (fb_y),a
        pop de
        ld a,d
        ld (fb_w),a
        ld a,e
        ld (fb_h),a
        jp fill_block

; --- the GEOBENCH PCW video driver under test --------------------------
                include "../../lib/pcw/screen.asm"

; --- test data ----------------------------------------------------------
; 16x16px checker tile, GB pens 0/3 (renders cyan/magenta)
BD_TILE:
        db #00,#00,#FF,#FF
        db #00,#00,#FF,#FF
        db #00,#00,#FF,#FF
        db #00,#00,#FF,#FF
        db #00,#00,#FF,#FF
        db #00,#00,#FF,#FF
        db #00,#00,#FF,#FF
        db #00,#00,#FF,#FF
        db #FF,#FF,#00,#00
        db #FF,#FF,#00,#00
        db #FF,#FF,#00,#00
        db #FF,#FF,#00,#00
        db #FF,#FF,#00,#00
        db #FF,#FF,#00,#00
        db #FF,#FF,#00,#00
        db #FF,#FF,#00,#00

; 16x16px test glyph, GB pen space: pen-0 corners (transparent when
; bm_keep=#FF), pen-2 black ring, pen-1 white fill, pen-3 red core.
glyph:
        db #00,#AA,#AA,#00      ; row 0:  ..RRRR..  (R = ring pen2)
        db #0A,#AA,#AA,#A0
        db #AA,#55,#55,#AA      ; ring around white fill
        db #AA,#55,#55,#AA
        db #A5,#55,#55,#5A
        db #A5,#5F,#F5,#5A      ; pen-3 core starts
        db #A5,#5F,#F5,#5A
        db #A5,#55,#55,#5A
        db #A5,#55,#55,#5A
        db #A5,#5F,#F5,#5A
        db #A5,#5F,#F5,#5A
        db #A5,#55,#55,#5A
        db #AA,#55,#55,#AA
        db #AA,#55,#55,#AA
        db #0A,#AA,#AA,#A0
        db #00,#AA,#AA,#00

spike_end:
        save"build/pcwspike.bin",#1000,spike_end-entry
