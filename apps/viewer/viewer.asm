; viewer - the first GEOBENCH target app, launched by the file manager when a
; file is double-clicked. Runs co-resident in its own bank page (PAGE_APP1),
; reads the opened file's name via GB_GETARG, and shows it in a window. A click
; or ESC closes it, returning to the file manager.
;
; (For now it just displays the name - proving the launch + filename handoff.
; Reading and showing the file's contents is the next step.)

                include "../../lib/gbapp.inc"

                org   APP_BASE
vw_entry
                ld    b,8                     ; window at (8,46), 48x70
                ld    c,46
                ld    d,48
                ld    e,70
                ld    hl,vw_title
                call  GB_WINDOW

                call  GB_GETARG             ; HL = 8.3 name of the opened file
                call  vw_format             ; -> vw_name "NAME.EXT", 0-term
                ld    b,11                    ; "Opened file:"
                ld    c,64
                ld    d,1
                ld    e,0
                ld    hl,vw_lbl
                call  GB_TEXT
                ld    b,11                    ; the file name
                ld    c,74
                ld    d,1
                ld    e,0
                ld    hl,vw_name
                call  GB_TEXT

                call  GB_CURSHOW
vw_loop
                call  GB_POLL                ; D: bit0 click, bit1 quit
                bit   1,d
                jr    nz,vw_done
                bit   0,d
                jr    nz,vw_done
                jr    vw_loop
vw_done
                ret                            ; back to the file manager

; vw_format: HL = 8.3 name (11 bytes, space padded) -> vw_name "NAME.EXT", 0.
vw_format
                push  hl
                ld    de,vw_name
                ld    b,8
vf_name
                ld    a,(hl)
                cp    ' '
                jr    z,vf_ext
                ld    (de),a
                inc   de
                inc   hl
                djnz  vf_name
vf_ext
                pop   hl                       ; base + 8 = extension
                ld    bc,8
                add   hl,bc
                ld    a,(hl)
                cp    ' '
                jr    z,vf_end
                ld    a,'.'
                ld    (de),a
                inc   de
                ld    b,3
vf_xloop
                ld    a,(hl)
                cp    ' '
                jr    z,vf_end
                ld    (de),a
                inc   de
                inc   hl
                djnz  vf_xloop
vf_end
                xor   a
                ld    (de),a
                ret

vw_title        db    "VIEWER",0
vw_lbl          db    "Opened file:",0
vw_name         defs  14
vw_end
                save  "build/VIEWER.RAW",APP_BASE,vw_end-APP_BASE
