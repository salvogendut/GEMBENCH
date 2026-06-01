; ---------------------------------------------------------------------------
; GEOBENCH - milestone 3: save-under pointer
;
; Boots, switches to Mode 1, paints a desktop backdrop with a title bar and a
; help line, then runs a main loop: read the cursor keys, move a pointer, and
; redraw it. The pointer is "save-under": before it is drawn, the pixels beneath
; it are read and stashed; when it moves, they are written back. So the pointer
; can travel anywhere - over the title bar and text included - without erasing
; what is underneath. ESC quits back to BASIC.
;
; Movement is keyboard-only for now (arrow keys). Joystick / AMX-mouse reads
; layer on top of this once lib/input is factored out.
;
; Built by tools/build.sh into build/geobench.dsk as GEOBENCH.BIN.
; ---------------------------------------------------------------------------

                org   #4000

; --- Firmware jumpblock (standard CPC addresses) -------------------------
SCR_SET_MODE    equ   #BC0E       ; A = mode
SCR_SET_BORDER  equ   #BC38       ; B,C = hardware ink (B=C for steady)
SCR_SET_INK     equ   #BC32       ; A = pen, B,C = hardware ink
TXT_SET_PEN     equ   #BB90       ; A = pen
TXT_SET_PAPER   equ   #BB96       ; A = pen
TXT_OUTPUT      equ   #BB5A       ; A = char (interprets control codes)
GRA_SET_PEN     equ   #BBDE       ; A = pen
GRA_PLOT_ABS    equ   #BBEA       ; DE = x, HL = y  (plot in current pen)
GRA_TEST_ABS    equ   #BBF0       ; DE = x, HL = y  -> A = pen at that point
KM_TEST_KEY     equ   #BB1E       ; A = key number; exit NZ if pressed
MC_WAIT_FLYBACK equ   #BD19       ; wait for frame flyback

; --- Palette (firmware ink numbers 0..26) --------------------------------
INK_DESKTOP     equ   1           ; blue        -> pen 0 (paper / backdrop)
INK_LIGHT       equ   26          ; bright white-> pen 1 (title bar, text)
INK_DARK        equ   0           ; black       -> pen 2 (pointer, outlines)
INK_ACCENT      equ   6           ; bright red  -> pen 3 (accents)
POINTER_PEN     equ   2           ; the pointer is drawn in pen 2 (black)

; --- Key numbers ---------------------------------------------------------
KEY_UP          equ   0
KEY_RIGHT       equ   1
KEY_DOWN        equ   2
KEY_LEFT        equ   8
KEY_ESC         equ   66

; --- Pointer geometry / movement (graphics coords: 0..639 x, 0..399 y) ---
ARM             equ   12          ; half-length of each cross arm
NPTS            equ   25          ; number of pixels in the pointer shape
STEP            equ   8           ; pixels moved per frame while a key is held
PXMIN           equ   ARM
PXMAX           equ   639-ARM
PYMIN           equ   ARM
PYMAX           equ   399-ARM

; ---------------------------------------------------------------------------
start
                ld    a,1
                call  SCR_SET_MODE          ; Mode 1, 320x200, 4 pens. Clears.

                call  set_palette
                call  draw_title_bar
                call  draw_help

                call  save_draw            ; draw the pointer at its start point

; --- Main loop -----------------------------------------------------------
mainloop
                call  MC_WAIT_FLYBACK       ; pace at 50 Hz, redraw in vblank
                call  read_keys             ; -> npx,npy (clamped)

                ld    hl,(npx)              ; moved?
                ld    de,(px)
                or    a
                sbc   hl,de
                jr    nz,moved
                ld    hl,(npy)
                ld    de,(py)
                or    a
                sbc   hl,de
                jr    z,check_esc           ; unchanged -> leave pointer be

moved
                call  restore               ; put back the pixels under the old pos
                ld    hl,(npx)
                ld    (px),hl
                ld    hl,(npy)
                ld    (py),hl
                call  save_draw             ; stash + draw at the new pos

check_esc
                ld    a,KEY_ESC
                call  KM_TEST_KEY
                jr    nz,quit
                jr    mainloop

quit
                ld    a,1                    ; tidy the screen on the way out
                call  SCR_SET_MODE
                ret

; ---------------------------------------------------------------------------
; Read the cursor keys into npx,npy (a stepped, clamped copy of px,py).
read_keys
                ld    hl,(px)
                ld    (npx),hl
                ld    hl,(py)
                ld    (npy),hl

                ld    a,KEY_LEFT
                call  KM_TEST_KEY
                jr    z,rk_right
                ld    hl,(npx)
                ld    de,STEP
                or    a
                sbc   hl,de
                ld    (npx),hl
