; ---------------------------------------------------------------------------
; GEOBENCH - desktop shell
;
; Paints the desktop (Mode 1 backdrop, title bar, help line) and runs the main
; loop: poll input, move the pointer, quit on request. The pointer, save-under
; drawing and input reads live in the lib/ modules assembled in below.
;
; Built by tools/build.sh into build/geobench.dsk as GEOBENCH.BIN.
; ---------------------------------------------------------------------------

                include "../lib/firmware.inc"

                org   #4000
geobench
                jp    desktop_start          ; AMSDOS entry point at #4000

; --- Library modules (assembled in) --------------------------------------
                include "../lib/input.asm"
                include "../lib/graphics.asm"

; --- Palette (firmware ink numbers 0..26) --------------------------------
INK_DESKTOP     equ   1           ; blue        -> pen 0 (paper / backdrop)
INK_LIGHT       equ   26          ; bright white-> pen 1 (title bar, text)
INK_DARK        equ   0           ; black       -> pen 2 (pointer, outlines)
INK_ACCENT      equ   6           ; bright red  -> pen 3 (accents)

; --- Pointer movement / bounds (graphics coords: 0..639 x, 0..399 y) -----
; The pointer accelerates while a direction is held: it starts at SPD_MIN for
; precise taps and ramps by SPD_INC each frame up to SPD_MAX, resetting to
; SPD_MIN whenever no direction is held.
SPD_MIN         equ   4           ; step on the first frame of a press
SPD_INC         equ   2           ; added each held frame
SPD_MAX         equ   24          ; top speed (12 px/frame in Mode 1)
PXMIN           equ   ARM
PXMAX           equ   639-ARM
PYMIN           equ   ARM
PYMAX           equ   399-ARM

; --- Icon (graphics coords; icon_x,icon_y is the lower-left corner) -------
; The icon is draggable, so its position lives in icon_x/icon_y at runtime.
; Drag bounds keep it on the plain backdrop (below the text rows) so erasing
; the old position by filling with the backdrop pen stays correct.
ICON_W          equ   80           ; width  (40 px in Mode 1)
ICON_H          equ   80           ; height (40 px)
ICON_X_INIT     equ   80
ICON_Y_INIT     equ   140
IXMIN           equ   4
IXMAX           equ   639-ICON_W-4
IYMIN           equ   4
; Keep the icon's top edge below the text. Text fills rows 0-1 (pixel lines
; 0-15); graphics y maps to line 199 - y/2, so the top (icon_y+ICON_H) must be
; <= 366 to stay at line 16 or below.
IYMAX           equ   366-ICON_H
PEN_DESKTOP     equ   0            ; backdrop (used to erase the icon)
PEN_BODY        equ   1            ; white icon body
PEN_BORDER      equ   2            ; black border when idle
PEN_SELECT      equ   3            ; accent border when selected

; ---------------------------------------------------------------------------
desktop_start
                ld    a,1
                call  SCR_SET_MODE           ; Mode 1, 320x200, 4 pens. Clears.
                call  set_palette
                call  draw_title_bar
                call  draw_help
                call  draw_icon_shape        ; before the cursor, so it saves
                call  cursor_show            ;   the icon pixels underneath

; --- Main loop -----------------------------------------------------------
mainloop
                call  MC_WAIT_FLYBACK        ; pace at 50 Hz, redraw in vblank
                call  input_poll             ; -> in_dirs, in_quit

                ld    a,(in_dirs)            ; keep the direction mask in B
                ld    b,a
                call  update_speed           ; -> C = this frame's step

                ld    hl,(cursor_x)          ; target x
                bit   2,b                    ; DIR_LEFT
                jr    z,ml_xr
                ld    e,c
                ld    d,0
                or    a
                sbc   hl,de
                jr    nc,ml_xr               ; floor underflow to 0
                ld    hl,0
ml_xr
                bit   3,b                    ; DIR_RIGHT
                jr    z,ml_xc
                ld    e,c
                ld    d,0
                add   hl,de
