icon_geom
                ld    l,a                     ; dir entry = DATA_ICONS+16 + slot*4
                ld    h,0
                add   hl,hl
                add   hl,hl
                ld    de,DATA_ICONS+16
                add   hl,de
                ld    e,(hl)                  ; offset (word)
                inc   hl
                ld    d,(hl)
                inc   hl
                ld    a,(hl)                  ; width (bytes)
                ld    (ig_w),a
                inc   hl
                ld    a,(hl)                  ; height (rows)
                ld    (ig_h),a
                ld    hl,DATA_ICONS          ; bitmap base = DATA_ICONS + offset
                add   hl,de
                ld    a,(ig_h)               ; + (h/4)*w  (skip the top quarter)
                srl   a
                srl   a
                ld    b,a
                ld    a,(ig_w)
                ld    e,a
                ld    d,0
ig_skip
                ld    a,b
                or    a
                jr    z,ig_done
                add   hl,de
                dec   b
                jr    ig_skip
ig_done
                ld    (bm_src),hl
                ld    a,(ig_w)
                ld    (bm_w),a
                ld    a,(ig_h)               ; half height
                srl   a
                ld    (bm_h),a
                ld    a,(be_x)
                ld    (bm_x),a
                ld    a,(be_y)
                ld    (bm_y),a
                ret
