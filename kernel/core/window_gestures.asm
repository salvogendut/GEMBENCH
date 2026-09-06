; Shared MSX production input/root routing; target leaves and state supplied by providers.
; Kernel-owned outline gestures for explicit v1 kinds. They deliberately retain the
; established app helper's interaction: the window is lifted only after actual
; movement, a red outline follows the held pointer, and one compositor repaint
; restores the stack on release. GB_APP also exposes the geometry engine to a
; legacy gb_win_t callback, whose entry+5 is an on_frame pointer rather than a
; managed descriptor. That path must not dispatch GB_MSG_MOVED through mw_hook.
mw_move_silent
                xor   a
                jr    mwm_mode
mw_move
                ld    a,1
mwm_mode        ld    (mwm_notify),a
                ld    a,(WM_FOCUS)
                call  wm_entry
                push  hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                bit   2,(hl)                  ; a maximised window stays anchored
                pop   hl
                ret   nz
                call  clip_set_full
                ld    a,(MW_RECT)
                ld    (sp_x),a
                ld    b,a
                ld    a,(POLL_MX)
                sub   b
                ld    (WM_DRAGX0),a           ; title grab offset
                ld    a,(MW_RECT+1)
                ld    (sp_y),a
                ld    b,a
                ld    a,(POLL_MY)
                sub   b
                ld    (WM_DRAGY0),a
                ld    a,(MW_RECT+2)
                ld    (ss_w),a
                ld    a,(MW_RECT+3)
                ld    (ss_h),a
                xor   a
                ld    (ghost_on),a
mwm_loop
                call  k_poll
                ld    a,(POLL_FLAGS)
                bit   2,a                     ; fire held
                jr    z,mwm_done
                ld    a,(POLL_MX)
                ld    hl,WM_DRAGX0
                sub   (hl)
                jr    nc,mwm_x_nonnegative
                xor   a
mwm_x_nonnegative
                ld    b,a                     ; B = candidate x
                ld    a,SCR_COLS
                ld    hl,ss_w
                sub   (hl)                    ; A = rightmost x
                cp    b
                jr    nc,mwm_x_clamped
                ld    b,a
mwm_x_clamped
                ld    a,(POLL_MY)
                ld    hl,WM_DRAGY0
                sub   (hl)
                jr    nc,mwm_y_nonnegative
                xor   a
mwm_y_nonnegative
                cp    8                       ; stay below the desktop menu bar
                jr    nc,mwm_y_bar
                ld    a,8
mwm_y_bar       ld    c,a                     ; C = candidate y
                ld    a,SCR_LINES
                ld    hl,ss_h
                sub   (hl)                    ; A = bottommost y
                cp    c
                jr    nc,mwm_y_clamped
                ld    c,a
mwm_y_clamped
                ld    a,(sp_x)
                cp    b
                jr    nz,mwm_changed
                ld    a,(sp_y)
                cp    c
                jr    z,mwm_loop
mwm_changed     push  bc
                call  cursor_erase
                ld    a,(ghost_on)
                or    a
                jr    nz,mwm_erase_outline
                ld    a,1
                ld    (ghost_on),a
                call  mw_gesture_backdrop
                jr    mwm_store
mwm_erase_outline
                xor   a
                call  mw_gesture_outline
mwm_store       pop   bc
                ld    a,b
                ld    (sp_x),a
                ld    a,c
                ld    (sp_y),a
                ld    a,3
                call  mw_gesture_outline
                call  cursor_show
                jr    mwm_loop
mwm_done        ld    a,(ghost_on)
                or    a
                ret   z
                call  cursor_erase
                xor   a
                call  mw_gesture_outline
                call  cursor_show
                ld    a,(sp_y)
                ld    l,a
                ld    a,(sp_x)
                call  k_wm_setpos
                ld    a,(WM_FOCUS)
                call  wm_entry
                call  mw_publish
                ld    a,(MW_RECT)
                ld    (GB_MSG+1),a
                ld    a,(MW_RECT+1)
                ld    (GB_MSG+2),a
                xor   a
                ld    (GB_MSG+3),a
                ld    a,(mwm_notify)
                or    a
                ret   z                          ; legacy caller records geometry, then repaints
                ld    a,GB_MSG_MOVED
                call  mw_hook
                jp    wm_repaint_all

