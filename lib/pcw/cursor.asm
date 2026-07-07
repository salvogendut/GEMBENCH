; ---------------------------------------------------------------------------
; lib/pcw/cursor.asm - masked, pre-shifted software pointer for the PCW (#331).
;
; The PCW has no hardware sprites, so this is lib/cursor.asm (the CPC
; software pointer: save-under + interleaved mask,data composite) adapted to
; the CGA2 driver:
;   - scr_addr -> pcw_addr (same register contract), and the composite walks
;     the screen with stride 8 (char-cell interleave)
;   - geometry: 90 byte cols x 248 lines; line = 247 - cursor_y/2
;   - sprite bytes are 4px/byte 2-bit fields like the CPC's Mode 1, so
;     lib/cursor_arrow.asm (geometry + phase tables over CUR_LOW) is reused
;     verbatim; the .SPR asset content is PCW-specific (hardware-space data
;     with 11-per-kept-field masks, 2 pre-shifted phases, png2spr --platform
;     pcw)
;
; Same interface as both other pointers: cursor_x/cursor_y (virtual units,
; 2 per pixel, Y flipped), cursor_show / cursor_move_to / cursor_draw /
; cursor_erase, cur_supp / cur_paintlock flags.
; Requires cursor_arrow.asm + lib/pcw/screen.asm assembled in before this.
; ---------------------------------------------------------------------------

CUR_W           equ   cursor_arrow_w
CUR_H           equ   cursor_arrow_h

cursor_show
                ld    a,(cur_paintlock)      ; suppressed inside wm_repaint_all
                or    a
                ret   nz
                ld    a,(cur_shown)          ; already on screen? a bare re-draw
                or    a                       ; would save the cursor into its own
                ret   nz                      ; save-under -> ghost (#126)
                jp    cursor_draw

; cursor_move_to: DE = x, HL = y (virtual units). No-op if unchanged.
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
                ret   z
cm_go
                ld    a,(cur_supp)           ; suppressed (DnD ghost): track only
                or    a
                jr    nz,cm_storeonly
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
                ld    a,(cur_paintlock)
                or    a
                ret   nz
                xor   a                       ; cursor no longer on screen (#126)
                ld    (cur_shown),a
                call  cur_setsb
                jp    restore_block

; cur_setsb: point the shared save_block/restore_block params (sb_*) at the
; cursor's clipped on-screen rectangle + cur_bg buffer.
cur_setsb
                ld    a,(cur_xbyte)
                ld    (sb_x),a
                ld    a,(cur_line)
                ld    (sb_y),a
                ld    a,(cur_dcols)           ; clipped extent
                ld    (sb_w),a
                ld    a,(cur_drows)
                ld    (sb_h),a
                ld    hl,cur_bg
                ld    (sb_buf),hl
                ret

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
                cp    PCW_COLS                ; clamp hotspot byte so the tip can
                jr    c,cd_xb                 ; reach the right border
                ld    a,PCW_COLS-1
cd_xb
                ld    (cur_xbyte),a
                sub   PCW_COLS-CUR_W          ; sprite cols off the right edge
                jr    nc,cd_xclip
                xor   a
cd_xclip
                ld    (cur_skip),a
                ld    b,a                     ; cur_dcols = CUR_W - cur_skip
                ld    a,CUR_W
                sub   b
                ld    (cur_dcols),a
                ld    hl,(cursor_y)          ; line = 247 - cursor_y/2 - hotspot_y
                srl   h
                rr    l
                ld    a,PCW_LINES-1
                sub   l
                sub   cursor_arrow_hy
                ld    (cur_line),a
                sub   PCW_LINES-CUR_H         ; rows off the bottom edge
                jr    nc,cd_yclip
                xor   a
cd_yclip
                ld    b,a                     ; cur_drows = CUR_H - clipped rows
                ld    a,CUR_H
                sub   b
                ld    (cur_drows),a

                call  cur_setsb              ; save the background under the sprite
                call  save_block
                ld    a,(cur_sub)            ; HL = interleaved (mask,data) sprite
                add   a,a                     ; for this sub-phase
                ld    e,a
                ld    d,0
                ld    hl,cursor_arrow_spr
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                ld    de,cur_bg              ; DE = saved-background read ptr
                ld    a,(cur_drows)
                ld    (cc_rows),a
                ld    a,(cur_line)
                ld    (cc_y),a
                ; composite: screen = (saved bg AND mask) OR data, all three
                ; pointers in registers; the screen pointer steps by 8.
cc_row
                push  hl                      ; keep sprite + save ptrs across pcw_addr
                push  de
                ld    a,(cur_xbyte)
                ld    d,a
                ld    a,(cc_y)
                ld    e,a
                call  pcw_addr               ; HL = screen row addr (block mapped)
                ld    b,h
                ld    c,l                     ; BC = screen ptr
                pop   de                      ; DE = save-under ptr
                pop   hl                      ; HL = sprite ptr
                ld    a,(cur_dcols)
                ld    (cc_cols),a
cc_col
                ld    a,(de)                  ; bg from the saved buffer
                inc   de
                and   (hl)                    ; (bg AND mask)
                inc   hl
                or    (hl)                    ;         OR data
                inc   hl
                ld    (bc),a                  ; composite to the screen
                ld    a,c                     ; BC += 8 (x-neighbour stride)
                add   a,8
                ld    c,a
                jr    nc,cc_nc
                inc   b
cc_nc
                ld    a,(cc_cols)
                dec   a
                ld    (cc_cols),a
                jr    nz,cc_col
                ld    a,(cur_skip)            ; skip clipped sprite cols (x2 = mask+data)
                add   a,a
                ld    c,a
                ld    b,0
                add   hl,bc                   ; advance sprite ptr to the next row
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
cursor_x        dw    360                    ; virtual units (2 per pixel)
cursor_y        dw    248
cur_xbyte       db    0
cur_line        db    0
cur_supp        db    0            ; 1 = suppress drawing (DnD ghost)
cur_shown       db    0            ; 1 = the arrow is composited on screen
cur_paintlock   db    0            ; 1 = inside wm_repaint_all
cur_sub         db    0
cc_rows         db    0
cc_y            db    0
cc_cols         db    0
cur_dcols       db    cursor_arrow_w
cur_drows       db    cursor_arrow_h
cur_skip        db    0
cur_bg          equ   #1291        ; 64-byte save-under (same low-RAM home as CPC)
