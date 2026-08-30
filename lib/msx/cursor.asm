; ---------------------------------------------------------------------------
; lib/msx/cursor.asm - V9938 hardware-sprite pointer for the MSX2 target (#287).
;
; Same interface as lib/cursor.asm (cursor_x/cursor_y in the CPC's 2-units-per-
; pixel virtual space, cursor_show / cursor_erase / cursor_move_to /
; cursor_draw, cur_supp / cur_paintlock flags) - but the arrow is two 16x16
; hardware sprites (plane 0 = white outline; plane 1 = red fill), so there is
; NO save-under, no composite, and no way for a stale
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
                ; Screen 7 uses direct palette indices. Screen 6 repeats each
                ; 2-bit pen in both halves of the colour nibble.
                ld    hl,SPR_COLOUR          ; sprite 0 lines = pen 1 (white border)
                call  vdp_setwr16
                di
                ld    b,16
                ifdef MSX_SCREEN7
                ld    a,1
                else
                ld    a,%0101
                endif
ca_c0           out   (VDP_DATA),a
                djnz  ca_c0
                ld    b,16                    ; sprite 1 lines = pen 3 (red fill)
                ifdef MSX_SCREEN7
                ld    a,3
                else
                ld    a,%1111
                endif
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
                ifdef GEMBENCH_BASELINE
                if GEMBENCH_BASELINE
                ld    a,(cd_sx)
                ld    (baseline_old_sx),a
                ld    a,(cd_sy)
                ld    (baseline_old_sy),a
                endif
                endif
                ld    (cursor_x),de
                ld    (cursor_y),hl
                ld    a,(cur_supp)           ; suppressed (DnD ghost): track, don't draw
                or    a
                ret   nz
                ld    a,(cur_paintlock)
                or    a
                ret   nz
                ifdef GEMBENCH_BASELINE
                if GEMBENCH_BASELINE
                call  cursor_draw
                jp    baseline_pointer_ack
                endif
                endif
                jp    cursor_draw

                ifdef GEMBENCH_BASELINE
                if GEMBENCH_BASELINE
; Record the completion point only on cursor_move_to's changed-position path,
; after both hardware-sprite attribute entries have reached VRAM. Plain
; hide/show brackets therefore cannot produce a false pointer acknowledgement.
baseline_pointer_ack
                ld    a,(MSX_BASELINE_INPUT_FLAGS)
                bit   0,a
                ret   z
                bit   1,a
                ret   nz
                ld    a,(cd_sx)               ; virtual movement smaller than one
                ld    hl,baseline_old_sx       ; sprite pixel is not yet visible
                cp    (hl)
                jr    nz,bpa_visible
                ld    a,(cd_sy)
                ld    hl,baseline_old_sy
                cp    (hl)
                ret   z
bpa_visible
                ld    a,(MSX_BASELINE_INPUT_FLAGS)
                ld    hl,(MSX_TICK)
                ld    (MSX_BASELINE_POINTER_ACK),hl
                set   1,a
                ld    (MSX_BASELINE_INPUT_FLAGS),a
                ret
baseline_old_sx db    0
baseline_old_sy db    0
                endif
                endif

; cursor_erase: park the sprites below the display.
cursor_erase
                ld    a,(MSX_TIMER_OWNER)      ; a timer-only compositor pass cannot
                or    a                        ; contaminate this hardware-sprite pointer,
                ret   m                        ; so keep it visible instead of blinking it
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
                out   (VDP_DATA),a            ; x/pattern/colour are immaterial while
                out   (VDP_DATA),a            ; parked and cursor_draw replaces all eight
                out   (VDP_DATA),a            ; attribute bytes before showing the pointer
                out   (VDP_DATA),a            ; sprite 1 y: parked
                ei
                ret

; cursor_draw: position both sprites at (cursor_x, cursor_y) minus the hotspot.
; line = 211 - cursor_y/2 (the shared Y-flipped virtual space); sprite x is in
; 2-screen-pixel units in the 512-dot mode, so attr x = pixel/2 = cursor_x/4.
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
