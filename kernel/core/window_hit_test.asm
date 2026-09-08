; Shared working focus/stack policy (#70); see window_focus_contract.inc.
; wm_hit_test: -> A = slot of the top-most window whose rect contains the pointer
; (CORE_POINTER_X, CORE_POINTER_Y), scanning z-order top->bottom; CF set if none.
wm_hit_test
                ld    a,(CORE_LIVE_WINDOWS)
                ld    (CORE_HIT_CURSOR),a
wht_l           ld    a,(CORE_HIT_CURSOR)
                or    a
                jr    z,wht_none
                dec   a
                ld    (CORE_HIT_CURSOR),a
                ld    hl,CORE_Z_ORDER
                add   a,l
                ld    l,a
                ld    a,(hl)                       ; slot = CORE_Z_ORDER[i]
                FOCUS_RECT
                ld    a,(CORE_POINTER_X)
                sub   (hl)
                jr    c,wht_l                       ; mx < x
                ld    c,a                            ; mx - x
                inc   hl                            ; +2 y
                inc   hl                            ; +3 w
                ld    a,c
                cp    (hl)
                jr    nc,wht_l                      ; mx-x >= w
                dec   hl                            ; +2 y
                ld    a,(CORE_POINTER_Y)
                sub   (hl)
                jr    c,wht_l                       ; my < y
                ld    c,a                            ; my - y
                inc   hl                            ; +3 w
                inc   hl                            ; +4 h
                ld    a,c
                cp    (hl)
                jr    nc,wht_l                      ; my-y >= h
                ld    a,(CORE_HIT_CURSOR)                     ; hit -> recover slot
                ld    hl,CORE_Z_ORDER
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a                             ; clear CF
                ret
wht_none        scf
                ret
