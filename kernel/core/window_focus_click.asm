; Shared working focus/stack policy (#70); see window_focus_contract.inc.
; wm_focus_click: if a fresh click landed on a window other than the focused one,
; move focus there. App windows also rise to the z-top. The visible-region
; compositor repaints the exact union of the old and new focus rectangles, so
; both windows immediately redraw their active/inactive furniture without
; touching unrelated desktop areas. A click that activates another window in
; the same application is consumed: the new pane receives frames immediately, but
; editing starts with the next press instead of reusing the activation press.
; The desktop (slot 0) stays pinned at the bottom.
wm_focus_click
                ld    a,(CORE_INPUT_FLAGS)
                bit   0,a
                ret   z                            ; no fresh click
                call  wm_hit_test                  ; CF set = no window hit (e.g. top bar)
                ret   c
                ld    (CORE_FOCUS_TARGET),a                  ; clicked slot survives native-cell lookup
                ld    b,a
                ld    a,(CORE_FOCUS_SLOT)
                cp    b
                ret   z                            ; already focused -> deliver
                FOCUS_NATIVE_CELL
                ld    a,(hl)                       ; (same application/code page)
                ld    (CORE_FOCUS_OLD),a
                ld    a,(CORE_FOCUS_TARGET)
                FOCUS_NATIVE_CELL
                ld    a,(CORE_FOCUS_OLD)
                cp    (hl)
                jr    nz,wfc_activate
                ld    a,(CORE_INPUT_FLAGS)
                res   0,a
                ld    (CORE_INPUT_FLAGS),a
wfc_activate
                if CORE_FOCUS_VISIBLE_DAMAGE
                ld    a,(CORE_FOCUS_SLOT)                ; sibling comparison no longer needs its page
                ld    (CORE_FOCUS_OLD),a             ; retain the old focus slot for exact damage
                endif
                ld    a,(CORE_FOCUS_TARGET)
                ld    (CORE_FOCUS_SLOT),a               ; focus the clicked window
                if CORE_FOCUS_VISIBLE_DAMAGE
                call  FOCUS_BUILD_DAMAGE             ; exact old/new focus-window union
                ld    a,(CORE_FOCUS_TARGET)
                or    a
                jr    z,wfc_repaint_focus         ; desktop remains pinned at the bottom
                ld    c,a                          ; c = clicked app slot
                ld    a,(CORE_LIVE_WINDOWS)                 ; already the z-top? repaint focus state anyway
                dec   a
                ld    hl,CORE_Z_ORDER
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    c
                jr    z,wfc_repaint_focus
                ld    a,c
                call  wm_raise                     ; bring it to the front
wfc_repaint_focus
                jp    FOCUS_REPAINT               ; compositor clips every layer to the exact union
                else
                or    a
                ret   z                            ; desktop: keep it at the bottom
                ld    c,a                          ; c = clicked app slot
                ld    a,(CORE_LIVE_WINDOWS)               ; already the z-top? then nothing to raise
                dec   a
                ld    hl,CORE_Z_ORDER
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    c
                ret   z
                ld    a,c
                call  wm_raise
                ld    a,c                          ; legacy targets repaint the raised window
                call  FOCUS_SET_CLIP
                jp    FOCUS_REPAINT_TOP               ; opaque top window: avoid repainting layers through it
                endif                              ; CORE_FOCUS_VISIBLE_DAMAGE
