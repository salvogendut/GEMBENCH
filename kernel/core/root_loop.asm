; Shared MSX production input/root routing; target leaves and state supplied by providers.
                include "input_routing_contract.inc"
wm_loop
                call  wm_map_focus               ; bank focused page; APP_HANDLER = its
                call  k_poll                      ; on_event, so a top-bar click reaches
                call  wm_focus_click             ; the right app. then route the click.
                include "root_dispatch_phase.asm"
                                                 ; A direct-drawing full-screen app (a .SAV saver) never
                                                 ; goes through wm_repaint_all (which restores the clip),
                                                 ; so without this it inherits the stale damage clip the
                                                 ; desktop bar / a menu action left (#153/#279) - and
                                                 ; clip_fb_copy's 8-bit maths turns that into full-width
                                                 ; fill bands. Managed windows set their own damage
                                                 ; in-frame, so a full default here is harmless.
                ld    a,(WM_FOCUS)               ; call the focused window's on_frame
                call  wm_entry                   ; HL = entry
                push  hl                          ; #146: managed window -> kernel router
                ld    de,WM_FR_FLAGS
                add   hl,de
                if PREEMPTIVE_CONTEXT
                ld    a,(hl)
                pop   hl
                bit   1,a
                else
                bit   1,(hl)
                pop   hl                          ; HL = entry
                endif
                jr    z,wmf_legacy
                call  wm_chrome_frame
                jr    wmf_done
wmf_legacy
                ld    de,WM_FR_FRAME
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                call  md_call
wmf_done
                ld    hl,(BAR_HANDLER)            ; top-bar hook (#77): run the bar handler every
                ld    a,h                          ; frame in the desktop's page so the bar stays
                or    l                            ; live regardless of which window has focus.
                if PREEMPTIVE_CONTEXT
                jr    z,wm_loop_tail               ; bar_draw only repaints lines 0-7 when the clock
                else
                jr    z,wm_loop
                endif
                ld    a,(ROOT_HOME_NATIVE)
                call  bank_set                     ; its own redraws with gb_curhide/show), so the
                ld    hl,(BAR_HANDLER)            ; pointer over the bar is left untouched - do NOT
                call  md_call                      ; erase/show it every frame here: that landed the
                if PREEMPTIVE_CONTEXT
wm_loop_tail
                ld    a,(SCHED_RUNNABLE)
                cp    2                            ; avoid a stack copy when the desktop is alone
                jr    c,wm_loop
                ld    a,(WM_TABLE)                 ; system task snapshot belongs to the root bank
                call  bank_set
                call  SCHED_YIELD_ENTRY
                endif
                ROOT_LOOP_REPEAT
