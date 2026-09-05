; Shared existing window damage/repaint policy (#72).
; Provider obligations: window_damage_contract.inc.
                if CORE_REPAINT_REGIONS
; wm_focus_damage: make the new focus rectangle the primary source and the old
; focus rectangle the second source. The compositor subtracts their overlap and
; clips both against the post-focus z-order, yielding an exact visible union.
; CORE_FOCUS_OLD contains the old focus slot and CORE_FOCUS_TARGET the new one. Desktop has
; no focus furniture, so it is omitted when it is either endpoint.
wm_focus_damage
                xor   a
                ld    (CORE_DAMAGE_EXTRA_PENDING),a
                ld    a,(CORE_FOCUS_TARGET)
                or    a
                jr    nz,wfd_primary
                ld    a,(CORE_FOCUS_OLD)            ; app -> desktop: old app is primary
wfd_primary
                PAINT_WINDOW_RECT
                ld    de,CORE_CLIP_X
                ld    bc,4
                ldir
                ld    a,(CORE_FOCUS_TARGET)
                or    a
                ret   z                             ; app -> desktop: desktop has no furniture
                ld    a,(CORE_FOCUS_OLD)
                or    a
                ret   z                             ; desktop -> app: only the app changes appearance
                PAINT_WINDOW_RECT
                ld    de,CORE_DAMAGE_EXTRA
                ld    bc,4
                ldir
                ld    a,1
                ld    (CORE_DAMAGE_EXTRA_PENDING),a
                ret
                endif                               ; CORE_REPAINT_REGIONS focus damage
