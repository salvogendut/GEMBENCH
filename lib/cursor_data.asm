; cursor sprite bitmaps (2 pre-shifted phases), relocated out of the resident
; kernel (#65). Assembled ABOVE kern_end (not part of GBKERN.BIN) and saved as
; DEFAULT.SPR; the kernel loads it into low RAM at CUR_LOW at boot (cursor_init).
; Layout = d0,m0,d2,m2, each cursor_arrow_w*cursor_arrow_h (64) bytes, so at
; CUR_LOW they sit at +0 (d0), +#40 (m0), +#80 (d2), +#C0 (m2) - matching the
; pointer tables in cursor_arrow.asm.
cur_spr_data
                db    #40,#00,#00,#00      ; d0 (shift 0)
                db    #60,#00,#00,#00
                db    #72,#00,#00,#00
                db    #73,#80,#00,#00
                db    #73,#C8,#00,#00
                db    #73,#FC,#00,#00
                db    #73,#FF,#80,#00
                db    #73,#FF,#C8,#00
                db    #73,#FF,#EC,#00
                db    #73,#FE,#E0,#00
                db    #73,#F2,#80,#00
                db    #72,#F3,#80,#00
                db    #60,#71,#C8,#00
                db    #00,#31,#C8,#00
                db    #00,#31,#C8,#00
                db    #00,#10,#80,#00
                db    #BB,#FF,#FF,#FF      ; m0 (mask, shift 0)
                db    #99,#FF,#FF,#FF
                db    #88,#FF,#FF,#FF
                db    #88,#77,#FF,#FF
                db    #88,#33,#FF,#FF
                db    #88,#00,#FF,#FF
                db    #88,#00,#77,#FF
                db    #88,#00,#33,#FF
                db    #88,#00,#11,#FF
                db    #88,#00,#11,#FF
                db    #88,#00,#77,#FF
                db    #88,#00,#77,#FF
                db    #99,#88,#33,#FF
                db    #FF,#CC,#33,#FF
                db    #FF,#CC,#33,#FF
                db    #FF,#EE,#77,#FF
                db    #10,#00,#00,#00      ; d2 (shift 2)
                db    #10,#80,#00,#00
                db    #10,#C8,#00,#00
                db    #10,#EC,#00,#00
                db    #10,#FE,#00,#00
                db    #10,#FF,#C0,#00
                db    #10,#FF,#EC,#00
                db    #10,#FF,#FE,#00
                db    #10,#FF,#FF,#80
                db    #10,#FF,#F8,#80
                db    #10,#FC,#E8,#00
                db    #10,#F8,#EC,#00
                db    #10,#90,#F6,#00
                db    #00,#00,#F6,#00
                db    #00,#00,#F6,#00
                db    #00,#00,#60,#00
                db    #EE,#FF,#FF,#FF      ; m2 (mask, shift 2)
                db    #EE,#77,#FF,#FF
                db    #EE,#33,#FF,#FF
                db    #EE,#11,#FF,#FF
                db    #EE,#00,#FF,#FF
                db    #EE,#00,#33,#FF
                db    #EE,#00,#11,#FF
                db    #EE,#00,#00,#FF
                db    #EE,#00,#00,#77
                db    #EE,#00,#00,#77
                db    #EE,#00,#11,#FF
                db    #EE,#00,#11,#FF
                db    #EE,#66,#00,#FF
                db    #FF,#FF,#00,#FF
                db    #FF,#FF,#00,#FF
                db    #FF,#FF,#99,#FF
cur_spr_end
