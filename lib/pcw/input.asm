; ---------------------------------------------------------------------------
; lib/pcw/input.asm - GEOBENCH input layer for the PCW target (#331).
;
; Same abstract per-frame result as lib/input.asm / lib/msx/input.asm
; (in_dx/in_dy signed deltas + in_fire/in_quit), fed from:
;   - the DK'tronics AY board joystick: select register 14 via port #AA,
;     read port #A9 - ACTIVE-LOW, bit2=L bit3=R bit4=D bit5=U bit6=fire.
;     With no board fitted the port reads #FF = idle, so the merge is safe.
;   - the keyboard matrix, memory-mapped at #FFF0-#FFFF when physical
;     block 3 is in the slot-3 window - ACTIVE-HIGH, refreshed ~300 Hz by
;     the keyboard MCU. Cursor keys merge into the pointer (like the MSX's
;     GTSTCK 0), SPACE doubles as fire (like the MSX's trigger 0), and the
;     EXIT key (host Esc) sets in_quit.
; The acceleration ramp is the CPC's, verbatim.
;
; k_getkey scans matrix rows 0-10 itself (the PCW has no firmware): newly
; pressed bits against a previous-state copy, mapped through a normal/shift
; ASCII table (Joyce matrix layout, UK legends). Cursor keys and modifiers
; are masked - they are the pointer, not typing. No auto-repeat yet.
;
; Both routines remap the slot-3 window to the keyboard block; per the
; platform convention (lib/pcw/glue.inc) every slot-3 user maps what it
; needs before use, so no restore is required.
; ---------------------------------------------------------------------------

; --- direction bits (shared semantics with the CPC/MSX layers) --------------
DIR_UP           equ   1           ; UP -> dy += step (virtual Y grows upward)
DIR_DOWN         equ   2
DIR_LEFT         equ   4
DIR_RIGHT        equ   8

input_init
                xor   a
                ld    (in_accel),a
                ; seed the previous-state matrix so keys held across boot
                ; don't type a ghost character on the first k_getkey
kb_snapshot
                ld    a,PCW_BLK_KBD
                out   (PCW_BANK3),a
                ld    hl,PCW_KBDMAT
                ld    de,kb_prev
                ld    bc,11
                ldir
                ret

input_poll
                ld    hl,0
                ld    (in_dx),hl
                ld    (in_dy),hl
                xor   a
                ld    (in_fire),a
                ld    (in_quit),a
                ; --- DK'tronics joystick: AY register 14, active-low --------
                ld    a,14
                out   (#AA),a                 ; AY register select
                in    a,(#A9)                 ; AY register read
                cpl                           ; pressed = 1
                ld    b,a
                xor   a                       ; A = direction accumulator
                bit   5,b
                jr    z,ip_j1
                or    DIR_UP
ip_j1
                bit   4,b
                jr    z,ip_j2
                or    DIR_DOWN
ip_j2
                bit   2,b
                jr    z,ip_j3
                or    DIR_LEFT
ip_j3
                bit   3,b
                jr    z,ip_j4
                or    DIR_RIGHT
ip_j4
                ld    c,a
                bit   6,b
                jr    z,ip_j5
                ld    a,1
                ld    (in_fire),a
ip_j5
                ; --- keyboard: arrows/space/EXIT from the matrix ------------
                ld    a,PCW_BLK_KBD
                out   (PCW_BANK3),a
                ld    a,(PCW_KBDMAT+1)        ; row 1: b6 = UP, b7 = LEFT, b0 = EXIT
                ld    b,a
                bit   6,b
                jr    z,ip_k1
                ld    a,c
                or    DIR_UP
                ld    c,a
ip_k1
                bit   7,b
                jr    z,ip_k2
                ld    a,c
                or    DIR_LEFT
                ld    c,a
ip_k2
                bit   0,b
                jr    z,ip_k3
                ld    a,1
                ld    (in_quit),a
ip_k3
                ld    a,(PCW_KBDMAT+0)        ; row 0: b6 = RIGHT
                bit   6,a
                jr    z,ip_k4
                ld    a,c
                or    DIR_RIGHT
                ld    c,a
ip_k4
                ld    a,(PCW_KBDMAT+10)       ; row 10: b6 = DOWN
                bit   6,a
                jr    z,ip_k5
                ld    a,c
                or    DIR_DOWN
                ld    c,a
ip_k5
                ld    a,(PCW_KBDMAT+5)        ; row 5: b7 = SPACE -> fire
                bit   7,a
                jr    z,ip_k6
                ld    a,1
                ld    (in_fire),a
ip_k6
                ld    a,c
                ld    (in_joy_dirs),a
                ; fall through into joy_to_delta

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
; Newly-pressed matrix bits (rows 0-10) against kb_prev, through the
; normal/shift table. Pointer keys and modifiers are masked out; unmapped
; keys are skipped, not returned as 0.
k_getkey
                ld    a,PCW_BLK_KBD
                out   (PCW_BANK3),a
                ld    hl,PCW_KBDMAT           ; snapshot the live matrix
                ld    de,kb_cur
                ld    bc,11
                ldir
                ld    b,0                     ; B = row
kg_row
                ld    a,b
                cp    11
                jr    nc,kg_none
                push  bc
                ld    e,b                     ; new = cur & ~prev & ~ignore
                ld    d,0
                ld    hl,kb_cur
                add   hl,de
                ld    a,(hl)
                ld    hl,kb_prev
                add   hl,de
                ld    c,(hl)
                ld    hl,kb_ign
                add   hl,de
                ld    e,a
                ld    a,c
                cpl
                and   e
                ld    e,a
                ld    a,(hl)
                cpl
                and   e
                pop   bc
                or    a
                jr    z,kg_next
                ld    c,a                     ; C = new-press bits, walk them
                ld    d,0                     ; D = bit index
kg_bit
                srl   c
                jr    nc,kg_bnext
                push  bc                      ; candidate: index = row*8 + bit
                push  de
                ld    a,b
                add   a,a
                add   a,a
                add   a,a
                add   a,d                     ; A = index
                ld    e,a
                ld    d,0
                ld    a,(kb_cur+2)            ; SHIFT held? (row 2 bit 5)
                and   #20
                ld    hl,key_norm
                jr    z,kg_tab
                ld    hl,key_shift
kg_tab
                add   hl,de
                ld    a,(hl)
                pop   de
                pop   bc
                or    a
                jr    z,kg_bnext              ; unmapped: keep scanning
                push  af                      ; commit: prev = cur, return char
                call  kb_commit
                pop   af
                ret
kg_bnext
                inc   d
                ld    a,d
                cp    8
                jr    c,kg_bit
kg_next
                inc   b
                jr    kg_row
kg_none
                call  kb_commit
                xor   a
                ret

kb_commit
                ld    hl,kb_cur
                ld    de,kb_prev
                ld    bc,11
                ldir
                ret

; --- matrix -> ASCII (Joyce layout, UK legends; 0 = not a typing key) --------
; rows 0..10, bit 0..7 within each row.
key_norm
                db    0,'0',0,0,'3','9',0,'5'          ; 0: keypad + PASTE/right
                db    27,0,0,0,0,'7',0,0               ; 1: EXIT,PTR,CUT,COPY,DOC,kp7,up,left
                db    127,']',13,0,'1',0,92,'+'        ; 2: DEL>,],RETURN,-,kp1,SHIFT,\,[+]
                db    '=','-','[','p',39,';','/','.'   ; 3
                db    '0','9','o','i','l','k','m',','  ; 4
                db    '8','7','u','y','h','j','n',32   ; 5
                db    '6','5','r','t','g','f','b','v'  ; 6
                db    '4','3','e','w','s','d','c','x'  ; 7
                db    '1','2','#','q',9,'a',0,'z'      ; 8: ...,TAB,a,CAPS,z
                db    0,0,0,0,0,0,0,127                ; 9: <-DEL
                db    0,0,0,'-',0,13,0,0               ; 10: ALT,CAN,[-],kpENTER,down
key_shift
                db    0,'0',0,0,'3','9',0,'5'
                db    27,0,0,0,0,'7',0,0
                db    127,'}',13,0,'1',0,'|','+'
                db    '+','_','{','P',64,':','?','>'
                db    '_',')','O','I','L','K','M','<'
                db    '(',39,'U','Y','H','J','N',32
                db    '&','%','R','T','G','F','B','V'
                db    '$','#','E','W','S','D','C','X'
                db    '!',34,'#','Q',9,'A',0,'Z'
                db    0,0,0,0,0,0,0,127
                db    0,0,0,'-',0,13,0,0

; bits that never type: the pointer's arrow keys + modifiers
kb_ign
                db    #40                      ; row 0: RIGHT
                db    #C0                      ; row 1: UP, LEFT
                db    #20                      ; row 2: SHIFT
                db    0,0,0,0,0,0,0
                db    #42                      ; row 10: DOWN, ALT

; --- State -------------------------------------------------------------------
in_dx           dw    0
in_dy           dw    0
in_fire         db    0
in_quit         db    0
in_joy_dirs     db    0
in_accel        db    0
in_step         db    0
kb_prev         ds    11
kb_cur          ds    11
