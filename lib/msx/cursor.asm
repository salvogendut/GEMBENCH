; ---------------------------------------------------------------------------
; lib/msx/cursor.asm - V9938 hardware-sprite pointer for the MSX2 target (#287).
;
; Same interface as lib/cursor.asm (cursor_x/cursor_y in the CPC's 2-units-per-
; pixel virtual space, cursor_show / cursor_erase / cursor_move_to /
; cursor_draw, cur_supp / cur_paintlock flags) - but the arrow is two 16x16
; hardware sprites (plane 0 = black outline, palette 12; plane 1 = white fill,
; palette 13), so there is NO save-under, no composite, and no way for a stale
; pointer to be baked into a window's save-under (#126-class bugs impossible).
; "Erase" just parks the sprites below the 212-line display.
;
; The sprite pattern comes from the loaded .SPR asset (CUR_LOW): the MSX .SPR
; layout is +0 hotspot_x, +1 hotspot_y, +2..33 outline plane, +34..65 fill
; plane (png2spr.py --platform msx2). cursor_apply uploads it to VRAM; the
; shared cursor_init calls it after every (re)load.
; ---------------------------------------------------------------------------

; cursor_apply: upload the .SPR at CUR_LOW to the sprite pattern + colour
; tables. Pattern 0 = outline (sprite 0), pattern 4 = fill (sprite 1).
cursor_apply
                call  vdp_wait_ce
                ld    hl,SPR_PATTERN         ; both 32-byte planes, back to back
                call  vdp_setwr16
                ld    hl,CUR_LOW+2
                ld    b,64
                ld    c,VDP_DATA
ca_pat          outi
                jr    nz,ca_pat
                ; Screen 6 (G5) quirk: a sprite colour nibble is TWO 2-bit pen
                ; fields - the renderer emits palette[c>>2] then palette[c&3]
                ; per sprite pixel (verified in the V9938 rasterizer). So both
                ; halves must name the same pen: outline = %1010 (pen 2 black),
                ; fill = %0101 (pen 1 white); the pointer follows INKS= like
                ; the rest of the UI.
                ld    hl,SPR_COLOUR          ; sprite 0 lines = pen-2 pair (outline)
                call  vdp_setwr16
                di
                ld    b,16
                ld    a,%1010
ca_c0           out   (VDP_DATA),a
                djnz  ca_c0
                ld    b,16                    ; sprite 1 lines = pen-1 pair (fill)
                ld    a,%0101
ca_c1           out   (VDP_DATA),a
                djnz  ca_c1
                ei
                ret

; cursor_show: place the sprites at the current position (honours the locks).
cursor_show
                ld    a,(cur_paintlock)
                or    a
                ret   nz
                ld    a,(cur_shown)
                or    a
                ret   nz
                jp    cursor_draw

; cursor_move_to: DE = x, HL = y (virtual units). No-op if unchanged.
cursor_move_to
                ld    a,(cursor_x)
                cp    e
                jr    nz,cm_go
                ld    a,(cursor_x+1)
                cp    d
                jr    nz,cm_go
                ld    a,(cursor_y)
                cp    l
                jr    nz,cm_go
                ld    a,(cursor_y+1)
                cp    h
                ret   z
cm_go
                ld    (cursor_x),de
                ld    (cursor_y),hl
                ld    a,(cur_supp)           ; suppressed (DnD ghost): track, don't draw
                or    a
                ret   nz
                ld    a,(cur_paintlock)
                or    a
                ret   nz
                jp    cursor_draw

; cursor_erase: park the sprites below the display.
cursor_erase
                ld    a,(cur_paintlock)
                or    a
                ret   nz
                xor   a
                ld    (cur_shown),a
                ld    hl,SPR_ATTR
                call  vdp_setwr16
                di
                ld    a,217                   ; sprite 0 y: parked
                out   (VDP_DATA),a
                ei
                ld    hl,SPR_ATTR+4
                call  vdp_setwr16
                di
                ld    a,217                   ; sprite 1 y: parked
                out   (VDP_DATA),a
                ei
                ret

; cursor_draw: position both sprites at (cursor_x, cursor_y) minus the hotspot.
; line = 211 - cursor_y/2 (the shared Y-flipped virtual space); sprite x is in
; 2-screen-pixel units in Screen 6, so attr x = pixel/2 = cursor_x/4.
cursor_draw
                ld    hl,(cursor_y)
                srl   h
                rr    l
                ld    a,211
                sub   l                       ; A = line (0..211)
                ld    hl,CUR_LOW+1
                sub   (hl)                    ; - hotspot_y
                jr    nc,cd_yok
                xor   a
cd_yok
                dec   a                       ; sprite displays at y+1
                ld    (cd_sy),a
                ld    hl,(cursor_x)
                srl   h
                rr    l
                srl   h
                rr    l                       ; HL = cursor_x/4 = sprite x (0..255)
                ld    a,l
                ld    hl,CUR_LOW
                sub   (hl)                    ; - hotspot_x (sprite-pixel units)
                jr    nc,cd_xok
                xor   a
cd_xok
                ld    (cd_sx),a
                ld    hl,SPR_ATTR             ; sprite 0: y, x, pattern 0
                call  vdp_setwr16
                di
                ld    a,(cd_sy)
                out   (VDP_DATA),a
                ld    a,(cd_sx)
                out   (VDP_DATA),a
                xor   a
                out   (VDP_DATA),a            ; pattern 0 (outline)
                out   (VDP_DATA),a
                ld    a,(cd_sy)               ; sprite 1: same spot, pattern 4
                out   (VDP_DATA),a
                ld    a,(cd_sx)
                out   (VDP_DATA),a
                ld    a,4
                out   (VDP_DATA),a
                ei
                ld    a,1
                ld    (cur_shown),a
                ret

; --- State (same names/semantics as the CPC pointer) --------------------------
cursor_x        dw    512                    ; virtual units (2 per screen pixel)
cursor_y        dw    212
cur_supp        db    0            ; 1 = suppress drawing (DnD drag shows a ghost)
cur_shown       db    0
cur_paintlock   db    0            ; 1 = inside wm_repaint_all
cd_sx           db    0
cd_sy           db    0
