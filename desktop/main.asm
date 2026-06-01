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

; --- Icon (graphics coords; ICON_Y0 is the lower edge) -------------------
ICON_X0         equ   80
ICON_X1         equ   160
ICON_Y0         equ   200
ICON_Y1         equ   280
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
                call  draw_icon              ; before the cursor, so it saves
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
                call  cursor_move_to

                call  handle_click

                ld    a,(in_quit)
                or    a
                jr    nz,quit
                jr    mainloop

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
; handle_click: on the frame fire/select first goes down (a rising edge), if
; the pointer is over the icon, toggle its selection and redraw its border.
handle_click
                ld    a,(in_fire)
                ld    b,a                     ; fire now
                ld    a,(last_fire)
                ld    c,a                     ; fire previous frame
                ld    a,b
                ld    (last_fire),a           ; remember for next frame
                or    a
                ret   z                       ; not held -> no click
                ld    a,c
                or    a
                ret   nz                      ; already held -> not an edge

                call  hit_test                ; carry set if pointer over icon
                ret   nc

                ld    a,(icon_selected)       ; toggle selection
                xor   1
                ld    (icon_selected),a

                call  cursor_erase            ; lift the cursor, redraw, replace
                call  draw_icon_border
                call  cursor_draw
                ret

; hit_test: carry set if the pointer (cursor_x,cursor_y) is over the icon body,
; carry clear otherwise.
hit_test
                ld    hl,(cursor_x)
                ld    de,ICON_X0
                call  cmp_hl_de
                jr    c,ht_out                ; x < X0
                ld    de,ICON_X1+1
                call  cmp_hl_de
                jr    nc,ht_out               ; x > X1  (not < X1+1)
                ld    hl,(cursor_y)
                ld    de,ICON_Y0
                call  cmp_hl_de
                jr    c,ht_out                ; y < Y0
                ld    de,ICON_Y1+1
                call  cmp_hl_de
                jr    nc,ht_out               ; y > Y1
                scf                            ; inside on both axes
                ret
ht_out
                or    a                        ; clear carry
                ret

; ---------------------------------------------------------------------------
; draw_icon: paint the icon body, border and label (once, at startup).
draw_icon
                call  set_icon_rect
                ld    a,PEN_BODY
                call  fill_rect
                call  draw_icon_border
                ld    a,1                     ; white label text
                call  TXT_SET_PEN
                ld    a,0                     ; on the blue backdrop
                call  TXT_SET_PAPER
                ld    hl,icon_label
                call  print_str
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

; Load the icon bounds into the shared rectangle parameters.
set_icon_rect
                ld    hl,ICON_X0
                ld    (rx0),hl
                ld    hl,ICON_Y0
                ld    (ry0),hl
                ld    hl,ICON_X1
                ld    (rx1),hl
                ld    hl,ICON_Y1
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
help_text       db    13,10,"  Move: arrows or joystick",13,10
                db    "  Fire / Space: select   ESC: quit",0

; Icon label, positioned with the locate control (31, column, row; 1-based).
icon_label      db    31,7,14,"Disk",0

spd             db    SPD_MIN
icon_selected   db    0
last_fire       db    0

end
                save  "GEOBENCH.BIN",geobench,end-geobench,DSK,"build/geobench.dsk"
