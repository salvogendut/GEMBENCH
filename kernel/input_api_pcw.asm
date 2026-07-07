; kernel/input_api_pcw.asm - frame-paced poll API for the PCW target (#331).
;
; The PCW counterpart of kernel/input_api.asm / input_api_msx.asm. Identical
; flow and published results (POLL_MX/POLL_MY/POLL_FLAGS, byte col + line +
; click/quit/fire), but the frame pace comes from the ASIC flyback bit (port
; #F8 read, bit 6 - GEOBENCH runs DI, so it polls the rising edge), and the
; virtual pointer space is 360x248: cursor_x 0..718 (2 units/pixel, byte col
; = x/8), cursor_y 0..494 (line = 247 - y/2, Y flipped like the CPC/MSX).
; cursor_move_to is the software pointer: it erases + redraws itself.

k_poll
                call  input_poll             ; in_dx/in_dy + in_fire/in_quit
                call  poll_move              ; -> DE = new x, HL = new y (clamped)
                call  pcw_wait_frame         ; pace to the frame flyback
                call  cursor_move_to
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
                ld    hl,(cursor_y)          ; cursor line = 247 - cursor_y / 2
                srl   h
                rr    l
                ld    a,247
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

; pcw_wait_frame: block until the next frame flyback rising edge (#F8 bit 6).
pcw_wait_frame
pwf_hi
                in    a,(PCW_SYSCTL)
                bit   6,a
                jr    nz,pwf_hi              ; wait out the current flyback
pwf_lo
                in    a,(PCW_SYSCTL)
                bit   6,a
                jr    z,pwf_lo               ; catch the rising edge
                ret

; poll_move: apply the per-frame delta, clamped to the 360x248 virtual space.
poll_move
                ld    hl,(cursor_x)
                ld    de,(in_dx)
                add   hl,de
                call  clamp718
                ld    (pm_newx),hl
                ld    hl,(cursor_y)
                ld    de,(in_dy)
                add   hl,de
                call  clamp494
                ld    de,(pm_newx)
                ret
pm_newx         equ   #14A0
clamp718
                ld    de,718
                jr    clamp_hl
clamp494
                ld    de,494
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
