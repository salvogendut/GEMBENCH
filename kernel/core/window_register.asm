; Shared native WM policy extracted from the production MSX2 kernel (#77).
; State, frozen record offsets and drawing/bank hooks are supplied by the provider.
wm_register
                ld    (wm_desc),hl
                call  wm_free_slot               ; A = first dead slot
                cp    #FF
                ret   z                          ; compositor full: publish nothing
                ld    (wm_slot),a
                call  window_generation_next
                ld    a,(wm_slot)
                call  wm_entry                    ; HL = WM_TABLE[slot]
                ld    a,(bank_cur)               ; +0 page = caller
                ld    (hl),a
                inc   hl
                ex    de,hl                       ; DE = entry+1
                ld    hl,(wm_desc)
                ld    bc,12                       ; x,y,w,h,on_frame,on_repaint,on_event,menu
                ldir
                ld    a,1                          ; entry+13 flags = alive
                ld    (de),a
                inc   de                            ; entry+14 = arg: capture the pending
                ld    hl,launch_arg               ; launch arg as this window's own file
                call  copy11
                call  owner_bind_pending_window   ; parallel owner identity; WM entry stays frozen
                ld    a,(wm_slot)                 ; focus + append the new window (z-top)
                ld    (WM_FOCUS),a
                call  wm_z_append
                scf
                ret

; ===== managed windows (#146): the kernel owns the chrome ====================
; k_wm_managed (GB_WMMANAGED): HL = a gb_mwin_t descriptor in the caller's page;
; A = 0 for the legacy 12-byte contract or GB_WK_ABI_V1 for the explicit MSX2
; kind extension. Distinct libgb entry points supply the selector, so the kernel
; never probes beyond a legacy descriptor.
; Register a window the WM draws + drives: the descriptor pointer goes in WM_FR_FRAME
; and FLAGS gets MW_MANAGED, so wm_loop / wm_repaint_all route it to wm_chrome_frame /
; wm_chrome_draw instead of the app's on_frame/on_repaint. Descriptor layout:
;   +0 x +1 y +2 w +3 h +4 min_w +5 min_h +6 proc +8 title
;   +10 task_worker (0 for normal managed windows)
k_wm_managed
                push  af                     ; preserve the registration selector
                call  wm_register            ; HL = desc; register as a normal window (slot,
                                             ; page, focus, z-order, arg, flags=alive; copies
                                             ; desc[0..11] -> entry+1..12). wm_register stashed
                                             ; the desc ptr in wm_desc. Now patch for managed:
                jr    c,kwm_registered
                pop   af
                ret
kwm_registered
                ld    a,(WM_FOCUS)           ; the just-registered window
                call  wm_entry               ; HL = entry
                pop   af                     ; restore the registration selector
                push  hl
                ld    de,WM_FR_FLAGS         ; FLAGS |= managed
                add   hl,de
                set   1,(hl)
                cp    GB_WK_ABI_V1
                jr    nz,kwm_kind_done
                set   4,(hl)                  ; remember explicit v1 registration per window
kwm_kind_done
                pop   hl
                push  hl
                ld    de,WM_FR_FRAME         ; WM_FR_FRAME (entry+5,6) = the descriptor ptr
                add   hl,de
                ld    de,(wm_desc)
                ld    (hl),e
                inc   hl
                ld    (hl),d
                pop   hl
                ld    de,WM_FR_EVENT         ; WM_FR_EVENT = desc.on_event (so bar clicks/drops
                add   hl,de                  ; reach the app's menu handler via the normal path)
                push  hl                     ; HL = entry+9
                ld    hl,(wm_desc)
                ld    de,6                   ; WM_FR_EVENT = desc.proc (#148): menu/drop come
                add   hl,de                  ; through here too, so every message reaches the
                ld    e,(hl)                 ; one WndProc (keyed by gb_msg.type)
                inc   hl
                ld    d,(hl)                 ; DE = proc ptr
                pop   hl                     ; HL = entry+9
                ld    (hl),e
                inc   hl
                ld    (hl),d                 ; REPAINT (entry+7,8) is garbage but the managed
                                             ; flag means wm_repaint_all skips it; MENU (entry+
                                             ; 11,12) temporarily contains task_worker but gb_doc
                                             ; replaces it before the app returns to the WM loop
                ld    hl,(wm_desc)
                ld    de,10
                add   hl,de
                ld    a,(hl)
                inc   hl
                or    (hl)
                call  nz,app_mark_worker_current
                ld    a,(WM_FOCUS)           ; publish MW_RECT so the app can read gb_wm_x/y/w/h
                call  wm_entry               ; in main, but DON'T draw yet: the app loads its
                call  mw_publish             ; content then calls gb_restore_parent for the first
                                             ; paint, so a window never shows empty during a slow
                                             ; load (#146). A managed app MUST paint when ready.
                                             ; mw_publish preserves A (still = WM_FOCUS), so:
                jp    wm_set_clip            ; #153: pre-set the clip to the new window's rect so
                                             ; that first gb_restore_parent repaints only OUR area,
                                             ; not the whole desktop (the open "flash"); then
                                             ; wm_repaint_all restores the full-screen clip.
