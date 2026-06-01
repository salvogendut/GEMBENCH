; ---------------------------------------------------------------------------
; GEOBENCH - milestone 1: bare desktop
;
; Boots, switches to Mode 1, paints a desktop backdrop with a title bar, and
; draws a mouse pointer in the centre. Then it parks in an idle loop so the
; desktop stays on screen (reset / F12 to leave).
;
; This is the smallest runnable artifact that proves the toolchain end to end
; (RASM -> .dsk -> emulator). Input / pointer movement come in a later
; milestone, once lib/input exists.
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
GRA_MOVE_ABS    equ   #BBC0       ; DE = x, HL = y
GRA_LINE_ABS    equ   #BBF6       ; DE = x, HL = y

; --- Palette (firmware ink numbers 0..26) --------------------------------
INK_DESKTOP     equ   1           ; blue   -> pen 0 (paper / backdrop)
INK_LIGHT       equ   26          ; bright white -> pen 1 (title bar, text)
INK_DARK        equ   0           ; black  -> pen 2 (pointer, outlines)
INK_ACCENT      equ   6           ; bright red -> pen 3 (accents)

; ---------------------------------------------------------------------------
start
                ld    a,1
                call  SCR_SET_MODE          ; Mode 1, 320x200, 4 pens. Clears.

                call  set_palette
                call  draw_title_bar
                call  draw_body
                call  draw_pointer

idle            jr    idle                  ; park: keep the desktop on screen

; ---------------------------------------------------------------------------
; Set up the four-pen desktop palette and a matching border.
set_palette
                ld    a,0                   ; pen 0 = desktop blue
                ld    b,INK_DESKTOP
                ld    c,INK_DESKTOP
                call  SCR_SET_INK
                ld    a,1                   ; pen 1 = bright white
                ld    b,INK_LIGHT
                ld    c,INK_LIGHT
                call  SCR_SET_INK
                ld    a,2                   ; pen 2 = black
                ld    b,INK_DARK
                ld    c,INK_DARK
                call  SCR_SET_INK
                ld    a,3                   ; pen 3 = accent
                ld    b,INK_ACCENT
                ld    c,INK_ACCENT
                call  SCR_SET_INK
                ld    b,INK_DESKTOP         ; border matches the desktop
                ld    c,INK_DESKTOP
                call  SCR_SET_BORDER
                ret

; ---------------------------------------------------------------------------
; Print a full-width white title bar across the top row (row 0): black text
; on a white paper, padded with spaces to fill all 40 columns.
draw_title_bar
                ld    a,2                   ; black text
                call  TXT_SET_PEN
                ld    a,1                   ; on white paper
                call  TXT_SET_PAPER
                ld    hl,title_text
                call  print_str
                ret

; ---------------------------------------------------------------------------
; A line of body text on the blue backdrop, a couple of rows down.
draw_body
                ld    a,1                   ; white text
                call  TXT_SET_PEN
                ld    a,0                   ; on the desktop (blue) paper
                call  TXT_SET_PAPER
                ld    hl,body_text
                call  print_str
                ret

; ---------------------------------------------------------------------------
; Draw the mouse pointer as a black cross in the centre of the screen.
; Graphics coordinates: origin bottom-left, 0..639 x by 0..399 y.
draw_pointer
                ld    a,2                   ; black pen
                call  GRA_SET_PEN
                ld    de,308                ; horizontal stroke
                ld    hl,198
                call  GRA_MOVE_ABS
                ld    de,332
                ld    hl,198
                call  GRA_LINE_ABS
                ld    de,320                ; vertical stroke
                ld    hl,186
                call  GRA_MOVE_ABS
                ld    de,320
                ld    hl,210
                call  GRA_LINE_ABS
                ret

; ---------------------------------------------------------------------------
; Print a zero-terminated string via TXT_OUTPUT (interprets CR/LF).
print_str
                ld    a,(hl)
                or    a
                ret   z
                call  TXT_OUTPUT
                inc   hl
                jr    print_str

; ---------------------------------------------------------------------------
; Data. The title is padded to a full 40-column row so the whole bar is white.
title_text      db    " GEOBENCH                               ",0
body_text       db    13,10,13,10,"  Welcome to GEOBENCH - milestone 1",13,10
                db    "  A GEOS / Workbench-style desktop for the CPC.",0

end
                save  "GEOBENCH.BIN",start,end-start,DSK,"build/geobench.dsk"
