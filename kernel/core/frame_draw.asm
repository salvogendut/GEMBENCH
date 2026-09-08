; Shared native WM policy extracted from the production MSX2 kernel (#77).
; State, frozen record offsets and drawing/bank hooks are supplied by the provider.
k_frame
                ld    (gf_pen),a             ; save params FIRST: pen_to_byte below
                ld    a,b                     ; clobbers E (height), so capture it now
                ld    (gf_x),a
                ld    a,c
                ld    (gf_y),a
                ld    a,d
                ld    (gf_w),a
                ld    a,e
                ld    (gf_h),a
                ld    a,(gf_pen)
                call  pen_to_byte            ; pen -> Mode 1 fill byte
                ld    (fb_val),a
                ld    a,(gf_x)               ; top edge: (x, y, w, 1)
                ld    b,a
                ld    a,(gf_y)
                ld    c,a
                ld    a,(gf_w)
                ld    d,a
                ld    e,1
                call  fill_xywh
                ld    a,(gf_x)               ; bottom edge: (x, y+h-1, w, 1)
                ld    b,a
                ld    a,(gf_y)
                ld    c,a
                ld    a,(gf_h)
                add   a,c
                dec   a
                ld    c,a
                ld    a,(gf_w)
                ld    d,a
                ld    e,1
                call  fill_xywh
                ld    a,(gf_x)               ; left edge: (x, y, 1, h)
                ld    b,a
                ld    a,(gf_y)
                ld    c,a
                ld    d,1
                ld    a,(gf_h)
                ld    e,a
                call  fill_xywh
                ld    a,(gf_x)               ; right edge: (x+w-1, y, 1, h)
                ld    b,a
                ld    a,(gf_w)
                add   a,b
                dec   a
                ld    b,a
                ld    a,(gf_y)
                ld    c,a
                ld    d,1
                ld    a,(gf_h)
                ld    e,a
                jp    fill_xywh
