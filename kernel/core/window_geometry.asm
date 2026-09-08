; Shared existing window damage/repaint policy (#72).
; Provider obligations: window_damage_contract.inc.
; k_wm_setpos (GB_WMSETPOS): A = x, L = y -> move the focused window's hit rect to
; (x,y), so click-to-focus follows a window the app has dragged. The endpoint
; envelope covers the destructive rubber-band path between the original and final
; positions before the following gb_restore_parent reconstructs the stack.
k_wm_setpos
                ld    (CORE_MOVE_X),a               ; new x
                ld    a,l
                ld    (CORE_MOVE_Y),a               ; new y
                ld    a,(CORE_FOCUS_SLOT)
                PAINT_WINDOW_RECT
                ld    b,(hl)
                inc   hl
                inc   hl                            ; rect+2 width
                ld    c,(hl)
                ld    a,(CORE_MOVE_X)
                call  damage_axis                   ; D = min(ox,nx), E = span
                ld    a,d
                ld    (CORE_CLIP_X),a
                ld    a,e
                ld    (CORE_CLIP_W),a
                dec   hl                            ; rect+1 old y
                ld    b,(hl)
                inc   hl
                inc   hl                            ; rect+3 height
                ld    c,(hl)
                ld    a,(CORE_MOVE_Y)
                call  damage_axis
                ld    a,d
                ld    (CORE_CLIP_Y),a
                ld    a,e
                ld    (CORE_CLIP_H),a
                dec   hl                            ; rect+3 -> rect+0 (x)
                dec   hl
                dec   hl
                ld    a,(CORE_MOVE_X)               ; commit the new position
                ld    (hl),a
                inc   hl
                ld    a,(CORE_MOVE_Y)
                ld    (hl),a
                ret

; k_wm_setsize (GB_WMSETSIZE, #81): A = new w, L = new h. Resize the focused window's
; rect (top-left stays put). Damage clip = its (x,y) covering max(old,new) size, so the
; following gb_restore_parent repaints any area a shrink vacated.
k_wm_setsize
                ld    (CORE_SIZE_W),a
                ld    a,l
                ld    (CORE_SIZE_H),a
                ld    a,(CORE_FOCUS_SLOT)
                PAINT_WINDOW_RECT
                ld    a,(hl)
                ld    (CORE_CLIP_X),a               ; clip x = window x (unchanged)
                inc   hl                            ; rect+1 y
                ld    a,(hl)
                ld    (CORE_CLIP_Y),a
                inc   hl                            ; rect+2 width
                ld    b,(hl)                        ; old w
                ld    a,(CORE_SIZE_W)               ; clip w = max(old, new)
                cp    b
                jr    nc,kss_w
                ld    a,b
kss_w
                ld    (CORE_CLIP_W),a
                ld    a,(CORE_SIZE_W)
                ld    (hl),a                        ; commit new w
                inc   hl                            ; rect+3 height
                ld    b,(hl)                        ; old h
                ld    a,(CORE_SIZE_H)
                cp    b
                jr    nc,kss_h
                ld    a,b
kss_h
                ld    (CORE_CLIP_H),a
                ld    a,(CORE_SIZE_H)
                ld    (hl),a                        ; commit new h
                ret

; damage_axis: B = old, A = new, C = size -> D = min(old,new), E = span =
; max(old,new) + size - min. The 1-D damage extent of a move. Preserves HL.
damage_axis
                cp    b
                jr    nc,dax_oldmin                 ; new >= old -> min = old, max = new
                ld    d,a                           ; min = new
                ld    a,b                           ; max = old
                jr    dax_span
dax_oldmin      ld    d,b                           ; min = old (A = new = max)
dax_span        add   a,c                           ; max + size
                sub   d                             ; - min
                ld    e,a
                ret
