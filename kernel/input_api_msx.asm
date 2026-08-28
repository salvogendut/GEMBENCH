; kernel/input_api_msx.asm - frame-paced poll API for the MSX2 target (#287).
;
; The MSX counterpart of kernel/input_api.asm. Identical flow and published
; results (POLL_MX/POLL_MY/POLL_FLAGS, byte col + line + click/quit/fire), but
; the frame pace comes from the H.TIMI tick instead of MC_WAIT_FLYBACK, and
; the virtual pointer space is 512x212: cursor_x 0..1022 (2 units/pixel,
; byte col = x/8), cursor_y 0..422 (line = 211 - y/2, Y flipped like the CPC).

k_poll
                call  input_poll             ; in_dx/in_dy + in_fire/in_quit
                call  poll_move              ; -> DE = new x, HL = new y (clamped)
                call  msx_wait_tick          ; pace to the VBLANK tick
                call  cursor_move_to         ; hardware sprite: update-only, no erase
                call  clock_tick
                ld    hl,(cursor_x)          ; cursor byte col = cursor_x / 8
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                ld    (poll_byte),a
                ld    hl,(cursor_y)          ; cursor line = 211 - cursor_y / 2
                srl   h
                rr    l
                ld    a,211
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
                ld    a,d
                ld    (POLL_FLAGS),a
                ld    a,(poll_byte)
                ld    (POLL_MX),a
                ld    b,a
                ld    a,(poll_line)
                ld    (POLL_MY),a
                ld    c,a
                ret
poll_lastfire   db    0
poll_byte       equ   #14A2
poll_line       equ   #14A3

; poll_move: apply the per-frame delta, clamped to the 512x212 virtual space.
poll_move
                ld    hl,(cursor_x)
                ld    de,(in_dx)
                add   hl,de
                call  clamp1022
                ld    (pm_newx),hl
                ld    hl,(cursor_y)
                ld    de,(in_dy)
                add   hl,de
                call  clamp422
                ld    de,(pm_newx)
                ret
pm_newx         equ   #14A0
clamp1022
                ld    de,1022
                jr    clamp_hl
clamp422
                ld    de,422
clamp_hl                                       ; clamp HL to [0, DE]
                bit   7,h
                jr    z,ch_hi
                ld    hl,0
                ret
ch_hi
                push  hl
                or    a
                sbc   hl,de
                pop   hl
                ret   c
                ex    de,hl
                ret
