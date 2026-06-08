; ---------------------------------------------------------------------------
; lib/input.asm - GEOBENCH input layer
;
; Polls the pointer devices and reports an abstract per-frame result, so the
; rest of the system never reads hardware directly. The mouse takes precedence:
; the joystick drives the pointer only as a FALLBACK when no mouse is present, so
; an idle/noisy joystick can't fight a real mouse (input_poll gates it on
; mouse_enabled).
;   - SYMBiFACE II PS/2 mouse (port #FD10), polled only when a SymbiFace is
;     detected - the pointer when present.
;   - joystick port (KM_GET_JOYSTICK; an AMX-style mouse/gamepad presents as the
;     joystick). Held directions -> a stepped delta, with an acceleration ramp.
;     The fallback when no mouse is detected. #FD10 returns 0x00 both when idle AND when no mouse is fitted, so
;     a mouse cannot be sensed at rest - we just read its packets when they come.
;     The port floats on a board with no SymbiFace, so it is gated behind a
;     presence probe (the SymbiFace IDE controller answering fs_ide_present).
; Both feed a signed per-frame delta (in_dx/in_dy, cursor units); the kernel's
; poll_move applies it. ESC is the one keyboard key read here (universal quit;
; never a text char, so it does not clash with Notepad typing).
;
; Requires lib/firmware.inc (KM_TEST_KEY, KM_GET_JOYSTICK) and fs_ide_present
; (lib/fs.asm). Assembled into the consumer; no org.
;
; Interface:
;   call input_init   -> probe for a SymbiFace; enable the mouse if present
;   call input_poll   -> in_dx/in_dy : signed pointer delta this frame
;                        in_fire      : non-zero if select/click is held
;                        in_quit      : non-zero if the user asked to quit
; ---------------------------------------------------------------------------

KEY_ESC          equ   66

; --- Direction bits (low nibble of the CPC joystick byte) ---------------
DIR_UP           equ   1
DIR_DOWN         equ   2
DIR_LEFT         equ   4
DIR_RIGHT        equ   8

JOY_FIRE2        equ   4           ; KM_GET_JOYSTICK bit 4
JOY_FIRE1        equ   5           ; bit 5

FS_MOUSE         equ   #FD10       ; SYMBiFACE II PS/2 mouse status port
MOUSE_SHIFT      equ   1           ; delta scale: << this (1 = x2, ~1 px per unit)
MOUSE_MAXPKT     equ   8           ; burst-read safety cap (protocol emits <=4)

; ---------------------------------------------------------------------------
; input_init: enable the mouse only if a SymbiFace is present. Its IDE controller
; answers fs_ide_present; the mouse port floats on a board without one, which
; would otherwise inject noise. Joystick-only when absent.
;
; #104: an Albireo box has no SymbiFace IDE to probe, so fs_ide_present is the
; wrong signal there - it would leave the pointer dead. On an Albireo build enable
; the mouse unconditionally (#FD10 is the pointer; the SymbiFace mouse, or a USB
; mouse on real hardware, drives it). TODO: read the Albireo USB HID directly.
input_init
                xor   a
                ld    (mouse_enabled),a
                ld    (mouse_btn_state),a
                if STORAGE_ALBIREO
                ld    a,1
                ld    (mouse_enabled),a
                ret
                else
                call  fs_ide_present
                ret   nc
                ld    a,1
                ld    (mouse_enabled),a
                ret
                endif

; ---------------------------------------------------------------------------
input_poll
                ld    hl,0
                ld    (in_dx),hl
                ld    (in_dy),hl
                xor   a
                ld    (in_fire),a
                ld    (in_quit),a
                ld    (in_joy_dirs),a
                ld    a,(mouse_enabled)       ; the joystick is a FALLBACK: only drive the
                or    a                        ; pointer from it when NO mouse is present, so a
                jr    nz,ip_mouse              ; noisy/idle joystick can't fight a real mouse
                call  read_joystick          ; -> in_joy_dirs, in_fire, in_quit
                call  joy_to_delta           ; held dirs (+ accel) -> in_dx/in_dy
ip_mouse
                call  read_mouse             ; SymbiFace mouse -> in_dx/in_dy + buttons
                ld    a,KEY_ESC              ; ESC quits (never a text key)
                call  KM_TEST_KEY
                ret   z
                ld    a,1
                ld    (in_quit),a
                ret

; read_joystick: directions -> in_joy_dirs; fire 1 = select, fire 2 = quit.
read_joystick
                call  KM_GET_JOYSTICK
                ld    c,a
                and   #0F                     ; bits 0..3 = DIR_* directions
                ld    (in_joy_dirs),a
                bit   JOY_FIRE1,c
                jr    z,rj_fire2
                ld    a,1
                ld    (in_fire),a
rj_fire2
                bit   JOY_FIRE2,c
                ret   z
                ld    a,1
                ld    (in_quit),a
                ret

; joy_to_delta: held directions -> a per-frame delta, with the acceleration ramp
; (a tap nudges ~1px; held a while moves faster).
joy_to_delta
                ld    a,(in_joy_dirs)
                or    a
                jr    nz,jd_held
                ld    (in_accel),a            ; nothing held -> reset the ramp
                jr    jd_step
jd_held
                ld    a,(in_accel)
                inc   a
                cp    40
                jr    c,jd_accsave
                ld    a,39                     ; cap the ramp counter
jd_accsave
                ld    (in_accel),a
jd_step
                ld    a,(in_accel)
                cp    7
                ld    a,2                      ; 2 units (~1px): precise
                jr    c,jd_havestep
                ld    a,12                     ; held a while -> 12 units (~6px): fast
jd_havestep
                ld    (in_step),a
                ld    a,(in_joy_dirs)
                ld    c,a
                bit   2,c                      ; LEFT -> dx -= step
                jr    z,jd_right
                ld    hl,in_dx
                call  jd_substep
jd_right
                bit   3,c                      ; RIGHT -> dx += step
                jr    z,jd_up
                ld    hl,in_dx
                call  jd_addstep
jd_up
                bit   0,c                      ; UP -> dy += step (screen up = +cursor_y)
                jr    z,jd_down
                ld    hl,in_dy
                call  jd_addstep
jd_down
                bit   1,c                      ; DOWN -> dy -= step
                ret   z
                ld    hl,in_dy
                jr    jd_substep
jd_addstep                                     ; (HL) += in_step  [HL -> word]
                ld    a,(in_step)
                ld    e,a
                ld    d,0
                jp    add_de_to
jd_substep                                     ; (HL) -= in_step
                ld    a,(in_step)
                neg
                ld    e,a
                ld    d,#FF
                jp    add_de_to

; ---------------------------------------------------------------------------
; read_mouse: burst-read #FD10, accumulating X/Y deltas (scaled) into in_dx/in_dy
; and the latest button state. Button packets only arrive on a change, so the
; held state is kept in mouse_btn_state and applied every frame.
read_mouse
                ld    a,(mouse_enabled)
                or    a
                ret   z
                ld    a,MOUSE_MAXPKT
                ld    (rm_count),a
rm_loop
                ld    bc,FS_MOUSE
                in    a,(c)
                or    a
                jr    z,rm_apply              ; 0x00 = no more data
                ld    e,a                      ; keep the raw packet
                bit   7,a
                jr    nz,rm_hi
                ld    a,e                      ; m=01 -> X offset (+ = right)
                call  mouse_sext6
                call  mouse_scale
                ld    hl,in_dx
                call  add_de_to
                jr    rm_next
rm_hi
                bit   6,a
                jr    nz,rm_btnscroll
                ld    a,e                      ; m=10 -> Y offset (+ = up = +cursor_y)
                call  mouse_sext6
                call  mouse_scale
                ld    hl,in_dy
                call  add_de_to
                jr    rm_next
rm_btnscroll
                bit   5,a                      ; m=11: D5 0=buttons, 1=scroll
                jr    nz,rm_next               ; scroll -> ignored for now
                ld    a,e
                and   #1F                       ; buttons (b0=L b1=R b2=M ...)
                ld    (mouse_btn_state),a
rm_next
                ld    a,(rm_count)
                dec   a
                ld    (rm_count),a
                jr    nz,rm_loop
rm_apply
                ld    a,(mouse_btn_state)      ; held left button -> select/click
                bit   0,a
                jr    z,rm_noL
                ld    a,1
                ld    (in_fire),a
rm_noL
                ld    a,(mouse_btn_state)      ; held right button -> quit
                bit   1,a
                ret   z
                ld    a,1
                ld    (in_quit),a
                ret

; mouse_sext6: A = packet -> DE = sign-extended 6-bit data (bit5 = sign).
mouse_sext6
                and   #3F
                ld    e,a
                ld    d,0
                bit   5,e
                ret   z
                ld    a,e
                or    #C0
                ld    e,a
                ld    d,#FF
                ret

; mouse_scale: DE <<= MOUSE_SHIFT.
mouse_scale
                ld    b,MOUSE_SHIFT
ms_shl          sla   e
                rl    d
                djnz  ms_shl
                ret

; add_de_to: (HL) += DE (signed 16-bit); HL -> word variable.
add_de_to
                ld    a,(hl)
                add   a,e
                ld    (hl),a
                inc   hl
                ld    a,(hl)
                adc   a,d
                ld    (hl),a
                ret

; --- State ---------------------------------------------------------------
in_dx           dw    0            ; signed pointer delta this frame (cursor units)
in_dy           dw    0
in_fire         db    0            ; select/click held
in_quit         db    0            ; quit requested
in_joy_dirs     db    0            ; joystick directions (scratch)
in_accel        db    0            ; joystick acceleration ramp counter
in_step         db    0            ; joystick step this frame
mouse_enabled   db    0            ; 1 = a SymbiFace is present, poll the mouse
mouse_btn_state db    0            ; latest mouse button bits (persists across frames)
rm_count        db    0            ; mouse burst-read counter