rk_right
                ld    a,KEY_RIGHT
                call  KM_TEST_KEY
                jr    z,rk_up
                ld    hl,(npx)
                ld    de,STEP
                add   hl,de
                ld    (npx),hl
rk_up
                ld    a,KEY_UP             ; up = increasing graphics y
                call  KM_TEST_KEY
                jr    z,rk_down
                ld    hl,(npy)
                ld    de,STEP
                add   hl,de
                ld    (npy),hl
rk_down
                ld    a,KEY_DOWN
                call  KM_TEST_KEY
                jr    z,rk_clamp
                ld    hl,(npy)
                ld    de,STEP
                or    a
                sbc   hl,de
                ld    (npy),hl
rk_clamp
                ld    hl,(npx)
                ld    de,PXMIN
                call  clamp_lo
                ld    de,PXMAX
                call  clamp_hi
                ld    (npx),hl
                ld    hl,(npy)
                ld    de,PYMIN
                call  clamp_lo
                ld    de,PYMAX
                call  clamp_hi
                ld    (npy),hl
                ret

; HL = max(HL,DE)  (unsigned)
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

; HL = min(HL,DE)  (unsigned)
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

; ---------------------------------------------------------------------------
; save_draw: for each pointer pixel, read what's underneath into the save
; buffer, then plot the pointer pen over it. Uses px,py. The pointer pen is
; constant, so it is set once; GRA_TEST_ABS does not disturb it.
save_draw
                ld    hl,points
                ld    (tptr),hl
                ld    hl,saved
                ld    (sptr),hl
                ld    a,NPTS
                ld    (cnt),a
                ld    a,POINTER_PEN
                call  GRA_SET_PEN
sd_loop
                call  get_point            ; DE = x, HL = y
                push  de
                push  hl
                call  GRA_TEST_ABS         ; A = pen currently under this pixel
                ld    hl,(sptr)
                ld    (hl),a
                inc   hl
                ld    (sptr),hl
                pop   hl                    ; reload DE,HL (TEST trashed them)
                pop   de
                call  GRA_PLOT_ABS
                call  next_point
                jr    nz,sd_loop
                ret

; restore: write the saved pixels back at px,py (erasing the pointer cleanly).
; last_pen caches the current pen so a run of same-pen pixels (the usual case
; over the plain backdrop) only sets the pen once.
restore
                ld    hl,points
                ld    (tptr),hl
                ld    hl,saved
                ld    (sptr),hl
                ld    a,NPTS
                ld    (cnt),a
                ld    a,255                 ; invalidate the pen cache
                ld    (last_pen),a
rs_loop
                ld    hl,(sptr)
                ld    a,(hl)               ; A = saved pen
                inc   hl
                ld    (sptr),hl
                ld    b,a
                ld    a,(last_pen)
                cp    b
                jr    z,rs_samepen
                ld    a,b
                call  GRA_SET_PEN
                ld    a,b
                ld    (last_pen),a
rs_samepen
                call  get_point            ; DE = x, HL = y
                call  GRA_PLOT_ABS
                call  next_point
                jr    nz,rs_loop
                ret

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

; Compute the absolute coords of the current pointer pixel: DE = px + dx,
; HL = py + dy, where (dx,dy) is the signed pair at (tptr).
get_point
                ld    hl,(tptr)
                ld    a,(hl)              ; dx
                ld    hl,(px)
                call  add_signed          ; HL = px + dx
                ld    (tmp_x),hl
                ld    hl,(tptr)
                inc   hl
                ld    a,(hl)              ; dy
                ld    hl,(py)
                call  add_signed          ; HL = py + dy  (the y coord)
                ld    de,(tmp_x)          ; the x coord
                ret

; HL = HL + sign_extend(A)
add_signed
                ld    e,a
                add   a,a                ; carry = sign bit of the byte
                sbc   a,a                ; A = 0xFF if negative else 0x00
                ld    d,a
                add   hl,de
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

; ---------------------------------------------------------------------------
; Data
title_text      db    " GEOBENCH                               ",0
help_text       db    13,10,"  Arrows: move pointer    ESC: quit",0

; Pointer shape: a cross of NPTS pixels as signed (dx,dy) offsets, one graphics
; pixel apart (2 units = 1 pixel in Mode 1).
points
                db    -12,0,-10,0,-8,0,-6,0,-4,0,-2,0,0,0
                db    2,0,4,0,6,0,8,0,10,0,12,0
                db    0,-12,0,-10,0,-8,0,-6,0,-4,0,-2
                db    0,2,0,4,0,6,0,8,0,10,0,12

; Mutable state
px              dw    320
py              dw    200
npx             dw    320
npy             dw    200
tptr            dw    0
sptr            dw    0
cnt             db    0
last_pen        db    255
tmp_x           dw    0
saved           defs  NPTS

end
                save  "GEOBENCH.BIN",start,end-start,DSK,"build/geobench.dsk"
