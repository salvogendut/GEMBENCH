; ---------------------------------------------------------------------------
; lib/cursor.asm - masked, pre-shifted bitmap mouse cursor with save-under.
;
; Drop-in replacement for the old cross cursor: same interface (cursor_x/
; cursor_y in graphics coords; cursor_show / cursor_move_to / cursor_draw /
; cursor_erase). Uses lib/screen.asm (scr_addr, save_block, restore_block) and a
; sprite from png2spr (cursor_arrow_*).
;
; Draw: save the screen block under the sprite, then composite
;       screen = (saved_background AND mask) OR data
; using the just-saved RAM buffer as the background (so no extra screen reads).
; Erase: restore the saved block.
;
; Requires cursor_arrow.asm + lib/screen.asm assembled in before this.
; ---------------------------------------------------------------------------

CUR_W           equ   cursor_arrow_w
CUR_H           equ   cursor_arrow_h

cursor_show
                ld    a,(cur_shown)          ; already on screen? a bare re-draw would
                or    a                       ; save the cursor into its own save-under
                ret   nz                      ; -> a ghost on the next move (#126). cursor_
                jp    cursor_draw             ; move_to already guards this way (it erases)

; cursor_move_to: DE = x, HL = y (graphics). No-op if unchanged.
cursor_move_to
                ld    a,(cursor_x)
                cp    e
                jr    nz,cm_go
                ld    a,(cursor_x+1)
                cp    d
                jr    nz,cm_go
                ld    a,(cursor_y)
                cp    l
                jr    nz,cm_go
                ld    a,(cursor_y+1)
                cp    h
                jr    nz,cm_go
                ret
cm_go
                ld    a,(cur_supp)           ; suppressed (during a DnD drag, #62)?
                or    a                       ; update the position but don't draw, so
                jr    nz,cm_storeonly         ; the pointer still tracks under the ghost
                push  de
                push  hl
                call  cursor_erase
                pop   hl
                pop   de
                ld    (cursor_x),de
                ld    (cursor_y),hl
                jp    cursor_draw
cm_storeonly
                ld    (cursor_x),de
                ld    (cursor_y),hl
                ret

; cursor_erase: restore the screen block saved at the last draw position.
cursor_erase
                xor   a                       ; cursor no longer on screen (#126)
                ld    (cur_shown),a
                ld    a,(cur_xbyte)
                ld    (sb_x),a
                ld    a,(cur_line)
                ld    (sb_y),a
                ld    a,CUR_W
                ld    (sb_w),a
                ld    a,CUR_H
                ld    (sb_h),a
                ld    hl,cur_bg
                ld    (sb_buf),hl
                jp    restore_block

; cursor_draw: place the sprite at (cursor_x, cursor_y) minus the hotspot.
cursor_draw
                ld    hl,(cursor_x)          ; px = cursor_x/2 - hotspot_x
                srl   h
                rr    l
                ld    de,cursor_arrow_hx
                or    a
                sbc   hl,de
                jr    nc,cd_xok
                ld    hl,0
cd_xok
                ld    a,l                     ; sub = px AND 3
                and   3
                ld    (cur_sub),a
                srl   h                       ; xbyte = px >> 2
                rr    l
                srl   h
                rr    l
                ld    a,l
                cp    80-CUR_W+1              ; clamp to [0, 80-CUR_W]
                jr    c,cd_xb
                ld    a,80-CUR_W
cd_xb
                ld    (cur_xbyte),a
                ld    hl,(cursor_y)          ; line = 199 - cursor_y/2 - hotspot_y
                srl   h
                rr    l
                ld    a,199
                sub   l
                sub   cursor_arrow_hy
                cp    200-CUR_H+1             ; clamp to [0, 200-CUR_H]
                jr    c,cd_yb
                ld    a,200-CUR_H
cd_yb
                ld    (cur_line),a

                ld    a,(cur_xbyte)          ; save the background block
                ld    (sb_x),a
                ld    a,(cur_line)
                ld    (sb_y),a
                ld    a,CUR_W
                ld    (sb_w),a
                ld    a,CUR_H
                ld    (sb_h),a
                ld    hl,cur_bg
                ld    (sb_buf),hl
                call  save_block

                ld    a,(cur_sub)            ; pick the pre-shifted data/mask
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,cursor_arrow_data
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                ld    (cur_dptr),hl
                ld    a,(cur_sub)
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,cursor_arrow_mask
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                ld    (cur_mptr),hl
                ld    hl,cur_bg
                ld    (cur_bgp),hl

                ld    a,CUR_H                 ; composite into screen
                ld    (cc_rows),a
                ld    a,(cur_line)
                ld    (cc_y),a
cc_row
                ld    a,(cur_xbyte)
                ld    d,a
                ld    a,(cc_y)
                ld    e,a
                call  scr_addr               ; HL = screen row addr
                ld    a,CUR_W
                ld    (cc_cols),a
cc_col
                push  hl
                ld    hl,(cur_bgp)           ; A = background byte
                ld    a,(hl)
                inc   hl
                ld    (cur_bgp),hl
                ld    hl,(cur_mptr)
                and   (hl)                    ; A = bg AND mask
                inc   hl
                ld    (cur_mptr),hl
                ld    hl,(cur_dptr)
                or    (hl)                    ; A = (bg AND mask) OR data
                inc   hl
                ld    (cur_dptr),hl
                pop   hl
                ld    (hl),a
                inc   hl
                ld    a,(cc_cols)
                dec   a
                ld    (cc_cols),a
                jr    nz,cc_col
                ld    a,(cc_y)
                inc   a
                ld    (cc_y),a
                ld    a,(cc_rows)
                dec   a
                ld    (cc_rows),a
                jr    nz,cc_row
                ld    a,1                      ; cursor now on screen (#126)
                ld    (cur_shown),a
                ret

; --- State ---------------------------------------------------------------
cursor_x        dw    320
cursor_y        dw    200
cur_xbyte       db    0
cur_line        db    0
cur_supp        db    0            ; 1 = suppress drawing (DnD drag shows a ghost instead)
cur_shown       db    0            ; 1 = the arrow is currently composited on screen (#126)
cur_sub         db    0
cur_dptr        dw    0
cur_mptr        dw    0
cur_bgp         dw    0
cc_rows         db    0
cc_y            db    0
cc_cols         db    0
cur_bg          defs  cursor_arrow_w*cursor_arrow_h
