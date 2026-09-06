; Shared native WM policy extracted from the production MSX2 kernel (#77).
; State, frozen record offsets and drawing/bank hooks are supplied by the provider.
gb_open_window
                ld    a,GB_WK_LEGACY         ; direct gb_window() keeps the inherited chrome
                ld    (mw_kind),a            ; contract; managed windows enter below after
gb_open_window_kind
                ld    a,b
                ld    (kw_x),a
                ld    a,c
                ld    (kw_y),a
                ld    a,d
                ld    (kw_w),a
                ld    a,e
                ld    (kw_h),a
                ld    de,kw_title            ; copy title out of the caller's page
                call  kw_copy_title
                if TITLEBAR_TILE
                call  to_data                 ; GBTITLE.MOD shares PAGE_DATA with font/icons
                call  kwin_frame             ; frame: fills to screen, no font
                else
                call  kwin_frame
                call  to_data                 ; title needs the font page
                endif
                ld    a,(mw_kind)
                bit   0,a                     ; GB_WK_TITLE
                jr    z,gow_done
                ld    b,1                     ; white on the structure-colour title backing
                ld    c,2
                call  set_text_pens
                ld    a,(kw_x)
                ld    hl,mw_kind
                bit   1,(hl)                  ; reserve the left close gadget only when selected
                jr    z,gow_title_left
                add   a,4
                jr    gow_title_x
gow_title_left  inc   a
gow_title_x
                ld    (tc_x),a
                ld    a,(kw_y)
                add   a,3
                ld    (tc_y),a
                ld    hl,kw_title
                call  draw_text
                if !THEMED_GADGETS
                ld    a,(mw_kind)
                bit   1,a                     ; GB_WK_CLOSE
                jr    z,gow_done
                ld    b,2                     ; close 'X' glyph: structure colour on white
                ld    c,1
                call  set_text_pens
                ld    a,(kw_x)
                inc   a
                ld    (tc_x),a
                ld    a,(kw_y)
                add   a,3
                ld    (tc_y),a
                ld    hl,gad_x_str
                call  draw_text
                endif
gow_done
                jp    from_data
                if !THEMED_GADGETS
gad_x_str       db    "X",0
                endif

; KWB_LIGHT/DARK are provider fill encodings, not cross-platform pen bytes.

; kwin_frame: paper interior, striped/tiled title bar, borders and gadgets.
kwin_frame
                xor   a                       ; interior (logical pen 0): (x, y, w, h)
                ld    (fb_val),a
                ld    a,(kw_x)
                ld    b,a
                ld    a,(kw_y)
                ld    c,a
                ld    a,(kw_w)
                ld    d,a
                ld    a,(kw_h)
                ld    e,a
                call  fill_xywh
                ld    a,(mw_kind)
                bit   0,a                     ; a titleless kind is a framed work surface
                jr    z,kf_border
                if TITLEBAR_TILE
                ; The tile renderer clips like fill_block and phases the
                ; 16x14 motif from this window's own top-left corner.
                ld    a,(kw_x)
                ld    (fb_x),a
                ld    a,(kw_y)
                ld    (fb_y),a
                ld    a,(kw_w)
                ld    (fb_w),a
                ld    a,14
                ld    (fb_h),a
                ld    a,(TITLE_READY)
                or    a
                jr    z,kf_tile_missing
                call  fill_title_pattern
                jr    kf_title_done
kf_tile_missing
                ld    a,KWB_LIGHT             ; missing sample module: safe plain title bar
                ld    (fb_val),a
                call  fill_block
kf_title_done
                else
                ld    a,KWB_LIGHT             ; title bar: light base (x, y, w, 14)
                ld    (fb_val),a
                ld    a,(kw_x)
                ld    b,a
                ld    a,(kw_y)
                ld    c,a
                ld    a,(kw_w)
                ld    d,a
                ld    e,14
                call  fill_xywh
                ld    a,KWB_DARK              ; ... dark horizontal stripes (1-line
                ld    (fb_val),a             ; fills, every other line; fb_x/fb_w
                ld    a,1                     ; stay kw_x/kw_w from the fill above)
                ld    (fb_h),a
                ld    a,(kw_y)
                ld    (kf_sy),a
                ld    b,7
kf_stripe       ld    a,(kf_sy)
                ld    (fb_y),a
                push  bc
                call  fill_block
                pop   bc
                ld    a,(kf_sy)
                add   a,2
                ld    (kf_sy),a
                djnz  kf_stripe
                endif
kf_border
                ld    hl,(kw_x)              ; configured borders via k_frame (all 4 edges; the
                ld    b,l                    ; top edge coincides with the first title
                ld    c,h                    ; stripe, so it is behavior-neutral) - was
                ld    hl,(kw_w)              ; three separate left/right/bottom fills
                ld    d,l
                ld    e,h
                ld    a,(KCFG_FRAMEPEN)      ; Edge, or a preselected contrasting UI pen
                call  k_frame
                jp    kf_kind_furniture

; Draw exactly the selected furniture. Legacy is title/close/maximise, no grip.
kf_kind_furniture
                ld    a,(mw_kind)
                bit   0,a                     ; close/maximise live in the title band
                jr    z,kfm_grip
                if THEMED_GADGETS
                xor   a
                ld    (bm_keep),a
                ld    a,(mw_kind)
                bit   1,a                     ; GB_WK_CLOSE
                jr    z,kfm_theme_max
                ld    hl,DATA_TITLE_CLOSE
                ld    (bm_src),hl
                ld    a,(kw_x)
                inc   a
                ld    (bm_x),a
                ld    a,(kw_y)
                add   a,2
                ld    (bm_y),a
                ld    a,2
                ld    (bm_w),a
                ld    a,10
                ld    (bm_h),a
                call  blit_bitmap
kfm_theme_max   ld    a,(mw_kind)
                bit   2,a                     ; GB_WK_MAXIMIZE
                jr    z,kfm_grip
                ld    hl,DATA_TITLE_MAX
                ld    (bm_src),hl
                ld    a,(kw_x)
                ld    hl,kw_w
                add   a,(hl)
                sub   4
                ld    (bm_x),a
                ld    a,(kw_y)
                add   a,2
                ld    (bm_y),a
                ld    a,3
                ld    (bm_w),a
                ld    a,10
                ld    (bm_h),a
                call  blit_bitmap
                else
                ld    a,(mw_kind)
                bit   1,a                     ; GB_WK_CLOSE
                jr    z,kfm_plain_max
                ld    a,KWB_LIGHT
                ld    (fb_val),a
                ld    a,(kw_x)
                inc   a
                ld    b,a
                ld    a,(kw_y)
                add   a,2
                ld    c,a
                ld    d,2
                ld    e,10
                call  fill_xywh
kfm_plain_max   ld    a,(mw_kind)
                bit   2,a                     ; GB_WK_MAXIMIZE
                jr    z,kfm_grip
                ld    a,KWB_LIGHT
                ld    (fb_val),a
                ld    a,(kw_x)
                ld    hl,kw_w
                add   a,(hl)
                sub   4
                ld    (kfm_gx),a
                ld    b,a
                ld    a,(kw_y)
                add   a,2
                ld    c,a
                ld    d,3
                ld    e,10
                call  fill_xywh
                ld    a,KWB_DARK
                ld    (fb_val),a
                ld    a,(kfm_gx)
                inc   a
                ld    b,a
                ld    a,(kw_y)
                add   a,5
                ld    c,a
                ld    d,1
                ld    e,4
                call  fill_xywh
                endif
kfm_grip        ld    a,(mw_kind)
                bit   4,a                     ; GB_WK_RESIZE
                ret   z
                ld    a,KWB_LIGHT
                ld    (fb_val),a
                ld    a,(kw_x)
                ld    hl,kw_w
                add   a,(hl)
                sub   2
                ld    b,a
                ld    a,(kw_y)
                ld    hl,kw_h
                add   a,(hl)
                sub   6
                ld    c,a
                ld    d,2
                ld    e,6
                call  fill_xywh
                ld    a,(kw_x)
                ld    hl,kw_w
                add   a,(hl)
                sub   2
                ld    b,a
                ld    a,(kw_y)
                ld    hl,kw_h
                add   a,(hl)
                sub   6
                ld    c,a
                ld    d,2
                ld    e,6
                ld    a,2
                jp    k_frame
                CHROME_GADGET_STORAGE

; The native title allocation on MSX is 24 bytes, not the generic text service's
; 49. Bound the shared title copy before the font page overlays caller memory.
kw_copy_title
                ld b,23
                jp CHROME_STRING_COPY_LOOP
