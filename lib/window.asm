; ---------------------------------------------------------------------------
; lib/window.asm - draw a window frame (Workbench-style).
;
; Screen byte/line coords. A window is white content inside a black border, with
; a black title bar across the top holding a close gadget and the title text.
;
; Requires lib/screen.asm (fill_block) and lib/text.asm. Assembled in; no org.
;
; Set wnd_x (byte col), wnd_y (line), wnd_w (bytes), wnd_h (lines), wnd_title
; (0-term string), then call draw_window.
; ---------------------------------------------------------------------------

WND_TITLE_H     equ   14           ; title bar height (lines)
C_BLUE          equ   #00          ; Mode 1 solid-pen bytes
C_WHITE         equ   #F0
C_BLACK         equ   #0F
C_RED           equ   #FF

draw_window
                ld    a,(wnd_x)              ; content: fill the whole box
                ld    (fb_x),a
                ld    a,(wnd_y)
                ld    (fb_y),a
                ld    a,(wnd_w)
                ld    (fb_w),a
                ld    a,(wnd_h)
                ld    (fb_h),a
                ld    a,(wnd_content)
                ld    (fb_val),a
                call  fill_block

                ld    a,(wnd_x)              ; title bar: black across the top
                ld    (fb_x),a
                ld    a,(wnd_y)
                ld    (fb_y),a
                ld    a,(wnd_w)
                ld    (fb_w),a
                ld    a,WND_TITLE_H
                ld    (fb_h),a
                ld    a,C_BLACK
                ld    (fb_val),a
                call  fill_block

                ld    a,(wnd_x)              ; left border column
                ld    (fb_x),a
                ld    a,(wnd_y)
                ld    (fb_y),a
                ld    a,1
                ld    (fb_w),a
                ld    a,(wnd_h)
                ld    (fb_h),a
                call  fill_block             ; (fb_val still black)

                ld    a,(wnd_x)              ; right border column
                ld    b,a
                ld    a,(wnd_w)
                add   a,b
                dec   a
                ld    (fb_x),a
                ld    a,(wnd_y)
                ld    (fb_y),a
                ld    a,1
                ld    (fb_w),a
                ld    a,(wnd_h)
                ld    (fb_h),a
                call  fill_block

                ld    a,(wnd_x)              ; bottom border row
                ld    (fb_x),a
                ld    a,(wnd_h)
                ld    b,a
                ld    a,(wnd_y)
                add   a,b
                dec   a
                ld    (fb_y),a
                ld    a,(wnd_w)
                ld    (fb_w),a
                ld    a,1
                ld    (fb_h),a
                call  fill_block

                ld    a,(wnd_x)              ; close gadget: white box (8x10 px)
                inc   a
                ld    (fb_x),a
                ld    a,(wnd_y)
                add   a,2
                ld    (fb_y),a
                ld    a,2
                ld    (fb_w),a
                ld    a,10
                ld    (fb_h),a
                ld    a,C_WHITE
                ld    (fb_val),a
                call  fill_block

                ld    b,1                     ; title: white text on the black bar
                ld    c,2
                call  set_text_pens
                ld    a,(wnd_x)
                add   a,4
                ld    (tc_x),a
                ld    a,(wnd_y)
                add   a,3
                ld    (tc_y),a
                ld    hl,(wnd_title)
                jp    draw_text

; ---------------------------------------------------------------------------
; window_open: save the screen region the window will cover, then draw it.
; window_close: restore that region (revealing whatever was underneath).
window_open
                call  win_set_sb
                call  save_block
                call  draw_window
                ld    a,1
                ld    (win_open),a
                ret

window_close
                call  win_set_sb
                call  restore_block
                xor   a
                ld    (win_open),a
                ret

; point save_block/restore_block at the window's rectangle + its buffer.
win_set_sb
                ld    a,(wnd_x)
                ld    (sb_x),a
                ld    a,(wnd_y)
                ld    (sb_y),a
                ld    a,(wnd_w)
                ld    (sb_w),a
                ld    a,(wnd_h)
                ld    (sb_h),a
                ld    hl,win_buf
                ld    (sb_buf),hl
                ret

; cursor_to_screen: ch_xb = cursor byte column, ch_ln = cursor line.
cursor_to_screen
                ld    hl,(cursor_x)          ; cur xbyte = cursor_x >> 3
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                ld    (ch_xb),a
                ld    hl,(cursor_y)          ; cur line = 199 - (cursor_y >> 1)
                srl   h
                rr    l
                ld    a,199
                sub   l
                ld    (ch_ln),a
                ret

; title_hit: carry set if the cursor is anywhere on the title bar.
title_hit
                call  cursor_to_screen
                ld    hl,wnd_x               ; xbyte in [wnd_x, wnd_x+wnd_w) ?
                ld    a,(ch_xb)
                cp    (hl)
                jr    c,ch_no
                ld    a,(hl)
                ld    b,a
                ld    a,(wnd_w)
                add   a,b
                ld    b,a
                ld    a,(ch_xb)
                cp    b
                jr    nc,ch_no
                ld    hl,wnd_y               ; line in [wnd_y, wnd_y+WND_TITLE_H) ?
                ld    a,(ch_ln)
                cp    (hl)
                jr    c,ch_no
                ld    a,(hl)
                add   a,WND_TITLE_H
                ld    b,a
                ld    a,(ch_ln)
                cp    b
                jr    nc,ch_no
                scf
                ret

; close_hit: carry set if the cursor is over the close gadget area - the left
; three byte columns of the title bar.
close_hit
                call  cursor_to_screen
                ld    hl,wnd_x               ; xbyte in [wnd_x, wnd_x+3) ?
                ld    a,(ch_xb)
                cp    (hl)
                jr    c,ch_no
                ld    a,(hl)
                add   a,3
                ld    b,a
                ld    a,(ch_xb)
                cp    b
                jr    nc,ch_no
                ld    hl,wnd_y               ; line in [wnd_y, wnd_y+WND_TITLE_H) ?
                ld    a,(ch_ln)
                cp    (hl)
                jr    c,ch_no
                ld    a,(hl)
                add   a,WND_TITLE_H
                ld    b,a
                ld    a,(ch_ln)
                cp    b
                jr    nc,ch_no
                scf
                ret
ch_no
                or    a
                ret

; --- Current window parameters / state -----------------------------------
wnd_x           db    0
wnd_y           db    0
wnd_w           db    0
wnd_h           db    0
wnd_title       dw    0
wnd_content     db    #F0          ; content fill byte (#F0 white by default)
win_open        db    0
ch_xb           db    0
ch_ln           db    0
win_buf         defs  6400         ; save-under buffer (>= wnd_w*wnd_h, any window)
