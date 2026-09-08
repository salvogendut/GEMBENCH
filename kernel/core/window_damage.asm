; Shared existing window damage/repaint policy (#72).
; Provider obligations: window_damage_contract.inc.
; k_wm_damage (GB_WMDAMAGE): set the repaint clip to a caller-supplied damage rect,
; so the next gb_restore_parent only repaints that region instead of the whole
; screen (#153 - kills the full-desktop flash after a dropdown menu). gb_popup
; passes its box UNION the focused window's rect, so the repaint covers both the
; dropdown's footprint (the part that overhangs other windows) and the window the
; menu action changed. Registers are pre-swapped by the trampoline for two word
; stores: C=x B=y (-> CORE_CLIP_X,CORE_CLIP_Y) and E=w D=h (-> CORE_CLIP_W,CORE_CLIP_H).
k_wm_damage
                ld    (CORE_CLIP_X),bc              ; CORE_CLIP_X = x, CORE_CLIP_Y = y
                ld    (CORE_CLIP_W),de              ; CORE_CLIP_W = w, CORE_CLIP_H = h
                if CORE_REPAINT_REGIONS
                xor   a                             ; explicit damage replaces any
                ld    (CORE_DAMAGE_EXTRA_PENDING),a ; unconsumed move union
                endif
                ret

; clip_set_full: reset the fill clip to the whole screen (no clipping). Two word
; stores (clobbers BC/DE, preserves A and flags).
clip_set_full
                ld    bc,0                          ; CORE_CLIP_X = 0, CORE_CLIP_Y = 0
                ld    (CORE_CLIP_X),bc
                ld    de,(CORE_SCREEN_LINES*256)|CORE_SCREEN_COLS ; CORE_CLIP_W / CORE_CLIP_H = the full screen
                ld    (CORE_CLIP_W),de
                ret

; wm_set_clip: A = slot -> window clip with the provider's right overdraw pad.
; Returns B = native code tag and HL = rect+3 (height); close reuses both.
wm_set_clip
                PAINT_CLOSE_RECT
                ld    a,(hl)
                ld    (CORE_CLIP_X),a
                inc   hl                            ; rect+1 y
                ld    a,(hl)
                ld    (CORE_CLIP_Y),a
                inc   hl                            ; rect+2 width
                ld    a,(hl)                        ; allow the existing whole-atom overdraw
                add   a,CORE_WINDOW_DAMAGE_PAD
                ld    (CORE_CLIP_W),a
                inc   hl                            ; rect+3 height
                ld    a,(hl)
                ld    (CORE_CLIP_H),a
                ret
