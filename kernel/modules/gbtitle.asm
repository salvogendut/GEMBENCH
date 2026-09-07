; ---------------------------------------------------------------------------
; GBTITLE.PAY - issue #458 runtime title-bar tile and CPC renderer payload.
;
; PAGE_DATA reserves #5E00..#5FFF below the normal #6000 module slot. The first
; The first 106 bytes are the composed fallback theme: a 56-byte repeated
; background followed by the 50-byte close/maximize pair. TITLEBAR=<name>
; replaces the background and GADGETS=<name> replaces the gadget pair. Legacy
; 106-byte TBR files still replace both. CPC calls the renderer immediately
; after the theme; MSX/PCW use their resident screen renderers.
; ---------------------------------------------------------------------------

DATA_TITLE      equ   #5E00
DATA_TITLE_SIZE equ   106
DATA_TITLE_RUN  equ   DATA_TITLE+DATA_TITLE_SIZE

CLIP_X          equ   #1338
CLIP_Y          equ   #1339
CLIP_W          equ   #133A
CLIP_H          equ   #133B
FB_ROWS         equ   #14AE
FB_CY           equ   #14AF
FBW_X           equ   #14B0
FBW_Y           equ   #14B1
FBW_W           equ   #14B2
FBW_H           equ   #14B3
FB_X            equ   #14B8
FB_Y            equ   #14B9
FB_W            equ   #14BA
FB_H            equ   #14BB

                org   DATA_TITLE
gbtitle_tile    incbin "../../build/TITLEBAR.TBR"
                assert $-gbtitle_tile==DATA_TITLE_SIZE,"GBTITLE theme must be 106 bytes"

TITLE_SCREEN_ADDR equ tb_scr_addr
                macro TITLE_CLIP
                call tb_clip
                ret c
                mend
                include "../core/title_pattern.asm"

; D = byte column, E = line -> HL = CPC Mode-1 screen address.
tb_scr_addr
                ld    a,e
                and   7
                add   a,a
                add   a,a
                add   a,a
                or    #C0
                ld    h,a
                ld    l,0
                push  hl
                ld    a,e
                srl   a
                srl   a
                srl   a
                ld    l,a
                ld    h,0
                add   hl,hl                   ; character row * 16
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    b,h
                ld    c,l
                add   hl,hl                   ; * 32
                add   hl,hl                   ; * 64
                add   hl,bc                   ; * 80
                pop   bc                      ; interleaved scanline base
                add   hl,bc
                ld    b,0
                ld    c,d
                add   hl,bc
                ret

; FBW_* = intersection of FB_* and the active WM damage clip. CF = empty.
tb_clip
                ld    a,(FB_X)
                ld    h,a
                ld    a,(FB_W)
                add   a,h
                ld    l,a
                ld    a,(CLIP_X)
                ld    d,a
                ld    a,(CLIP_W)
                add   a,d
                ld    e,a
                ld    a,h
                cp    d
                jr    nc,tbc_x_left
                ld    a,d
tbc_x_left     ld    c,a
                ld    a,l
                cp    e
                jr    c,tbc_x_right
                ld    a,e
tbc_x_right    ld    b,a
                ld    a,c
                cp    b
                jr    nc,tbc_empty
                ld    (FBW_X),a
                ld    a,b
                sub   c
                ld    (FBW_W),a

                ld    a,(FB_Y)
                ld    h,a
                ld    a,(FB_H)
                add   a,h
                ld    l,a
                ld    a,(CLIP_Y)
                ld    d,a
                ld    a,(CLIP_H)
                add   a,d
                ld    e,a
                ld    a,h
                cp    d
                jr    nc,tbc_y_top
                ld    a,d
tbc_y_top      ld    c,a
                ld    a,l
                cp    e
                jr    c,tbc_y_bottom
                ld    a,e
tbc_y_bottom   ld    b,a
                ld    a,c
                cp    b
                jr    nc,tbc_empty
                ld    (FBW_Y),a
                ld    a,b
                sub   c
                ld    (FBW_H),a
                or    a
                ret
tbc_empty      scf
                ret

tb_off         db    0
gbtitle_end

                assert gbtitle_end-DATA_TITLE<=384,"GBTITLE payload exceeds reserved PAGE_DATA slot"
                save  "build/GBTITLE.PAY",DATA_TITLE,gbtitle_end-DATA_TITLE
