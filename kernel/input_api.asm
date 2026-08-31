; kernel/input_api.asm - frame-paced poll API and cursor delta handling.

; --- input + cursor services ---------------------------------------------
; GB_CURSHOW draws the pointer (apps call it once after drawing their UI); the jump
; table goes straight to cursor_show now (#148, reclaimed the k_curshow wrapper).

; k_poll: frame-paced input poll. Moves the cursor by the held directions and
; redraws it; returns B = cursor byte col, C = cursor line, D flags: bit0 = a
; fresh click (fire just pressed), bit1 = quit (ESC). Interrupts must be on so
; the firmware scans the keyboard.
k_poll
                call  input_poll             ; in_dx/in_dy + in_fire/in_quit
                call  poll_move              ; -> DE = new x, HL = new y (clamped)
                call  MC_WAIT_FLYBACK        ; pace to 50 Hz; do the move in the blank
                call  cursor_move_to         ; erases+redraws ONLY if the position
                                             ; actually changed (re-drawing in place,
                                             ; e.g. holding a key into the edge clamp,
                                             ; corrupts the save-under). In the flyback
                                             ; blank so the move isn't seen mid-frame.
                                             ; MUST precede clock_tick: it consumes the
                                             ; DE/HL target that clock_tick would clobber.
                call  clock_tick             ; keep the top-bar clock live
                ld    hl,(cursor_x)          ; cursor byte col = cursor_x / 8
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                ld    (poll_byte),a
                ld    hl,(cursor_y)          ; cursor line = 199 - cursor_y / 2
                srl   h
                rr    l
                ld    a,199
                sub   l
                ld    (poll_line),a
                ld    d,0
                ld    a,(in_fire)            ; click edge = fire & !last_fire
                ld    e,a
                ld    a,(poll_lastfire)
                cpl
                and   e
                jr    z,gp_noclick
                set   0,d
gp_noclick
                ld    a,e
                ld    (poll_lastfire),a
                ld    a,(in_quit)
                or    a
                jr    z,gp_noquit
                set   1,d
gp_noquit
                ld    a,(in_fire)            ; bit2 = fire currently held (for drag)
                or    a
                jr    z,gp_nohold
                set   2,d
gp_nohold
                call  menu_dispatch          ; kernel-owned top-bar click -> app
                ld    a,d                     ; publish the result to fixed low RAM so a
                ld    (POLL_FLAGS),a          ; WM callback can read it without re-polling
                ld    a,(poll_byte)           ; (gb_mx/gb_my/gb_flags read these)
                ld    (POLL_MX),a
                ld    b,a
                ld    a,(poll_line)
                ld    (POLL_MY),a
                ld    c,a
                ret
poll_lastfire   db    0
poll_byte       equ   #14A2        ; #196: relocated to low RAM (write-before-read scratch)
poll_line       equ   #14A3        ; #196: relocated to low RAM

; poll_move: apply the per-frame pointer delta (in_dx/in_dy, from input_poll -
; joystick step and/or SymbiFace mouse) to the cursor, clamped to the screen.
; Returns DE = new x, HL = new y. Does NOT write cursor_x/y - cursor_move_to does
; that, redrawing only when the position actually changes.
poll_move
                ld    hl,(cursor_x)
                ld    de,(in_dx)             ; signed delta this frame
                add   hl,de
                call  clamp638
                ld    (pm_newx),hl
                ld    hl,(cursor_y)
                ld    de,(in_dy)
                add   hl,de
                call  clamp398
                ld    de,(pm_newx)
                ret
pm_newx         equ   #14A0        ; #196: relocated to low RAM (write-before-read scratch)
clamp638
                ld    de,638
                jr    clamp_hl
clamp398
                ld    de,398
clamp_hl                                       ; clamp HL to [0, DE]
                bit   7,h                     ; negative -> 0
                jr    z,ch_hi
                ld    hl,0
                ret
ch_hi
                push  hl
                or    a
                sbc   hl,de
                pop   hl
                ret   c                        ; HL < DE -> keep
                ex    de,hl                    ; clamp to DE
                ret