ml_xc
                ld    de,PXMIN
                call  clamp_lo
                ld    de,PXMAX
                call  clamp_hi
                push  hl                     ; stash target x

                ld    hl,(cursor_y)          ; target y
                bit   0,b                    ; DIR_UP -> +y
                jr    z,ml_yd
                ld    e,c
                ld    d,0
                add   hl,de
ml_yd
                bit   1,b                    ; DIR_DOWN -> -y
                jr    z,ml_yc
                ld    e,c
                ld    d,0
                or    a
                sbc   hl,de
                jr    nc,ml_yc               ; floor underflow to 0
                ld    hl,0
ml_yc
                ld    de,PYMIN
                call  clamp_lo
                ld    de,PYMAX
                call  clamp_hi

                pop   de                     ; DE = target x, HL = target y
                ld    (tgt_x),de
                ld    (tgt_y),hl

                ld    a,(dragging)
                or    a
                jr    nz,ml_drag
                ld    de,(tgt_x)             ; not dragging: just move the cursor
                ld    hl,(tgt_y)
                call  cursor_move_to
                jr    ml_fire
ml_drag
                call  drag_frame             ; dragging: move icon + cursor together
ml_fire
                call  handle_fire

                ld    a,(in_quit)
                or    a
                jr    nz,quit
                jp    mainloop

quit
                ld    a,1                     ; tidy the screen on the way out
                call  SCR_SET_MODE
                ret

; ---------------------------------------------------------------------------
; update_speed: B = direction mask. With a direction held, accelerate spd by
; SPD_INC up to SPD_MAX; otherwise reset to SPD_MIN. Returns the step in C.
update_speed
                ld    a,b
                or    a
                jr    z,us_reset             ; nothing held -> back to base speed
                ld    a,(spd)
                add   a,SPD_INC
                cp    SPD_MAX
                jr    c,us_store
                ld    a,SPD_MAX
                jr    us_store
us_reset
                ld    a,SPD_MIN
us_store
                ld    (spd),a
                ld    c,a
                ret

; ---------------------------------------------------------------------------
; handle_fire: edge-detect the fire/select button.
;   - rising edge over the icon  -> start dragging (and select it)
;   - rising edge over empty space -> deselect any selection
;   - falling edge -> stop dragging
; The frame-by-frame icon follow is done in drag_frame, not here.
handle_fire
                ld    a,(in_fire)
                ld    b,a                     ; fire now
                ld    a,(last_fire)
                ld    c,a                     ; fire previous frame
                ld    a,b
                ld    (last_fire),a           ; remember for next frame

                or    a
                jr    nz,hf_down              ; held now?
                ; released: drop the icon if we were dragging
                ld    a,(dragging)
                or    a
                ret   z
                jp    drop_icon
hf_down
                ld    a,c
                or    a
                ret   nz                      ; already held -> not a new press

                call  hit_test                ; carry set if pointer over icon
                jr    c,hf_grab
                ; pressed on empty space -> deselect if needed
                ld    a,(icon_selected)
                or    a
                ret   z
                xor   a
                ld    (icon_selected),a
                jp    redraw_border
hf_grab
                jp    grab_icon

; redraw_border: lift the cursor, redraw the icon border, put the cursor back.
redraw_border
                call  cursor_erase
                call  draw_icon_border
                call  cursor_draw
                ret

; ---------------------------------------------------------------------------
; grab_icon: begin a drag. Erase the filled icon (it becomes "transparent")
; and replace it with a lightweight outline that the pointer drags around.
grab_icon
                ld    a,1
                ld    (dragging),a
                ld    a,1
                ld    (icon_selected),a
                ld    hl,(cursor_x)           ; grab offset = cursor - icon corner
                ld    de,(icon_x)
                or    a
                sbc   hl,de
                ld    (grab_dx),hl
                ld    hl,(cursor_y)
                ld    de,(icon_y)
                or    a
                sbc   hl,de
                ld    (grab_dy),hl
                ld    hl,(icon_x)            ; outline starts where the icon is
                ld    (drag_x),hl
                ld    hl,(icon_y)
                ld    (drag_y),hl

                call  cursor_erase
                call  erase_icon              ; remove the filled icon
                call  draw_outline            ; show the drag outline
                call  cursor_draw
                ret

