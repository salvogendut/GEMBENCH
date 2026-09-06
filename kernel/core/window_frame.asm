; Shared MSX production input/root routing; target leaves and state supplied by providers.
wm_chrome_frame
                call  mw_publish
                call  mw_kind_load
                ld    a,GB_MSG_FRAME         ; per-frame (idle/menus/tick)
                call  mw_hook
                ld    a,(POLL_FLAGS)
                bit   1,a                     ; GB_QUIT
                jr    z,mwf_click_check
                ld    a,(mw_kind)
                bit   1,a                     ; v1 windows without GB_WK_CLOSE stay open
                jp    nz,mw_do_close
mwf_click_check
                ld    a,(POLL_FLAGS)
                bit   0,a                     ; GB_CLICK
                ret   z
                ld    a,(mw_kind)
                bit   0,a                     ; no title band: the whole framed area is content
                jp    z,mwf_content
                ld    a,(POLL_MY)            ; my - win_y in title band?
                ld    e,a
                ld    a,(MW_RECT+1)
                ld    d,a
                ld    a,e
                sub   d
                jp    c,mwf_content           ; my < win_y
                cp    14                       ; TITLE_H
                jp    nc,mwf_content           ; my >= win_y+14 -> content
                ld    a,(POLL_MX)            ; in title bar: which gadget?
                ld    e,a
                ld    a,(mw_kind)
                bit   1,a                     ; GB_WK_CLOSE
                jr    z,mwf_notclose
                ld    a,(MW_RECT)
                add   a,5
                cp    e
                jr    c,mwf_notclose          ; win_x+5 < mx -> not the close gadget
                jr    z,mwf_notclose
                jp    mw_do_close             ; mx < win_x+5 -> close gadget
mwf_notclose
                ifdef WM_GADGETS
                ld    a,(mw_kind)
                bit   2,a                     ; GB_WK_MAXIMIZE
                jr    z,mwf_title
                ld    a,(MW_RECT)            ; maximize gadget? mx >= win_x + win_w - 4
                ld    hl,MW_RECT+2
                add   a,(hl)                  ; A = win_x + win_w
                sub   4
                cp    e
                jr    c,mwf_max              ; (win_x+win_w-4) < mx -> maximize/restore
                jr    z,mwf_max
                endif
mwf_title
                ld    a,(mw_kind)
                bit   7,a                     ; legacy descriptor: preserve GB_MSG_DRAG
                jr    z,mwf_legacy_drag
                bit   3,a                     ; v1 but not movable: consume title press
                ret   z
                jp    mw_move
mwf_legacy_drag
                ld    a,GB_MSG_DRAG          ; otherwise a title-bar press -> drag the window
                jp    mw_hook
                ifdef WM_GADGETS
; mwf_max: the maximize/restore gadget does a WINDOWED maximize (chrome stays) - distinct from
; the borderless View>Fullscreen / 'F' (the app's on_fullscreen). Toggle the focused window
; between its saved size and full-below-the-bar (0,8 .. 80x192); flags bit2 (MW_MAXED) tracks
; which way. The pre-max geometry is one global, so restoring the earlier of two maximized
; windows would use the later one's size - a rare case not worth a per-window store.
mwf_max         ld    a,(WM_FOCUS)
                call  wm_entry               ; HL = focused entry
                push  hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                bit   2,(hl)                  ; already maximized?
                jr    nz,mwf_unmax
                set   2,(hl)
                pop   hl                      ; HL = entry; save geom, then fill the screen
                push  hl
                inc   hl
                ld    a,(hl)
                ld    (wm_sav_x),a
                ld    (hl),0
                inc   hl
                ld    a,(hl)
                ld    (wm_sav_y),a
                ld    (hl),8
                inc   hl
                ld    a,(hl)
                ld    (wm_sav_w),a
                ld    (hl),SCR_COLS
                inc   hl
                ld    a,(hl)
                ld    (wm_sav_h),a
                ld    (hl),SCR_LINES-8
                jr    mwf_max_paint
mwf_unmax       res   2,(hl)
                pop   hl                      ; HL = entry; restore the saved geometry
                push  hl
                inc   hl
                ld    a,(wm_sav_x)
                ld    (hl),a
                inc   hl
                ld    a,(wm_sav_y)
                ld    (hl),a
                inc   hl
                ld    a,(wm_sav_w)
                ld    (hl),a
                inc   hl
                ld    a,(wm_sav_h)
                ld    (hl),a
mwf_max_paint   pop   hl                      ; HL = entry
                call  mw_publish             ; refresh MW_RECT (the app reads gb_wm_x/y/w/h)
                call  clip_set_full
                push  hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                ld    a,(hl)
                and   4                       ; p0 = 1 maximised, 0 restored
                jr    z,mwf_max_msg_state
                ld    a,1
mwf_max_msg_state
                ld    (GB_MSG+1),a
                ld    a,(MW_RECT+2)
                ld    (GB_MSG+2),a
                ld    a,(MW_RECT+3)
                ld    (GB_MSG+3),a
                pop   hl
                ld    a,GB_MSG_MAXIMIZED
                call  mw_hook
                jp    wm_repaint_all
                ROUTER_MAX_STORAGE
                endif
mwf_content
                ld    a,(mw_kind)
                bit   7,a                     ; only explicit v1 kinds get kernel resize
                jr    z,mwf_content_hook
                bit   4,a                     ; GB_WK_RESIZE
                jr    z,mwf_content_hook
                ld    a,(MW_RECT)
                ld    hl,MW_RECT+2
                add   a,(hl)                  ; right edge (exclusive)
                ld    b,a
                ld    a,(POLL_MX)
                cp    b
                jr    nc,mwf_content_hook
                ld    a,b
                sub   6                       ; generous invisible target around 2-byte grip
                ld    b,a
                ld    a,(POLL_MX)
                cp    b
                jr    c,mwf_content_hook
                ld    a,(MW_RECT+1)
                ld    hl,MW_RECT+3
                add   a,(hl)                  ; bottom edge (exclusive)
                ld    b,a
                ld    a,(POLL_MY)
                cp    b
                jr    nc,mwf_content_hook
                ld    a,b
                sub   14                      ; keyboard/joystick pointer may accelerate
                ld    b,a
                ld    a,(POLL_MY)
                cp    b
                jp    nc,mw_resize
mwf_content_hook
                ld    a,GB_MSG_CLICK         ; content (incl. grip) -> a content press
                jp    mw_hook
