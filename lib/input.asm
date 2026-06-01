; ---------------------------------------------------------------------------
; lib/input.asm - GEOBENCH input layer
;
; Polls the input devices and reports an abstract result, so the rest of the
; system never reads hardware directly. Today that is the keyboard (cursor keys
; + ESC); an AMX-style joystick-port read and a SYMBiFACE PS/2 mouse will be
; added here behind the same interface.
;
; Requires lib/firmware.inc (KM_TEST_KEY). Assembled into the consumer; no org.
;
; Interface:
;   call input_poll   -> in_dirs : bitmask of held directions (DIR_*)
;                        in_quit : non-zero if the user asked to quit
; ---------------------------------------------------------------------------

; --- CPC key numbers -----------------------------------------------------
KEY_UP          equ   0
KEY_RIGHT       equ   1
KEY_DOWN        equ   2
KEY_LEFT        equ   8
KEY_ESC         equ   66

; --- Direction bitmask returned in in_dirs -------------------------------
DIR_UP          equ   1
DIR_DOWN        equ   2
DIR_LEFT        equ   4
DIR_RIGHT       equ   8

; ---------------------------------------------------------------------------
input_poll
                xor   a
                ld    (in_dirs),a
                ld    (in_quit),a

                ld    a,KEY_UP
                call  KM_TEST_KEY
                jr    z,ip_down
                ld    a,(in_dirs)
                or    DIR_UP
                ld    (in_dirs),a
ip_down
                ld    a,KEY_DOWN
                call  KM_TEST_KEY
                jr    z,ip_left
                ld    a,(in_dirs)
                or    DIR_DOWN
                ld    (in_dirs),a
ip_left
                ld    a,KEY_LEFT
                call  KM_TEST_KEY
                jr    z,ip_right
                ld    a,(in_dirs)
                or    DIR_LEFT
                ld    (in_dirs),a
ip_right
                ld    a,KEY_RIGHT
                call  KM_TEST_KEY
                jr    z,ip_quit
                ld    a,(in_dirs)
                or    DIR_RIGHT
                ld    (in_dirs),a
ip_quit
                ld    a,KEY_ESC
                call  KM_TEST_KEY
                jr    z,ip_done
                ld    a,1
                ld    (in_quit),a
ip_done
                ret

; --- State ---------------------------------------------------------------
in_dirs         db    0
in_quit         db    0