; drop_icon: end a drag. Erase the outline and stamp the filled icon at the
; outline's final position.
drop_icon
                xor   a
                ld    (dragging),a
                call  cursor_erase
                call  erase_outline
                ld    hl,(drag_x)            ; commit the new icon position
                ld    (icon_x),hl
                ld    hl,(drag_y)
                ld    (icon_y),hl
                call  draw_icon_shape
                call  cursor_draw
                ret

; ---------------------------------------------------------------------------
; drag_frame: move the outline to follow the pointer (target - grab offset)
; and the cursor to its target, recompositing only if something moved.
drag_frame
                ld    hl,(tgt_x)             ; new outline x = tgt_x - grab_dx
                ld    de,(grab_dx)
                or    a
                sbc   hl,de
                jr    nc,df_xok
                ld    hl,0                    ; floor underflow
df_xok
                ld    de,IXMIN
                call  clamp_lo
                ld    de,IXMAX
                call  clamp_hi
                ld    (nicon_x),hl

                ld    hl,(tgt_y)             ; new outline y = tgt_y - grab_dy
                ld    de,(grab_dy)
                or    a
                sbc   hl,de
                jr    nc,df_yok
                ld    hl,0
df_yok
                ld    de,IYMIN
                call  clamp_lo
                ld    de,IYMAX
                call  clamp_hi
                ld    (nicon_y),hl

                ld    hl,(tgt_x)             ; anything moved? (cursor or outline)
                ld    de,(cursor_x)
                or    a
                sbc   hl,de
                jr    nz,df_go
                ld    hl,(tgt_y)
                ld    de,(cursor_y)
                or    a
                sbc   hl,de
                jr    nz,df_go
                ld    hl,(nicon_x)
                ld    de,(drag_x)
                or    a
                sbc   hl,de
                jr    nz,df_go
                ld    hl,(nicon_y)
                ld    de,(drag_y)
                or    a
                sbc   hl,de
                ret   z                       ; nothing moved -> leave it be
df_go
                call  cursor_erase            ; lift cursor from old position
                call  erase_outline           ; erase outline at the old spot
                ld    hl,(nicon_x)            ; commit new outline position
                ld    (drag_x),hl
                ld    hl,(nicon_y)
                ld    (drag_y),hl
                call  draw_outline            ; draw outline at the new spot
                ld    hl,(tgt_x)             ; move cursor to its target
                ld    (cursor_x),hl
                ld    hl,(tgt_y)
                ld    (cursor_y),hl
                call  cursor_draw             ; save under new spot + draw cursor
                ret

; erase_icon: fill the icon's current rectangle with the backdrop pen.
erase_icon
                call  set_icon_rect
                ld    a,PEN_DESKTOP
                call  fill_rect
                ret

; draw_outline: box outline at the drag position, in the accent pen.
draw_outline
                call  set_drag_rect
                ld    a,PEN_SELECT
                call  draw_box
                ret

; erase_outline: redraw the outline box in the backdrop pen (safe because the
; drag area is clamped to the plain backdrop).
erase_outline
                call  set_drag_rect
                ld    a,PEN_DESKTOP
                call  draw_box
                ret

; Load the outline's current bounds into the shared rectangle parameters.
set_drag_rect
                ld    hl,(drag_x)
                ld    (rx0),hl
                ld    hl,(drag_y)
                ld    (ry0),hl
                ld    hl,(drag_x)
                ld    de,ICON_W
                add   hl,de
                ld    (rx1),hl
                ld    hl,(drag_y)
                ld    de,ICON_H
                add   hl,de
                ld    (ry1),hl
                ret

