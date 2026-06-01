; ---------------------------------------------------------------------------
; lib/graphics.asm - GEOBENCH graphics helpers
;
; Rectangle/circle drawing and small unsigned compare/clamp helpers, shared by
; the desktop and icon code. (The mouse cursor lives in lib/cursor.asm.)
;
; Requires lib/firmware.inc. Assembled into the consumer; no org.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; HL = max(HL,DE)  (unsigned 16-bit)
clamp_lo
                ld    a,h
                cp    d
                jr    c,cl_set
                jr    nz,cl_keep
                ld    a,l
                cp    e
                jr    c,cl_set
cl_keep         ret
cl_set          ld    h,d
                ld    l,e
                ret

; HL = min(HL,DE)  (unsigned 16-bit)
clamp_hi
                ld    a,d
                cp    h
                jr    c,ch_set
                jr    nz,ch_keep
                ld    a,e
                cp    l
                jr    c,ch_set
ch_keep         ret
ch_set          ld    h,d
                ld    l,e
                ret

; Carry set iff HL < DE (unsigned 16-bit). HL and DE are preserved.
cmp_hl_de
                ld    a,h
                cp    d
                ret   c                     ; h < d  -> HL < DE
                ret   nz                    ; h > d  -> HL > DE (carry clear)
                ld    a,l
                cp    e                      ; compare low bytes
                ret

; ---------------------------------------------------------------------------
; Rectangle primitives. The rectangle is passed in rx0,ry0 (one corner) and
; rx1,ry1 (the opposite corner), with ry0 <= ry1. Pen is in A.

; draw_box: outline the rectangle.
draw_box
                call  GRA_SET_PEN
                ld    de,(rx0)
                ld    hl,(ry0)
                call  GRA_MOVE_ABS
                ld    de,(rx1)
                ld    hl,(ry0)
                call  GRA_LINE_ABS
                ld    de,(rx1)
                ld    hl,(ry1)
                call  GRA_LINE_ABS
                ld    de,(rx0)
                ld    hl,(ry1)
                call  GRA_LINE_ABS
                ld    de,(rx0)
                ld    hl,(ry0)
                call  GRA_LINE_ABS
                ret

; fill_rect: solid fill by drawing one horizontal line per screen row
; (graphics y steps by 2 in Mode 1).
fill_rect
                call  GRA_SET_PEN
                ld    hl,(ry0)
                ld    (fr_y),hl
fr_loop
                ld    de,(rx0)
                ld    hl,(fr_y)
                call  GRA_MOVE_ABS
                ld    de,(rx1)
                ld    hl,(fr_y)
                call  GRA_LINE_ABS
                ld    hl,(fr_y)
                inc   hl
                inc   hl
                ld    (fr_y),hl
                ld    hl,(ry1)             ; continue while ry1 >= fr_y
                ld    de,(fr_y)
                or    a
                sbc   hl,de
                jr    nc,fr_loop
                ret

; ---------------------------------------------------------------------------
; fill_circle: solid circle of radius 16 px centred at (cir_cx,cir_cy), pen A.
; For each pixel row k away from the centre, circle_half[k] gives the half-width
; in pixels; we draw a horizontal line above and below the centre. Coordinates
; are graphics units, so pixel counts are doubled (2 units = 1 px in Mode 1).
fill_circle
                call  GRA_SET_PEN
                xor   a
                ld    (fc_k),a
fc_loop
                ld    a,(fc_k)               ; half-width for this row
                ld    e,a
                ld    d,0
                ld    hl,circle_half
                add   hl,de
                ld    a,(hl)
                add   a,a                     ; pixels -> graphics units
                ld    e,a
                ld    d,0
                ld    hl,(cir_cx)
                add   hl,de
                ld    (fc_xr),hl             ; right end = cx + half
                ld    hl,(cir_cx)
                or    a
                sbc   hl,de
                ld    (fc_xl),hl             ; left end  = cx - half

                ld    a,(fc_k)               ; upper row: cy + 2k
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,(cir_cy)
                add   hl,de
                call  fc_hline

                ld    a,(fc_k)               ; lower row: cy - 2k (skip k=0)
                or    a
                jr    z,fc_next
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,(cir_cy)
                or    a
                sbc   hl,de
                call  fc_hline
fc_next
                ld    a,(fc_k)
                inc   a
                ld    (fc_k),a
                cp    17                      ; rows k = 0..16
                jr    c,fc_loop
                ret

; fc_hline: HL = graphics y; draw from fc_xl to fc_xr in the current pen.
fc_hline
                ld    (fc_gy),hl
                ld    de,(fc_xl)
                ld    hl,(fc_gy)
                call  GRA_MOVE_ABS
                ld    de,(fc_xr)
                ld    hl,(fc_gy)
                call  GRA_LINE_ABS
                ret

; Half-width in pixels for rows 0..16 of a radius-16 circle (round(sqrt(256-k^2))).
circle_half
                db    16,16,16,16,15,15,15,14,14,13
                db    12,12,11,9,8,6,0

; --- State ---------------------------------------------------------------
; Rectangle parameters (inputs to draw_box / fill_rect) + fill scanline.
rx0             dw    0
ry0             dw    0
rx1             dw    0
ry1             dw    0
fr_y            dw    0

; Circle parameters (inputs to fill_circle) + scratch.
cir_cx          dw    0
cir_cy          dw    0
fc_k            db    0
fc_xl           dw    0
fc_xr           dw    0
fc_gy           dw    0
