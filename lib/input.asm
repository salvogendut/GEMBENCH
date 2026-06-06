; ---------------------------------------------------------------------------
; lib/input.asm - GEOBENCH input layer
;
; Polls the input devices and reports an abstract result, so the rest of the
; system never reads hardware directly. The pointer is driven by the joystick
; port only (an AMX-style mouse / gamepad presents as the joystick); the cursor
; keys and Space are deliberately NOT read, so the whole keyboard is free for
; Notepad text entry. ESC is the one keyboard key kept here, as a universal quit
; (it is never a text character, so it does not clash with typing). A SYMBiFACE
; PS/2 mouse will be added here behind the same interface.
;
; Requires lib/firmware.inc (KM_TEST_KEY, KM_GET_JOYSTICK). Assembled into the
; consumer; no org.
;
; Interface:
;   call input_poll   -> in_dirs : bitmask of held directions (DIR_*)
;                        in_fire : non-zero if select/fire is held
;                        in_quit : non-zero if the user asked to quit
; ---------------------------------------------------------------------------

; --- CPC key numbers -----------------------------------------------------
KEY_UP          equ   0
KEY_RIGHT       equ   1
KEY_DOWN        equ   2
KEY_LEFT        equ   8
KEY_SPACE       equ   47
KEY_ESC         equ   66

; --- Direction bitmask returned in in_dirs -------------------------------
; These deliberately match the low nibble of the CPC joystick byte (bit 0 up,
; 1 down, 2 left, 3 right) so a joystick read drops straight into in_dirs.
DIR_UP          equ   1
DIR_DOWN        equ   2
DIR_LEFT        equ   4
DIR_RIGHT       equ   8

; --- Joystick byte bits (KM_GET_JOYSTICK) --------------------------------
JOY_FIRE2       equ   4           ; bit 4
JOY_FIRE1       equ   5           ; bit 5

; ---------------------------------------------------------------------------
input_poll
                xor   a
                ld    (in_dirs),a
                ld    (in_joy_dirs),a
                ld    (in_fire),a
                ld    (in_quit),a
                call  read_joystick          ; mouse/joystick -> directions + fire
                ld    a,(in_joy_dirs)        ; the pointer follows the joystick only
                ld    (in_dirs),a
                ld    a,KEY_ESC              ; ESC quits (not a text key, so it never
                call  KM_TEST_KEY            ; clashes with Notepad typing)
                ret   z
                ld    a,1
                ld    (in_quit),a
                ret

; ---------------------------------------------------------------------------
; Joystick 0: directions OR straight into in_dirs (matching bit layout);
; fire 1 = select, fire 2 = quit.
read_joystick
                call  KM_GET_JOYSTICK       ; A = joystick 0 state
                ld    c,a                   ; keep the raw byte in C

                and   #0F                   ; bits 0..3 == DIR_* directions
                ld    b,a
                ld    a,(in_joy_dirs)
                or    b
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

; --- State ---------------------------------------------------------------
in_dirs         db    0            ; held directions (DIR_*), from the joystick
in_joy_dirs     db    0            ; joystick/mouse directions (scratch)
in_fire         db    0
in_quit         db    0
