icon_full_geom                                 ; A = slot -> bm_src/w/h, bm_x/y
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl                     ; slot*4
                ld    de,DATA_ICONS+16
                add   hl,de
                ld    e,(hl)                  ; offset
                inc   hl
                ld    d,(hl)
                inc   hl
                ld    a,(hl)                  ; width
                ld    (bm_w),a
                inc   hl
                ld    a,(hl)                  ; height (full)
                ld    (bm_h),a
                ld    hl,DATA_ICONS
                add   hl,de
                ld    (bm_src),hl
                ld    a,(gi_x)
                ld    (bm_x),a
                ld    a,(gi_y)
                ld    (bm_y),a
                ret
