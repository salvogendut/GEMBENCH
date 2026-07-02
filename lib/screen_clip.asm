; ---------------------------------------------------------------------------
; lib/screen_clip.asm - clip-rect intersection + culling (pure integer math).
;
; Shared verbatim by BOTH screen drivers (lib/screen.asm for the CPC, and
; lib/msx/screen.asm for the MSX2 V9938 target, #287): no hardware access, only
; the fb_*/fbw_*/clip_* low-RAM cells. Extracted from lib/screen.asm so the
; MSX driver doesn't duplicate it; included at the exact same position in the
; CPC driver, so the CPC image is byte-identical.
; ---------------------------------------------------------------------------
; clip_fb_copy: fbw_* = intersection of fb_* (x,y,w,h) with the clip rect. CF set
; if the intersection is empty. Leaves fb_* untouched. Clobbers A,B,C,D,E,H,L.
clip_fb_copy
                ld    a,(fb_x)               ; X: seg [fb_x, fb_x+fb_w)
                ld    h,a
                ld    a,(fb_w)
                add   a,h
                ld    l,a                      ; L = fb_x + fb_w
                ld    a,(clip_x)
                ld    d,a
                ld    a,(clip_w)
                add   a,d
                ld    e,a                      ; E = clip_x + clip_w
                ld    a,h                      ; left = max(fb_x, clip_x)
                cp    d
                jr    nc,cfc_xl
                ld    a,d
cfc_xl          ld    c,a                      ; C = left
                ld    a,l                      ; right = min(fb_end, clip_end)
                cp    e
                jr    c,cfc_xr
                ld    a,e
cfc_xr          ld    b,a                      ; B = right
                ld    a,c
                cp    b
                jr    nc,cfc_empty            ; left >= right -> empty
                ld    (fbw_x),a
                ld    a,b
                sub   c
                ld    (fbw_w),a
                ld    a,(fb_y)               ; Y: seg [fb_y, fb_y+fb_h)
                ld    h,a
                ld    a,(fb_h)
                add   a,h
                ld    l,a
                ld    a,(clip_y)
                ld    d,a
                ld    a,(clip_h)
                add   a,d
                ld    e,a
                ld    a,h
                cp    d
                jr    nc,cfc_yl
                ld    a,d
cfc_yl          ld    c,a
                ld    a,l
                cp    e
                jr    c,cfc_yr
                ld    a,e
cfc_yr          ld    b,a
                ld    a,c
                cp    b
                jr    nc,cfc_empty
                ld    (fbw_y),a
                ld    a,b
                sub   c
                ld    (fbw_h),a
                or    a                         ; clear CF
                ret
cfc_empty       scf
                ret

; rect_cull: B=x C=y D=w E=h (byte cols / lines) -> CF set if the rectangle is
; fully outside the clip rect (so the caller skips drawing). Used to cull whole
; icons/glyphs so a lower layer never paints over a higher window during a partial
; repaint. Clobbers A,H,L.
rect_cull
                ld    a,b                       ; X: right = x + w
                add   a,d
                ld    l,a
                ld    a,(clip_x)
                cp    l
                jr    nc,rc_out                 ; clip_x >= right -> left of clip
                ld    a,(clip_x)               ; clip_right = clip_x + clip_w
                ld    h,a
                ld    a,(clip_w)
                add   a,h
                cp    b
                jr    c,rc_out                  ; clip_right < x -> right of clip
                jr    z,rc_out                  ; clip_right == x -> right of clip
                ld    a,c                       ; Y: bottom = y + h
                add   a,e
                ld    l,a
                ld    a,(clip_y)
                cp    l
                jr    nc,rc_out                 ; above clip
                ld    a,(clip_y)               ; clip_bottom = clip_y + clip_h
                ld    h,a
                ld    a,(clip_h)
                add   a,h
                cp    c
                jr    c,rc_out                  ; below clip
                jr    z,rc_out
                or    a                          ; clear CF -> visible
                ret
rc_out          scf
                ret
