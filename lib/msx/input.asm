; ---------------------------------------------------------------------------
; lib/msx/input.asm - GEOBENCH input layer for the MSX2 target (#287).
;
; Same abstract per-frame result as lib/input.asm (in_dx/in_dy signed deltas +
; in_fire/in_quit), fed from the MSX BIOS: GTSTCK 0 (cursor keys) merged with
; GTSTCK 1 (joystick port 1), GTTRIG 0/1 for select, and the keyboard matrix
; (SNSMAT row 7 bit 2) for ESC. The acceleration ramp is the CPC's, verbatim.
; The MSX standard mouse joins in M4 (GTPAD path).
;
; k_getkey also lives here (BIOS CHSNS/CHGET instead of the CPC KM buffer):
; cursor-key codes 28..31 are dropped - those keys ARE the pointer, and would
; otherwise flood a typing app exactly like the CPC's joystick-key gotcha.
; ---------------------------------------------------------------------------

; --- direction bits (shared semantics with the CPC layer) -------------------
DIR_UP           equ   1           ; UP -> dy += step (virtual Y grows upward)
DIR_DOWN         equ   2
DIR_LEFT         equ   4
DIR_RIGHT        equ   8

; msx_bios: call the main-BIOS entry in IX (CALSLT returns with DI - re-enable).
; MUST preserve IY: C apps frame on IY (--fomit-frame-pointer), and k_poll /
; k_getkey run inside app callbacks - same contract as the CPC firmware's
; IY-preservation that build_capp.sh relies on.
msx_bios
                push  iy
                ld    iy,(EXPTBL-1)          ; IYh = main BIOS slot
                call  CALSLT
                ei
                pop   iy
                ret

; msx_esc_held: NZ if the ESC key is currently held (matrix row 7, bit 2).
msx_esc_held
                push  bc
                push  de
                push  hl
                ld    a,7
                ld    ix,SNSMAT
                call  msx_bios
                pop   hl
                pop   de
                pop   bc
                cpl                           ; matrix bits are active-low
                and   1<<MSX_KEY_ESC
                ret

; GTPAD ids for a mouse in joystick port 1: 12 = presence/latch (also snapshots
; the counters), 13 = X offset since the last latch, 14 = Y offset (signed).
input_init
                xor   a
                ld    (in_accel),a
                ret

input_poll
                ld    hl,0
                ld    (in_dx),hl
                ld    (in_dy),hl
                xor   a
                ld    (in_fire),a
                ld    (in_quit),a
                ld    (in_joy_dirs),a
                xor   a                       ; stick 0 = cursor keys
                call  read_stick
                ld    a,1                     ; stick 1 = joystick port 1
                call  read_stick
                xor   a                       ; trigger 0 = space bar
                call  read_trig
                ld    a,1                     ; trigger 1 = joystick 1 button
                call  read_trig
                call  joy_to_delta
                call  read_mouse             ; MSX standard mouse (GTPAD, port 1)
                call  msx_esc_held
                ret   z
                ld    a,1
                ld    (in_quit),a
                ret

; read_mouse: latch the mouse counters (GTPAD 12), then add the X/Y offsets
; into in_dx/in_dy (x2: mouse counts ~ pixels, the pointer space is 2 units/px;
; Y sign flips - mouse-down is positive, cursor_y grows upward). A mouse's
; buttons arrive as joystick triggers, which read_trig already merges. With no
; mouse plugged the offsets read 0, so this is a no-op on joystick setups.
read_mouse
                ld    a,12                    ; presence + latch
                ld    ix,GTPAD
                call  msx_bios
                or    a
                ret   z                       ; no mouse in port 1
                ld    a,13                    ; X offset since last latch (signed byte)
                ld    ix,GTPAD
                call  msx_bios
                or    a
                jr    z,rm_y
                ld    e,a                     ; sign-extend into DE, then x2
                add   a,a
                sbc   a,a
                ld    d,a
                sla   e
                rl    d
                ld    hl,in_dx
                call  add_de_to
rm_y
                ld    a,14                    ; Y offset (positive = down)
                ld    ix,GTPAD
                call  msx_bios
                or    a
                ret   z
                ld    e,a                     ; sign-extend, negate (flip), x2
                add   a,a
                sbc   a,a
                ld    d,a
                xor   a                       ; DE = -DE
                sub   e
                ld    e,a
                ld    a,0
                sbc   a,d
                ld    d,a
                sla   e
                rl    d
                ld    hl,in_dy
                jp    add_de_to

; read_stick: A = stick id -> merge its direction (0..8) into in_joy_dirs.
read_stick
                ld    ix,GTSTCK
                call  msx_bios
                cp    9
                ret   nc                      ; defensive
                ld    e,a
                ld    d,0
                ld    hl,stick_dirs
                add   hl,de
                ld    a,(in_joy_dirs)
                or    (hl)
                ld    (in_joy_dirs),a
                ret
stick_dirs      db    0                        ; 0 = centre
                db    DIR_UP                   ; 1
                db    DIR_UP|DIR_RIGHT         ; 2
                db    DIR_RIGHT                ; 3
                db    DIR_DOWN|DIR_RIGHT       ; 4
                db    DIR_DOWN                 ; 5
                db    DIR_DOWN|DIR_LEFT        ; 6
                db    DIR_LEFT                 ; 7
                db    DIR_UP|DIR_LEFT          ; 8

; read_trig: A = trigger id -> in_fire |= pressed.
read_trig
                ld    ix,GTTRIG
                call  msx_bios
                or    a
                ret   z
                ld    a,1
                ld    (in_fire),a
                ret

; joy_to_delta: held directions -> a per-frame delta with the CPC's ramp.
joy_to_delta
                ld    a,(in_joy_dirs)
                or    a
                jr    nz,jd_held
                ld    (in_accel),a
                jr    jd_step
jd_held
                ld    a,(in_accel)
                inc   a
                cp    40
                jr    c,jd_accsave
                ld    a,39
jd_accsave
                ld    (in_accel),a
jd_step
                ld    a,(in_accel)
                cp    7
                ld    a,2
                jr    c,jd_havestep
                ld    a,12
jd_havestep
                ld    (in_step),a
                ld    a,(in_joy_dirs)
                ld    c,a
                bit   2,c                      ; LEFT
                jr    z,jd_right
                ld    hl,in_dx
                call  jd_substep
jd_right
                bit   3,c                      ; RIGHT
                jr    z,jd_up
                ld    hl,in_dx
                call  jd_addstep
jd_up
                bit   0,c                      ; UP
                jr    z,jd_down
                ld    hl,in_dy
                call  jd_addstep
jd_down
                bit   1,c                      ; DOWN
                ret   z
                ld    hl,in_dy
                jr    jd_substep
jd_addstep
                ld    a,(in_step)
                ld    e,a
                ld    d,0
                jp    add_de_to
jd_substep
                ld    a,(in_step)
                neg
                ld    e,a
                ld    d,#FF
                jp    add_de_to

; add_de_to: (HL) += DE (signed 16-bit).
add_de_to
                ld    a,(hl)
                add   a,e
                ld    (hl),a
                inc   hl
                ld    a,(hl)
                adc   a,d
                ld    (hl),a
                ret

; --- k_getkey (GB_GETKEY): A = a typed character, or 0 if none ---------------
k_getkey
                ld    ix,CHSNS
                call  msx_bios
                jr    z,kgk_none              ; ZF set = nothing waiting
                ld    ix,CHGET
                call  msx_bios
                cp    28                       ; 28..31 = cursor keys = the pointer:
                jr    c,kgk_have               ; drop them (they'd flood a typing app)
                cp    32
                jr    c,kgk_none
kgk_have
                or    a
                ret   nz
kgk_none
                xor   a
                ret

; --- State -------------------------------------------------------------------
in_dx           dw    0
in_dy           dw    0
in_fire         db    0
in_quit         db    0
in_joy_dirs     db    0
in_accel        db    0
in_step         db    0