; hit_test: carry set if the pointer (cursor_x,cursor_y) is over the icon,
; carry clear otherwise. Bounds come from the runtime icon position.
hit_test
                ld    hl,(cursor_x)          ; x >= icon_x ?
                ld    de,(icon_x)
                call  cmp_hl_de
                jr    c,ht_out
                ld    hl,(icon_x)            ; x <= icon_x + ICON_W ?
                ld    de,ICON_W+1
                add   hl,de
                ex    de,hl                   ; DE = icon_x + ICON_W + 1
                ld    hl,(cursor_x)
                call  cmp_hl_de
                jr    nc,ht_out
                ld    hl,(cursor_y)          ; y >= icon_y ?
                ld    de,(icon_y)
                call  cmp_hl_de
                jr    c,ht_out
                ld    hl,(icon_y)            ; y <= icon_y + ICON_H ?
                ld    de,ICON_H+1
                add   hl,de
                ex    de,hl                   ; DE = icon_y + ICON_H + 1
                ld    hl,(cursor_y)
                call  cmp_hl_de
                jr    nc,ht_out
                scf                            ; inside on both axes
                ret
ht_out
                or    a                        ; clear carry
                ret

; ---------------------------------------------------------------------------
; draw_icon_shape: paint the icon body and border at its current position.
draw_icon_shape
                call  set_icon_rect
                ld    a,PEN_BODY
                call  fill_rect
                call  draw_icon_border
                ret

; draw_icon_border: outline the icon, accent pen if selected else border pen.
draw_icon_border
                call  set_icon_rect
                ld    a,(icon_selected)
                or    a
                ld    a,PEN_BORDER
                jr    z,dib_draw
                ld    a,PEN_SELECT
dib_draw
                call  draw_box
                ret

; Load the icon's current bounds into the shared rectangle parameters.
set_icon_rect
                ld    hl,(icon_x)
                ld    (rx0),hl
                ld    hl,(icon_y)
                ld    (ry0),hl
                ld    hl,(icon_x)
                ld    de,ICON_W
                add   hl,de
                ld    (rx1),hl
                ld    hl,(icon_y)
                ld    de,ICON_H
                add   hl,de
                ld    (ry1),hl
                ret

; ---------------------------------------------------------------------------
; Set up the four-pen desktop palette and a matching border.
set_palette
                ld    a,0
                ld    b,INK_DESKTOP
                ld    c,INK_DESKTOP
                call  SCR_SET_INK
                ld    a,1
                ld    b,INK_LIGHT
                ld    c,INK_LIGHT
                call  SCR_SET_INK
                ld    a,2
                ld    b,INK_DARK
                ld    c,INK_DARK
                call  SCR_SET_INK
                ld    a,3
                ld    b,INK_ACCENT
                ld    c,INK_ACCENT
                call  SCR_SET_INK
                ld    b,INK_DESKTOP
                ld    c,INK_DESKTOP
                call  SCR_SET_BORDER
                ret

; Full-width white title bar on row 0: black text on white paper.
draw_title_bar
                ld    a,2
                call  TXT_SET_PEN
                ld    a,1
                call  TXT_SET_PAPER
                ld    hl,title_text
                call  print_str
                ret

; Help line below the bar, white text on the blue backdrop.
draw_help
                ld    a,1
                call  TXT_SET_PEN
                ld    a,0
                call  TXT_SET_PAPER
                ld    hl,help_text
                call  print_str
                ret

; Print a zero-terminated string via TXT_OUTPUT (interprets CR/LF).
print_str
                ld    a,(hl)
                or    a
                ret   z
                call  TXT_OUTPUT
                inc   hl
                jr    print_str

; --- Desktop data --------------------------------------------------------
title_text      db    " GEOBENCH                               ",0
; Help on row 1, placed with the locate control (31, column, row; 1-based) so
; its position is independent of where the title left the cursor.
help_text       db    31,1,2,"  Hold Fire/Space to drag   ESC: quit",0

; --- Mutable state -------------------------------------------------------
spd             db    SPD_MIN
icon_selected   db    0
last_fire       db    0
dragging        db    0
icon_x          dw    ICON_X_INIT
icon_y          dw    ICON_Y_INIT
drag_x          dw    0
drag_y          dw    0
grab_dx         dw    0
grab_dy         dw    0
nicon_x         dw    0
nicon_y         dw    0
tgt_x           dw    0
tgt_y           dw    0

end
                save  "GEOBENCH.BIN",geobench,end-geobench,DSK,"build/geobench.dsk"
