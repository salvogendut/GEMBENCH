; Shared existing window damage/repaint policy (#72).
; Provider obligations: window_damage_contract.inc.
; Repaint bottom-up through the provider's visible-region iterator (normal
; path), or its coarse rectangle culler (cooperative compatibility path).
; Restore the caller's bank and full clip, then unlock/show the pointer once.
; State/ordering and callback restrictions: window_damage_contract.inc.
wm_repaint_all
                xor   a
                jr    wra_seed
; wm_repaint_top: repaint only the current z-top. Used after click-to-focus raises an
; opaque managed window and through GB_REPAINTTOP for a newly published managed
; window; redrawing lower layers first makes the stack visibly flash.
wm_repaint_top
                ld    a,(CORE_LIVE_WINDOWS)
                dec   a
wra_seed        ld    (CORE_REPAINT_INDEX),a
                ld    a,(CORE_MAPPED_NATIVE)
                ld    (CORE_REPAINT_BANK),a
                if CORE_REPAINT_REGIONS
                call  PAINT_PREPARE                 ; capture sources, then refresh visibility
                endif
                if CORE_REPAINT_ERASE_POINTER
                ld    a,(CORE_POINTER_SUPPRESSED)   ; #148: hide the pointer before the repaint so it
                or    a                             ; can't pollute its save-under (else a later move
                call  z,PAINT_POINTER_ERASE         ; restores stale content = a pointer-sized hole).
                endif
                ld    a,1                           ; lock the cursor for the whole loop: app on_draw
                ld    (CORE_POINTER_PAINTLOCK),a    ; handlers also bracket with gb_curhide/show, and
                                                  ; that 2nd erase restores a stale save-under over
                                                  ; chrome a window drew earlier this pass (the XAOS
                                                  ; title hole, on File>New AND drag). Bracket ONCE.
                PAINT_IRQ_ENTER
wra_l           ld    a,(CORE_REPAINT_INDEX)
                ld    hl,CORE_LIVE_WINDOWS
                cp    (hl)
                jr    nc,wra_done
                ld    hl,CORE_Z_ORDER
                add   a,l
                ld    l,a
                ld    a,(hl)                        ; slot = CORE_Z_ORDER[i]
                if CORE_REPAINT_REGIONS
                call  PAINT_REGION_BEGIN            ; installs first exact visible damage fragment
                or    a
                jr    z,wra_next                    ; fully occluded: no callback and no drawing work
wra_fragment    ld    a,(CORE_REGION_SLOT)
                endif
                PAINT_WINDOW_TOKEN
                PAINT_WINDOW_FLAGS
                bit   CORE_PAINT_ALIVE_BIT,a        ; alive?
                jr    z,wra_next                    ; dead -> skip (z-order should exclude it)
                if !CORE_REPAINT_REGIONS
                push  af                            ; skip callbacks whose window cannot touch the
                push  hl                            ; current damage rectangle. Besides saving work,
                PAINT_RECT_ARGUMENTS
                call  PAINT_RECT_CULL
                pop   hl
                jr    c,wra_culled
                pop   af
                endif
                push  af                            ; keep flags across PAINT_SET_BANK
                PAINT_WINDOW_NATIVE
                call  PAINT_SET_BANK                ; (preserves HL = entry)
                pop   af                            ; #146: managed -> kernel draws chrome
                bit   CORE_PAINT_MANAGED_BIT,a      ; managed?
                jr    z,wra_legacy
                call  PAINT_CHROME_DRAW
                jr    wra_painted
wra_legacy
                PAINT_REPAINT_POINTER
                ld    a,h
                or    l
                jr    z,wra_painted                 ; no handler
                call  PAINT_CALL
                jr    wra_painted
                if !CORE_REPAINT_REGIONS
wra_culled      pop   af
                endif
wra_painted
                if CORE_REPAINT_REGIONS
                call  PAINT_REGION_NEXT
                or    a
                jr    nz,wra_fragment               ; same surface, next disjoint visible band
                endif
wra_next        ld    a,(CORE_REPAINT_INDEX)
                inc   a
                ld    (CORE_REPAINT_INDEX),a
                jr    wra_l
wra_done        ld    a,(CORE_REPAINT_BANK)
                call  PAINT_SET_BANK
                call  clip_set_full                 ; full-screen clip for normal drawing
                PAINT_IRQ_LEAVE
                xor   a                             ; unlock: loop done, now show the pointer ONCE
                ld    (CORE_POINTER_PAINTLOCK),a    ; over the final composited screen (fresh save-under)
                ld    a,(CORE_POINTER_SUPPRESSED)   ; #148: ensure the pointer is up with a FRESH
                or    a                             ; save-under over the just-repainted content.
                call  z,PAINT_POINTER_SHOW          ; GUARDED (#153): a handler that ends in gb_curshow
                ret                                 ; (e.g. the desktop paint) already drew it - don't
                                                  ; redraw, or we'd save cur_bg OVER the cursor's own
                                                  ; pixels and stamp a ghost on the next move.
