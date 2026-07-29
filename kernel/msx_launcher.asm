; GBMSX.COM - next-boot Screen 6/Screen 7 dispatcher.
;
; GEOBENCH.CFG remains the single settings store. MSXMODE=7 selects
; GBMSX7.COM; an absent, invalid, or MSXMODE=6 value selects GBMSX6.COM.
; MSXMOUSE=TRUE enables the standard GTPAD mouse, as does a manual /M option.
; Stage 2 runs briefly from the top of GEOBENCH's reserved page-3 glue area
; while DOS loads the selected .COM over this launcher at #0100.

                include "../lib/msx/bios.inc"

STAGE_ADDR      equ   #C800
STAGE_LIMIT     equ   #C900
LOAD_MAX        equ   #3F00        ; selected stubs are guarded below 16K
_STROUT         equ   #09

                org   #100

start
                ld    a,6
                ld    (stage_mode),a
                xor   a
                ld    (stage_mouse),a

                ; Preserve the mode-independent /M option while this selector
                ; chain-loads the real Screen 6/7 program over itself.
                ld    hl,#0080
                ld    b,(hl)
                ld    a,b
                or    a
                jr    z,arg_done
arg_scan        inc   hl
                ld    a,(hl)
                and   #DF
                cp    'M'
                jr    nz,arg_next
                ld    a,1
                ld    (stage_mouse),a
                jr    arg_done
arg_next        djnz  arg_scan
arg_done

                ld    de,cfg_name
                ld    a,1                     ; read-only
                ld    c,_DOPEN
                call  BDOS
                or    a
                jp    nz,cfg_done             ; absent config: compatibility Mode 6
                ld    a,b
                ld    (cfg_handle),a
                ld    de,cfg_buf
                ld    hl,512
                ld    c,_READ
                call  BDOS
                or    a
                jp    nz,cfg_close
                ld    de,cfg_buf
                add   hl,de
                ld    (hl),0                  ; sentinel (cfg_buf has one spare byte)
                ld    hl,cfg_buf
cfg_scan
                ld    a,(hl)
                or    a
                jp    z,cfg_close
                cp    'M'
                jr    nz,cfg_next
                push  hl
                inc   hl
                ld    a,(hl)
                cp    'S'
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    'X'
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    'M'
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    'O'
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    'D'
                jr    z,cfg_mode
                cp    'U'
                jr    z,cfg_mouse
                jr    cfg_nomatch
cfg_mode        inc   hl
                ld    a,(hl)
                cp    'E'
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    #3D
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    '7'
                jr    nz,cfg_nomatch
                ld    a,7
                ld    (stage_mode),a
                jr    cfg_nomatch
cfg_mouse       inc   hl
                ld    a,(hl)
                cp    'S'
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    'E'
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    #3D
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    'T'
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    'R'
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    'U'
                jr    nz,cfg_nomatch
                inc   hl
                ld    a,(hl)
                cp    'E'
                jr    nz,cfg_nomatch
                ld    a,1
                ld    (stage_mouse),a
cfg_nomatch     pop   hl
cfg_next        inc   hl
                jr    cfg_scan

cfg_close       ld    a,(cfg_handle)
                ld    b,a
                ld    c,_DCLOSE
                call  BDOS
cfg_done
                ld    hl,(#0006)             ; the relocated stage must fit in the TPA
                ld    de,STAGE_LIMIT
                or    a
                sbc   hl,de
                jr    nc,loader_relocate
                ld    de,msg_tpa
                ld    c,_STROUT
                call  BDOS
                ld    c,_TERM0
                jp    BDOS

loader_relocate ld    hl,stage2
                ld    de,STAGE_ADDR
                ld    bc,stage2_end-stage2
                ldir
                jp    STAGE_ADDR

cfg_name        db    "GEOBENCH.CFG",0
cfg_handle      db    0
msg_tpa         db    "GEOBENCH selector: TPA too small",13,10,"$"
cfg_buf         ds    513

; All absolute references in this block use their relocated addresses.
stage2
                ld    a,(stage_mode_r)
                cp    7
                ld    de,stage_name6_r
                jr    nz,stage_open
                ld    de,stage_name7_r
stage_open      ld    a,1
                ld    c,_DOPEN
                call  BDOS
                or    a
                jr    nz,stage_fail
                ld    a,b
                ld    (stage_handle_r),a
                ld    de,#100
                ld    hl,LOAD_MAX
                ld    c,_READ
                call  BDOS
                or    a
                jr    nz,stage_close_fail
                ld    a,h                     ; a full buffer means a malformed/oversize stub
                cp    LOAD_MAX/#100
                jr    nz,stage_loaded
                ld    a,l
                or    a
                jr    z,stage_close_fail
stage_loaded    ld    a,(stage_handle_r)
                ld    b,a
                ld    c,_DCLOSE
                call  BDOS
                ld    a,(stage_mouse_r)
                or    a
                jr    z,stage_run
                ld    a,2                     ; pass "/M" to the selected loader
                ld    (#0080),a
                ld    a,'/'
                ld    (#0081),a
                ld    a,'M'
                ld    (#0082),a
                ld    a,13
                ld    (#0083),a
stage_run
                jp    #100

stage_close_fail
                ld    a,(stage_handle_r)
                ld    b,a
                ld    c,_DCLOSE
                call  BDOS
stage_fail      ld    de,stage_msg_r
                ld    c,_STROUT
                call  BDOS
                ld    c,_TERM0
                jp    BDOS

stage_mode      db    6
stage_mouse     db    0
stage_handle    db    0
stage_name6     db    "GBMSX6.COM",0
stage_name7     db    "GBMSX7.COM",0
stage_msg       db    "GEOBENCH selector: video image missing",13,10,"$"
stage2_end

stage_mode_r    equ   STAGE_ADDR+stage_mode-stage2
stage_mouse_r   equ   STAGE_ADDR+stage_mouse-stage2
stage_handle_r  equ   STAGE_ADDR+stage_handle-stage2
stage_name6_r   equ   STAGE_ADDR+stage_name6-stage2
stage_name7_r   equ   STAGE_ADDR+stage_name7-stage2
stage_msg_r     equ   STAGE_ADDR+stage_msg-stage2

                assert stage2_end-stage2<=STAGE_LIMIT-STAGE_ADDR,"MSX selector stage exceeds reserved glue"
                save  "GBMSX.COM",#100,stage2_end-#100
