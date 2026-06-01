; ---------------------------------------------------------------------------
; lib/firmware.inc - Amstrad CPC firmware jumpblock equates (standard addresses)
;
; Equates only, no code: safe to include before the org so it shifts nothing.
; ---------------------------------------------------------------------------

; --- Screen pack ---------------------------------------------------------
SCR_SET_MODE    equ   #BC0E       ; A = mode
SCR_SET_BORDER  equ   #BC38       ; B,C = hardware ink (B=C for steady)
SCR_SET_INK     equ   #BC32       ; A = pen, B,C = hardware ink

; --- Text VDU ------------------------------------------------------------
TXT_OUTPUT      equ   #BB5A       ; A = char (interprets control codes)
TXT_SET_PEN     equ   #BB90       ; A = pen
TXT_SET_PAPER   equ   #BB96       ; A = pen

; --- Graphics VDU --------------------------------------------------------
GRA_SET_PEN     equ   #BBDE       ; A = pen
GRA_MOVE_ABS    equ   #BBC0       ; DE = x, HL = y  (move graphics cursor)
GRA_LINE_ABS    equ   #BBF6       ; DE = x, HL = y  (line to, in current pen)
GRA_PLOT_ABS    equ   #BBEA       ; DE = x, HL = y  (plot in current pen)
GRA_TEST_ABS    equ   #BBF0       ; DE = x, HL = y  -> A = pen at that point

; --- Keyboard ------------------------------------------------------------
KM_TEST_KEY     equ   #BB1E       ; A = key number; exit NZ if pressed
KM_GET_JOYSTICK equ   #BB24       ; A = joystick 0 state, H = joystick 1

; --- Machine pack --------------------------------------------------------
MC_WAIT_FLYBACK equ   #BD19       ; wait for frame flyback
