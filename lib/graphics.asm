; ---------------------------------------------------------------------------
; lib/graphics.asm - GEOBENCH graphics layer (save-under cursor)
;
; A software mouse pointer that preserves whatever is beneath it: before it is
; drawn, the pixels under each of its dots are read and stashed; when it moves,
; they are written back. So the pointer can travel anywhere - over the title
; bar, text, icons - without erasing what it passes over.
;
; This uses the firmware GRA_TEST/PLOT/SET_PEN per dot. That is the speed
; ceiling; a future fast path would write screen memory directly.
;
; Requires lib/firmware.inc. Assembled into the consumer; no org.
;
; Interface:
;   call cursor_show          draw the cursor at its current position
;   DE=x, HL=y : cursor_move_to   move it (no-op if unchanged)
;   cursor_x / cursor_y       current position (16-bit, read-only to callers)
;   clamp_lo / clamp_hi       unsigned 16-bit clamp helpers (HL vs DE)
; ---------------------------------------------------------------------------

POINTER_PEN     equ   2           ; the pointer is drawn in pen 2
ARM             equ   12          ; half-length of each cross arm (graphics units)
NPTS            equ   25          ; number of dots in the pointer shape

; ---------------------------------------------------------------------------
; Draw the cursor at its current position (first paint / re-show).
cursor_show
                jp    cursor_draw

; ---------------------------------------------------------------------------
; cursor_move_to: DE = new x, HL = new y. If unchanged, do nothing; otherwise
; restore the pixels under the old position, move, and draw at the new one.
cursor_move_to
                ld    a,(cursor_x)
                cp    e
                jr    nz,cm_diff
                ld    a,(cursor_x+1)
                cp    d
                jr    nz,cm_diff
                ld    a,(cursor_y)
                cp    l
                jr    nz,cm_diff
                ld    a,(cursor_y+1)
                cp    h
                jr    nz,cm_diff
                ret                        ; unchanged
cm_diff
                push  de
                push  hl
                call  cursor_erase          ; uses old cursor_x,cursor_y
                pop   hl
                pop   de
                ld    (cursor_x),de
                ld    (cursor_y),hl
                jp    cursor_draw            ; draw at new cursor_x,cursor_y

; ---------------------------------------------------------------------------
; cursor_draw: for each dot, read what's underneath into the save buffer, then
; plot the pointer pen over it. The pointer pen is constant, so it is set once;
; GRA_TEST_ABS does not disturb it.
cursor_draw
                ld    hl,points
                ld    (tptr),hl
                ld    hl,saved
                ld    (sptr),hl
                ld    a,NPTS
                ld    (cnt),a
                ld    a,POINTER_PEN
                call  GRA_SET_PEN
cd_loop
                call  get_point             ; DE = x, HL = y
                push  de
                push  hl
                call  GRA_TEST_ABS          ; A = pen currently under this dot
                ld    hl,(sptr)
                ld    (hl),a
                inc   hl
                ld    (sptr),hl
                pop   hl                     ; reload DE,HL (TEST trashed them)
                pop   de
                call  GRA_PLOT_ABS
                call  next_point
                jr    nz,cd_loop
                ret

; cursor_erase: write the saved pixels back at cursor_x,cursor_y. last_pen
; caches the pen so a run of same-pen dots (the usual case over the plain
; backdrop) only sets the pen once.
cursor_erase
                ld    hl,points
                ld    (tptr),hl
                ld    hl,saved
                ld    (sptr),hl
                ld    a,NPTS
                ld    (cnt),a
                ld    a,255                  ; invalidate the pen cache
                ld    (last_pen),a
ce_loop
                ld    hl,(sptr)
                ld    a,(hl)                 ; A = saved pen
                inc   hl
                ld    (sptr),hl
                ld    b,a
                ld    a,(last_pen)
                cp    b
                jr    z,ce_samepen
                ld    a,b
                call  GRA_SET_PEN
                ld    a,b
                ld    (last_pen),a
ce_samepen
                call  get_point             ; DE = x, HL = y
                call  GRA_PLOT_ABS
                call  next_point
                jr    nz,ce_loop
                ret

; ---------------------------------------------------------------------------
; Advance the points-table pointer and decrement the counter. Z when done.
next_point
                ld    hl,(tptr)
                inc   hl
                inc   hl
                ld    (tptr),hl
                ld    a,(cnt)
                dec   a
                ld    (cnt),a
                ret

; Compute the absolute coords of the current dot: DE = cursor_x + dx,
; HL = cursor_y + dy, where (dx,dy) is the signed pair at (tptr).
get_point
                ld    hl,(tptr)
                ld    a,(hl)                ; dx
                ld    hl,(cursor_x)
                call  add_signed            ; HL = cursor_x + dx
                ld    (tmp_x),hl
                ld    hl,(tptr)
                inc   hl
                ld    a,(hl)                ; dy
                ld    hl,(cursor_y)
                call  add_signed            ; HL = cursor_y + dy (the y coord)
                ld    de,(tmp_x)            ; the x coord
                ret

; HL = HL + sign_extend(A)
add_signed
                ld    e,a
                add   a,a                   ; carry = sign bit of the byte
                sbc   a,a                   ; A = 0xFF if negative else 0x00
                ld    d,a
                add   hl,de
                ret

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
; Pointer shape: a cross of NPTS dots as signed (dx,dy) offsets, one graphics
; pixel apart (2 units = 1 pixel in Mode 1).
points
                db    -12,0,-10,0,-8,0,-6,0,-4,0,-2,0,0,0
                db    2,0,4,0,6,0,8,0,10,0,12,0
                db    0,-12,0,-10,0,-8,0,-6,0,-4,0,-2
                db    0,2,0,4,0,6,0,8,0,10,0,12

; --- State ---------------------------------------------------------------
cursor_x        dw    320
cursor_y        dw    200
tptr            dw    0
sptr            dw    0
cnt             db    0
last_pen        db    255
tmp_x           dw    0
saved           defs  NPTS

; Rectangle parameters (inputs to draw_box / fill_rect) + fill scanline.
rx0             dw    0
ry0             dw    0
rx1             dw    0
ry1             dw    0
fr_y            dw    0
