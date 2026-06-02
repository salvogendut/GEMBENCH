; ---------------------------------------------------------------------------
; lib/input.asm - GEOBENCH input layer
;
; Polls the input devices and reports an abstract result, so the rest of the
; system never reads hardware directly. Today it reads the keyboard (cursor
; keys + Space + ESC) and the joystick port (an AMX-style mouse presents as the
; joystick). A SYMBiFACE PS/2 mouse will be added here behind the same
; interface for machines that have the board.
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
                ld    (in_kbd_dirs),a
                ld    (in_joy_dirs),a
                ld    (in_fire),a
                ld    (in_quit),a
                call  read_keyboard          ; -> in_kbd_dirs
                call  read_joystick          ; -> in_joy_dirs
                ld    a,(in_kbd_dirs)        ; in_dirs = keyboard OR joystick
                ld    b,a
                ld    a,(in_joy_dirs)
                or    b
                ld    (in_dirs),a
                ret

; ---------------------------------------------------------------------------
; Keyboard: cursor keys move, Space = fire/select, ESC = quit.
read_keyboard
                ld    a,KEY_UP
                call  KM_TEST_KEY
                jr    z,rk_down
                ld    a,(in_kbd_dirs)
                or    DIR_UP
                ld    (in_kbd_dirs),a
rk_down
                ld    a,KEY_DOWN
                call  KM_TEST_KEY
                jr    z,rk_left
                ld    a,(in_kbd_dirs)
                or    DIR_DOWN
                ld    (in_kbd_dirs),a
rk_left
                ld    a,KEY_LEFT
                call  KM_TEST_KEY
                jr    z,rk_right
                ld    a,(in_kbd_dirs)
                or    DIR_LEFT
                ld    (in_kbd_dirs),a
rk_right
                ld    a,KEY_RIGHT
                call  KM_TEST_KEY
                jr    z,rk_fire
                ld    a,(in_kbd_dirs)
                or    DIR_RIGHT
                ld    (in_kbd_dirs),a
rk_fire
                ld    a,KEY_SPACE
                call  KM_TEST_KEY
                jr    z,rk_quit
                ld    a,1
                ld    (in_fire),a
rk_quit
                ld    a,KEY_ESC
                call  KM_TEST_KEY
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
in_dirs         db    0            ; keyboard OR joystick directions (DIR_*)
in_kbd_dirs     db    0            ; keyboard-only directions (window list scroll)
in_joy_dirs     db    0            ; joystick/mouse-only directions
in_fire         db    0
in_quit         db    0