mw_resize
                ld    a,(WM_FOCUS)
                call  wm_entry
                push  hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                bit   2,(hl)                  ; maximise/restore owns full-screen geometry
                pop   hl
                ret   nz
                call  clip_set_full
                ld    a,(MW_RECT)
                ld    (sp_x),a
                ld    a,(MW_RECT+1)
                ld    (sp_y),a
                ld    a,(MW_RECT+2)
                ld    (ss_w),a
                ld    a,(MW_RECT+3)
                ld    (ss_h),a
                ld    hl,(mw_desc)
                ld    de,4
                add   hl,de
                ld    a,(hl)                  ; descriptor min_w/min_h
                ld    (WM_DRAGX0),a
                inc   hl
                ld    a,(hl)
                ld    (WM_DRAGY0),a
                xor   a
                ld    (ghost_on),a
mwr_loop
                call  k_poll
                ld    a,(POLL_FLAGS)
                bit   2,a
                jr    z,mwr_done
                ld    a,(POLL_MX)
                ld    hl,sp_x
                sub   (hl)
                inc   a                       ; inclusive bottom-right pointer
                ld    b,a                     ; B = candidate width
                ld    hl,WM_DRAGX0
                ld    a,b
                cp    (hl)
                jr    nc,mwr_w_min
                ld    b,(hl)
mwr_w_min       ld    a,SCR_COLS
                ld    hl,sp_x
                sub   (hl)
                cp    b
                jr    nc,mwr_w_max
                ld    b,a
mwr_w_max       ld    a,(POLL_MY)
                ld    hl,sp_y
                sub   (hl)
                inc   a
                ld    c,a                     ; C = candidate height
                ld    hl,WM_DRAGY0
                ld    a,c
                cp    (hl)
                jr    nc,mwr_h_min
                ld    c,(hl)
mwr_h_min       ld    a,SCR_LINES
                ld    hl,sp_y
                sub   (hl)
                cp    c
                jr    nc,mwr_h_max
                ld    c,a
mwr_h_max       ld    a,(ss_w)
                cp    b
                jr    nz,mwr_changed
                ld    a,(ss_h)
                cp    c
                jr    z,mwr_loop
mwr_changed     push  bc
                call  cursor_erase
                ld    a,(ghost_on)
                or    a
                jr    nz,mwr_erase_outline
                ld    a,1
                ld    (ghost_on),a
                call  mw_gesture_backdrop
                jr    mwr_store
mwr_erase_outline
                xor   a
                call  mw_gesture_outline
mwr_store       pop   bc
                ld    a,b
                ld    (ss_w),a
                ld    a,c
                ld    (ss_h),a
                ld    a,3
                call  mw_gesture_outline
                call  cursor_show
                jr    mwr_loop
mwr_done        ld    a,(ghost_on)
                or    a
                ret   z
                call  cursor_erase
                xor   a
                call  mw_gesture_outline
                call  cursor_show
                ld    a,(ss_h)
                ld    l,a
                ld    a,(ss_w)
                call  k_wm_setsize
                ld    a,(WM_FOCUS)
                call  wm_entry
                call  mw_publish
                ld    a,(MW_RECT+2)
                ld    (GB_MSG+1),a
                ld    a,(MW_RECT+3)
                ld    (GB_MSG+2),a
                xor   a
                ld    (GB_MSG+3),a
                ld    a,GB_MSG_SIZED
                call  mw_hook
                jp    wm_repaint_all

; A = logical pen, geometry in sp_x/sp_y/ss_w/ss_h.
mw_gesture_outline
                push  af
                ld    a,(sp_x)
                ld    b,a
                ld    a,(sp_y)
                ld    c,a
                ld    a,(ss_w)
                ld    d,a
                ld    a,(ss_h)
                ld    e,a
                pop   af
                jp    k_frame

mw_gesture_backdrop
                ld    a,(sp_x)
                ld    b,a
                ld    a,(sp_y)
                ld    c,a
                ld    a,(ss_w)
                ld    d,a
                ld    a,(ss_h)
                ld    e,a
                jp    k_backdrop

; mw_do_close: a close was requested - deliver GB_MSG_CLOSE to the window's proc
; (it confirms + calls gb_wm_close). Every managed window has a proc, so there is
; no "no handler" path; mw_hook's null guard falls through to no-op if it's ever 0.
mw_do_close
                ld    a,GB_MSG_CLOSE
                jp    mw_hook

                GESTURE_STATE_STORAGE
