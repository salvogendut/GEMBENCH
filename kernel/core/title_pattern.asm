gbtitle_entry
                assert gbtitle_entry==DATA_TITLE_RUN,"GBTITLE CPC entry moved"
                TITLE_CLIP
                ld    a,(FBW_H)
                ld    (FB_ROWS),a
                ld    a,(FBW_Y)
                ld    (FB_CY),a
tb_row
                ld    a,(FB_CY)              ; relative tile row * four bytes
                ld    hl,FB_Y
                sub   (hl)
                and   15
                add   a,a
                add   a,a
                ld    c,a
                ld    a,(FBW_X)              ; relative byte-column phase
                ld    hl,FB_X
                sub   (hl)
                and   3
                add   a,c
                ld    (tb_off),a

                ld    a,(FBW_X)
                ld    d,a
                ld    a,(FB_CY)
                ld    e,a
                call  TITLE_SCREEN_ADDR

                ld    a,(tb_off)
                ld    e,a
                ld    d,0
                push  hl
                ld    hl,DATA_TITLE
                add   hl,de
                ex    de,hl                   ; DE = tile byte, HL restored as screen
                pop   hl
                ld    a,(FBW_W)
                ld    b,a
tb_col
                ld    a,(de)
                ld    (hl),a
                inc   hl
                inc   e
                ld    a,e
                and   3
                jr    nz,tb_no_wrap
                dec   e
                dec   e
                dec   e
                dec   e
tb_no_wrap
                djnz  tb_col
                ld    a,(FB_CY)
                inc   a
                ld    (FB_CY),a
                ld    a,(FB_ROWS)
                dec   a
                ld    (FB_ROWS),a
                jr    nz,tb_row
                ret
