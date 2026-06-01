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

WND_TITLE_H     equ   10           ; title bar height (lines)
C_BLUE          equ   #00          ; Mode 1 solid-pen bytes
C_WHITE         equ   #F0
C_BLACK         equ   #0F
C_RED           equ   #FF

draw_window
                ld    a,(wnd_x)              ; content: fill the whole box white
                ld    (fb_x),a
                ld    a,(wnd_y)
                ld    (fb_y),a
                ld    a,(wnd_w)
                ld    (fb_w),a
                ld    a,(wnd_h)
                ld    (fb_h),a
                ld    a,C_WHITE
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

                ld    a,(wnd_x)              ; close gadget: small white box
                inc   a
                ld    (fb_x),a
                ld    a,(wnd_y)
                add   a,2
                ld    (fb_y),a
                ld    a,1
                ld    (fb_w),a
                ld    a,6
                ld    (fb_h),a
                ld    a,C_WHITE
                ld    (fb_val),a
                call  fill_block

                ld    b,1                     ; title: white text on the black bar
                ld    c,2
                call  set_text_pens
                ld    a,(wnd_x)
                add   a,3
                ld    (tc_x),a
                ld    a,(wnd_y)
                inc   a
                ld    (tc_y),a
                ld    hl,(wnd_title)
                jp    draw_text

; --- Current window parameters -------------------------------------------
wnd_x           db    0
wnd_y           db    0
wnd_w           db    0
wnd_h           db    0
wnd_title       dw    0
