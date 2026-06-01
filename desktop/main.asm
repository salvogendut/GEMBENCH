; ---------------------------------------------------------------------------
; GEOBENCH - desktop shell
;
; Paints the desktop (Mode 1 backdrop, title bar, help line) and runs the main
; loop: poll input, move the pointer, quit on request. The pointer, save-under
; drawing and input reads live in the lib/ modules assembled in below.
;
; Built by tools/build.sh into build/geobench.dsk as GEOBENCH.BIN.
; ---------------------------------------------------------------------------

                include "../lib/firmware.inc"

                org   #4000
geobench
                jp    desktop_start          ; AMSDOS entry point at #4000

; --- Library modules (assembled in) --------------------------------------
                include "../lib/input.asm"
                include "../lib/graphics.asm"
                include "../lib/screen.asm"
                include "../lib/cursor_arrow.asm"
                include "../lib/cursor.asm"
                include "../lib/icon_floppy.asm"
                include "../lib/icon_clock.asm"
                include "../lib/icon_trash.asm"

; --- Palette (firmware ink numbers 0..26) --------------------------------
INK_DESKTOP     equ   1           ; blue        -> pen 0 (paper / backdrop)
INK_LIGHT       equ   26          ; bright white-> pen 1 (title bar, text)
INK_DARK        equ   0           ; black       -> pen 2 (pointer, outlines)
INK_ACCENT      equ   6           ; bright red  -> pen 3 (accents)

; --- Pointer movement / bounds (graphics coords: 0..639 x, 0..399 y) -----
; The pointer accelerates while a direction is held: it starts at SPD_MIN for
; precise taps and ramps by SPD_INC each frame up to SPD_MAX, resetting to
; SPD_MIN whenever no direction is held.
SPD_MIN         equ   2           ; step on the first frame of a press
SPD_INC         equ   2           ; added each held frame
SPD_MAX         equ   16          ; top speed (8 px/frame in Mode 1)
PXMIN           equ   0            ; the bitmap cursor clamps its own sprite,
PXMAX           equ   639          ; so the hotspot may range the full screen
PYMIN           equ   0
PYMAX           equ   399

; --- Icons ---------------------------------------------------------------
; Icons live in a table of parallel arrays (icon_xs/icon_ys/icon_shapes).
; icon_x,icon_y is the lower-left of the WxH bounding box. Selection and the
; drag outline are a square frame FRAME_G units OUTSIDE the box, drawn in the
; plain backdrop margin so erasing them with the backdrop pen stays safe.
NUM_ICONS       equ   3
ICON_W          equ   80           ; bounding box width  (40 px in Mode 1)
ICON_H          equ   80           ; height (40 px)
FRAME_G         equ   4            ; selection/drag frame margin (2 px outside)
; The box holds a smaller shape in its top portion and a 1-row label band at
; its bottom (8 px). The label therefore sits inside the box/outline.
LABEL_BAND      equ   16           ; bottom band reserved for the label (8 px)
SHAPE_INSET     equ   8            ; icon bitmap inset from the box sides (4 px)
BMP_W           equ   8            ; icon bitmaps are 8 bytes (32 px) ...
BMP_H           equ   32           ; ... by 32 rows
NO_ICON         equ   255
IXMIN           equ   FRAME_G
IXMAX           equ   639-ICON_W-FRAME_G
; Lower bound keeps the label (the box's bottom text row) on screen: at wy=16
; it lands on row 24, clear of the last row, so printing it never scrolls.
IYMIN           equ   16
; Keep the frame's top edge below the text (rows 0-1 = pixel lines 0-15).
; graphics y maps to line 199 - y/2, so frame top (y+ICON_H+FRAME_G) <= 366.
IYMAX           equ   366-ICON_H-FRAME_G
PEN_DESKTOP     equ   0            ; backdrop (used to erase)
PEN_BODY        equ   1            ; white icon body
PEN_BORDER      equ   2            ; black square-icon border
PEN_SELECT      equ   3            ; accent selection / drag frame

; ---------------------------------------------------------------------------
desktop_start
                ld    a,1
                call  SCR_SET_MODE           ; Mode 1, 320x200, 4 pens. Clears.
                call  TXT_CUR_DISABLE        ; no blinking text cursor blob
                call  TXT_CUR_OFF
                call  set_palette
                call  draw_title_bar
                call  draw_help
                call  draw_all_icons         ; before the cursor, so it saves
                call  cursor_show            ;   the icon pixels underneath

; --- Main loop -----------------------------------------------------------
mainloop
                call  MC_WAIT_FLYBACK        ; pace at 50 Hz, redraw in vblank
                call  input_poll             ; -> in_dirs, in_quit

                ld    a,(in_dirs)            ; keep the direction mask in B
                ld    b,a
                call  update_speed           ; -> C = this frame's step

                ld    hl,(cursor_x)          ; target x
                bit   2,b                    ; DIR_LEFT
                jr    z,ml_xr
                ld    e,c
                ld    d,0
                or    a
                sbc   hl,de
                jr    nc,ml_xr               ; floor underflow to 0
                ld    hl,0
ml_xr
                bit   3,b                    ; DIR_RIGHT
                jr    z,ml_xc
                ld    e,c
                ld    d,0
                add   hl,de
ml_xc
                ld    de,PXMIN
                call  clamp_lo
                ld    de,PXMAX
                call  clamp_hi
                push  hl                     ; stash target x

                ld    hl,(cursor_y)          ; target y
                bit   0,b                    ; DIR_UP -> +y
                jr    z,ml_yd
                ld    e,c
                ld    d,0
                add   hl,de
ml_yd
                bit   1,b                    ; DIR_DOWN -> -y
                jr    z,ml_yc
                ld    e,c
                ld    d,0
                or    a
                sbc   hl,de
                jr    nc,ml_yc               ; floor underflow to 0
                ld    hl,0
ml_yc
                ld    de,PYMIN
                call  clamp_lo
                ld    de,PYMAX
                call  clamp_hi

                pop   de                     ; DE = target x, HL = target y
                ld    (tgt_x),de
                ld    (tgt_y),hl

                ld    a,(dragging)
                or    a
                jr    nz,ml_drag
                ld    de,(tgt_x)             ; not dragging: just move the cursor
                ld    hl,(tgt_y)
                call  cursor_move_to
                jr    ml_fire
ml_drag
                call  drag_frame             ; dragging: move icon + cursor together
ml_fire
                call  handle_fire

                ld    a,(in_quit)
                or    a
                jr    nz,quit
                jp    mainloop

quit
                ld    a,1                     ; tidy the screen on the way out
                call  SCR_SET_MODE
                ret

; ---------------------------------------------------------------------------
; update_speed: B = direction mask. With a direction held, accelerate spd by
; SPD_INC up to SPD_MAX; otherwise reset to SPD_MIN. Returns the step in C.
update_speed
                ld    a,b
                or    a
                jr    z,us_reset             ; nothing held -> back to base speed
                ld    a,(spd)
                add   a,SPD_INC
                cp    SPD_MAX
                jr    c,us_store
                ld    a,SPD_MAX
                jr    us_store
us_reset
                ld    a,SPD_MIN
us_store
                ld    (spd),a
                ld    c,a
                ret

; ---------------------------------------------------------------------------
; handle_fire: edge-detect the fire/select button.
;   - rising edge over an icon    -> select it and begin dragging
;   - rising edge over empty space -> deselect
;   - falling edge -> drop the dragged icon
handle_fire
                ld    a,(in_fire)
                ld    b,a                     ; fire now
                ld    a,(last_fire)
                ld    c,a                     ; fire previous frame
                ld    a,b
                ld    (last_fire),a

                or    a
                jr    nz,hf_down              ; held now?
                ld    a,(dragging)            ; released: drop if we were dragging
                or    a
                ret   z
                jp    drop_drag
hf_down
                ld    a,c
                or    a
                ret   nz                      ; already held -> not a fresh press

                call  hit_test_icons          ; A = icon index, carry if hit
                jr    c,hf_grab
                jp    deselect_current        ; pressed empty space
hf_grab
                ld    (drag_idx),a            ; the icon under the pointer
                ld    b,a
                ld    a,(sel_icon)            ; a different icon selected? clear it
                cp    NO_ICON
                jr    z,hf_sel
                cp    b
                jr    z,hf_sel
                push  bc
                call  deselect_current
                pop   bc
hf_sel
                ld    a,b
                ld    (sel_icon),a
                jp    start_drag

; deselect_current: erase the selected icon's frame, if any.
deselect_current
                ld    a,(sel_icon)
                cp    NO_ICON
                ret   z
                call  load_icon
                call  cursor_erase
                ld    a,PEN_DESKTOP
                call  draw_frame
                call  repair_others
                call  cursor_draw
                ld    a,NO_ICON
                ld    (sel_icon),a
                ret

; ---------------------------------------------------------------------------
; start_drag: erase the dragged icon's body (it goes "transparent") and show
; the lightweight drag frame the pointer carries around.
start_drag
                ld    a,1
                ld    (dragging),a
                ld    a,(drag_idx)
                call  load_icon               ; wx,wy = icon position
                ld    hl,(wx)
                ld    (drag_x),hl
                ld    hl,(wy)
                ld    (drag_y),hl
                ld    hl,(cursor_x)           ; grab offset = cursor - icon corner
                ld    de,(wx)
                or    a
                sbc   hl,de
                ld    (grab_dx),hl
                ld    hl,(cursor_y)
                ld    de,(wy)
                or    a
                sbc   hl,de
                ld    (grab_dy),hl

                call  cursor_erase
                call  erase_body              ; clears the whole box (shape+label)
                ld    a,PEN_DESKTOP           ; clear any old static frame
                call  draw_frame
                call  repair_others           ; restore icons under the cleared area
                ld    hl,(drag_x)            ; wx,wy = drag position
                ld    (wx),hl
                ld    hl,(drag_y)
                ld    (wy),hl
                ld    a,PEN_SELECT            ; show the drag frame
                call  draw_frame
                call  cursor_draw
                ret

; drop_drag: erase the drag frame, then stamp the icon and a selection frame at
; the snapped final position.
drop_drag
                call  cursor_erase
                ld    hl,(drag_x)            ; erase the drag frame where it is
                ld    (wx),hl
                ld    hl,(drag_y)
                ld    (wy),hl
                ld    a,PEN_DESKTOP
                call  draw_frame
                call  repair_others           ; (still dragging -> skips this icon)
                xor   a
                ld    (dragging),a

                ld    hl,(drag_x)            ; snap the dropped position to the grid
                call  snap16
                ld    de,IXMIN
                call  clamp_lo
                ld    de,IXMAX
                call  clamp_hi
                ld    (wx),hl
                ld    hl,(drag_y)
                call  snap16
                ld    de,IYMIN
                call  clamp_lo
                ld    de,IYMAX
                call  clamp_hi
                ld    (wy),hl
                ld    a,(drag_idx)
                call  store_icon_xy           ; commit new position
                ld    a,(drag_idx)
                call  load_icon               ; refresh wx,wy,wshape,wlabel
                call  draw_icon_full          ; draw icon at the snapped position
                ld    a,PEN_SELECT            ; selection frame around it
                call  draw_frame
                call  redraw_all_labels       ; repair any labels nicked during drag
                call  cursor_draw
                ret

; redraw_all_labels: reprint every icon's label. Used on drop to restore labels
; that the per-frame shape-only repair left nicked (keeps text off the drag path).
redraw_all_labels
                xor   a
ral_loop
                push  af
                call  load_icon
                ld    a,1
                call  draw_label
                pop   af
                inc   a
                cp    NUM_ICONS
                jr    c,ral_loop
                ret

; ---------------------------------------------------------------------------
; drag_frame: move the drag frame to follow the pointer (target - grab offset)
; and the cursor to its target, recompositing only if something moved.
drag_frame
                ld    hl,(tgt_x)             ; new frame x = tgt_x - grab_dx
                ld    de,(grab_dx)
                or    a
                sbc   hl,de
                jr    nc,df_xok
                ld    hl,0                    ; floor underflow
df_xok
                ld    de,IXMIN
                call  clamp_lo
                ld    de,IXMAX
                call  clamp_hi
                ld    (nicon_x),hl

                ld    hl,(tgt_y)             ; new frame y = tgt_y - grab_dy
                ld    de,(grab_dy)
                or    a
                sbc   hl,de
                jr    nc,df_yok
                ld    hl,0
df_yok
                ld    de,IYMIN
                call  clamp_lo
                ld    de,IYMAX
                call  clamp_hi
                ld    (nicon_y),hl

                ld    hl,(tgt_x)             ; anything moved? (cursor or frame)
                ld    de,(cursor_x)
                or    a
                sbc   hl,de
                jr    nz,df_go
                ld    hl,(tgt_y)
                ld    de,(cursor_y)
                or    a
                sbc   hl,de
                jr    nz,df_go
                ld    hl,(nicon_x)
                ld    de,(drag_x)
                or    a
                sbc   hl,de
                jr    nz,df_go
                ld    hl,(nicon_y)
                ld    de,(drag_y)
                or    a
                sbc   hl,de
                ret   z                       ; nothing moved -> leave it be
df_go
                call  cursor_erase            ; lift cursor from old position
                ld    hl,(drag_x)            ; erase frame at the old spot
                ld    (wx),hl
                ld    hl,(drag_y)
                ld    (wy),hl
                ld    a,PEN_DESKTOP
                call  draw_frame
                call  repair_others           ; restore any icon under the old frame
                ld    hl,(nicon_x)           ; advance the drag position
                ld    (drag_x),hl
                ld    (wx),hl                ; wx,wy = new drag position
                ld    hl,(nicon_y)
                ld    (drag_y),hl
                ld    (wy),hl
                ld    a,PEN_SELECT            ; draw frame at the new spot
                call  draw_frame
                ld    hl,(tgt_x)             ; move cursor to its target
                ld    (cursor_x),hl
                ld    hl,(tgt_y)
                ld    (cursor_y),hl
                call  cursor_draw
                ret

; ---------------------------------------------------------------------------
; load_icon: A = index -> wx,wy = icon position, wshape = shape.
load_icon
                ld    (li_idx),a
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,icon_xs
                add   hl,de
                ld    c,(hl)
                inc   hl
                ld    b,(hl)
                ld    (wx),bc
                ld    hl,icon_ys
                add   hl,de
                ld    c,(hl)
                inc   hl
                ld    b,(hl)
                ld    (wy),bc
                ld    a,(li_idx)             ; bitmap pointer (word array)
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,icon_bmps
                add   hl,de
                ld    c,(hl)
                inc   hl
                ld    b,(hl)
                ld    (wbmp),bc
                ld    a,(li_idx)             ; label pointer (word array)
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,icon_labels
                add   hl,de
                ld    c,(hl)
                inc   hl
                ld    b,(hl)
                ld    (wlabel),bc
                ret

; store_icon_xy: A = index <- wx,wy.
store_icon_xy
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,icon_xs
                add   hl,de
                ld    bc,(wx)
                ld    (hl),c
                inc   hl
                ld    (hl),b
                ld    hl,icon_ys
                add   hl,de
                ld    bc,(wy)
                ld    (hl),c
                inc   hl
                ld    (hl),b
                ret

; draw_all_icons: draw every icon body (no selection at startup).
draw_all_icons
                xor   a
dai_loop
                push  af
                call  load_icon
                call  draw_icon_full
                pop   af
                inc   a
                cp    NUM_ICONS
                jr    c,dai_loop
                ret

; draw_body: draw just the icon shape (in the box's top region, no label).
; Safe for the per-frame repair path (no text VDU).
; draw_body: blit the icon's bitmap (wbmp) into the box's shape region.
draw_body
                ld    hl,(wx)                 ; bm_x = (wx + SHAPE_INSET) / 8 bytes
                ld    de,SHAPE_INSET
                add   hl,de
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                ld    (bm_x),a
                ld    hl,(wy)                 ; bm_y = 159 - wy/2  (shape top line)
                srl   h
                rr    l
                ld    a,159
                sub   l
                ld    (bm_y),a
                ld    hl,(wbmp)
                ld    (bm_src),hl
                ld    a,BMP_W
                ld    (bm_w),a
                ld    a,BMP_H
                ld    (bm_h),a
                call  blit_bitmap
                ret

; draw_icon_full: body + label. Used only on events (startup, drop), never on
; the per-frame drag path.
draw_icon_full
                call  draw_body
                ld    a,1                     ; white label
                call  draw_label
                ret

; draw_label: A = text pen (PEN_DESKTOP erases). Print the current icon's label
; (wlabel) centred just below the icon at wx,wy, on the backdrop.
draw_label
                push  af
                ld    hl,(wlabel)            ; label length -> B
                ld    b,0
dl_len
                ld    a,(hl)
                or    a
                jr    z,dl_pos
                inc   hl
                inc   b
                jr    dl_len
dl_pos
                ld    hl,(wx)                ; centre column = (wx + ICON_W/2)/16
                ld    de,ICON_W/2
                add   hl,de
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l                    ; centre column (0-based)
                ld    c,a
                ld    a,b                    ; minus half the label length
                srl   a
                ld    b,a
                ld    a,c
                sub   b
                inc   a                       ; locate column is 1-based
                ld    (lcmd+1),a
                ld    hl,(wy)                ; row = ((199 - wy/2) / 8) + 1
                srl   h                       ; (the box's bottom text row)
                rr    l
                ld    a,199
                sub   l
                srl   a
                srl   a
                srl   a
                add   a,1
                ld    (lcmd+2),a
                pop   af
                call  TXT_SET_PEN
                ld    a,PEN_DESKTOP
                call  TXT_SET_PAPER
                ld    hl,lcmd                ; locate (31,col,row)
                call  print_str
                ld    hl,(wlabel)            ; then the label text
                call  print_str
                ret

; erase_body: fill the icon's bounding box with the backdrop pen.
erase_body
                call  set_body_rect
                ld    a,PEN_DESKTOP
                call  fill_rect
                ret

; draw_frame: A = pen. Box FRAME_G units outside the box at wx,wy.
draw_frame
                push  af
                call  set_frame_rect
                pop   af
                call  draw_box
                ret

; point_in_body: carry set if the cursor is within the box at wx,wy.
point_in_body
                ld    hl,(cursor_x)
                ld    de,(wx)
                call  cmp_hl_de
                jr    c,pib_no
                ld    hl,(wx)
                ld    de,ICON_W+1
                add   hl,de
                ex    de,hl
                ld    hl,(cursor_x)
                call  cmp_hl_de
                jr    nc,pib_no
                ld    hl,(cursor_y)
                ld    de,(wy)
                call  cmp_hl_de
                jr    c,pib_no
                ld    hl,(wy)
                ld    de,ICON_H+1
                add   hl,de
                ex    de,hl
                ld    hl,(cursor_y)
                call  cmp_hl_de
                jr    nc,pib_no
                scf
                ret
pib_no
                or    a
                ret

; hit_test_icons: A = index of the icon under the cursor + carry set; else A =
; NO_ICON and carry clear.
hit_test_icons
                xor   a
hti_loop
                push  af
                call  load_icon
                call  point_in_body
                jr    c,hti_found
                pop   af
                inc   a
                cp    NUM_ICONS
                jr    c,hti_loop
                ld    a,NO_ICON
                or    a                        ; clear carry
                ret
hti_found
                pop   af                       ; A = matching index
                scf
                ret

; ---------------------------------------------------------------------------
; repair_others: an erase just cleared the rectangle now in rx0..ry1. Redraw
; any icon whose box overlaps it (so overlapping icons aren't left notched),
; skipping the icon currently being dragged (it is meant to be transparent).
; Clobbers wx,wy,wshape and the rectangle params.
repair_others
                ld    hl,(rx0)
                ld    (dr_x0),hl
                ld    hl,(ry0)
                ld    (dr_y0),hl
                ld    hl,(rx1)
                ld    (dr_x1),hl
                ld    hl,(ry1)
                ld    (dr_y1),hl
                xor   a
                ld    (ro_i),a
rep_loop
                ld    a,(dragging)
                or    a
                jr    z,rep_chk
                ld    a,(ro_i)               ; while dragging, skip the dragged icon
                ld    b,a
                ld    a,(drag_idx)
                cp    b
                jr    z,rep_next
rep_chk
                ld    a,(ro_i)
                call  load_icon
                call  rects_overlap
                jr    nc,rep_next
                call  draw_body
rep_next
                ld    a,(ro_i)
                inc   a
                ld    (ro_i),a
                cp    NUM_ICONS
                jr    c,rep_loop
                ret

; snap16: round HL to the nearest multiple of 16 (8 px in Mode 1).
snap16
                ld    de,8
                add   hl,de
                ld    a,l
                and   #F0
                ld    l,a
                ret

; rects_overlap: carry set if the icon box at wx,wy overlaps the saved dirty
; rectangle dr_x0..dr_y1.
rects_overlap
                ld    hl,(dr_x1)             ; dirty right < icon left -> no
                ld    de,(wx)
                call  cmp_hl_de
                jr    c,ro_none
                ld    hl,(wx)                ; icon right < dirty left -> no
                ld    de,ICON_W
                add   hl,de
                ld    de,(dr_x0)
                call  cmp_hl_de
                jr    c,ro_none
                ld    hl,(dr_y1)
                ld    de,(wy)
                call  cmp_hl_de
                jr    c,ro_none
                ld    hl,(wy)
                ld    de,ICON_H
                add   hl,de
                ld    de,(dr_y0)
                call  cmp_hl_de
                jr    c,ro_none
                scf
                ret
ro_none
                or    a
                ret

; set_body_rect / set_shape_rect / set_frame_rect: rectangle params from wx,wy.
; body  = the full box (erase, hit-test, frame base)
; shape = the smaller shape region in the box's top portion
set_body_rect
                ld    hl,(wx)
                ld    (rx0),hl
                ld    hl,(wy)
                ld    (ry0),hl
                ld    hl,(wx)
                ld    de,ICON_W
                add   hl,de
                ld    (rx1),hl
                ld    hl,(wy)
                ld    de,ICON_H
                add   hl,de
                ld    (ry1),hl
                ret
set_shape_rect
                ld    hl,(wx)
                ld    de,SHAPE_INSET
                add   hl,de
                ld    (rx0),hl
                ld    hl,(wy)
                ld    de,LABEL_BAND
                add   hl,de
                ld    (ry0),hl
                ld    hl,(wx)
                ld    de,ICON_W-SHAPE_INSET
                add   hl,de
                ld    (rx1),hl
                ld    hl,(wy)
                ld    de,ICON_H
                add   hl,de
                ld    (ry1),hl
                ret
set_frame_rect
                ld    hl,(wx)
                ld    de,FRAME_G
                or    a
                sbc   hl,de
                ld    (rx0),hl
                ld    hl,(wy)
                ld    de,FRAME_G
                or    a
                sbc   hl,de
                ld    (ry0),hl
                ld    hl,(wx)
                ld    de,ICON_W+FRAME_G
                add   hl,de
                ld    (rx1),hl
                ld    hl,(wy)
                ld    de,ICON_H+FRAME_G
                add   hl,de
                ld    (ry1),hl
                ret

; ---------------------------------------------------------------------------
; Set up the four-pen desktop palette and a matching border.
set_palette
                ld    a,0
                ld    b,INK_DESKTOP
                ld    c,INK_DESKTOP
                call  SCR_SET_INK
                ld    a,1
                ld    b,INK_LIGHT
                ld    c,INK_LIGHT
                call  SCR_SET_INK
                ld    a,2
                ld    b,INK_DARK
                ld    c,INK_DARK
                call  SCR_SET_INK
                ld    a,3
                ld    b,INK_ACCENT
                ld    c,INK_ACCENT
                call  SCR_SET_INK
                ld    b,INK_DESKTOP
                ld    c,INK_DESKTOP
                call  SCR_SET_BORDER
                ret

; Full-width white title bar on row 0: black text on white paper.
draw_title_bar
                ld    a,2
                call  TXT_SET_PEN
                ld    a,1
                call  TXT_SET_PAPER
                ld    hl,title_text
                call  print_str
                ret

; Help line below the bar, white text on the blue backdrop.
draw_help
                ld    a,1
                call  TXT_SET_PEN
                ld    a,0
                call  TXT_SET_PAPER
                ld    hl,help_text
                call  print_str
                ret

; Print a zero-terminated string via TXT_OUTPUT (interprets CR/LF).
print_str
                ld    a,(hl)
                or    a
                ret   z
                call  TXT_OUTPUT
                inc   hl
                jr    print_str

; --- Desktop data --------------------------------------------------------
title_text      db    " GEOBENCH                               ",0
; Help on row 1, placed with the locate control (31, column, row; 1-based) so
; its position is independent of where the title left the cursor.
help_text       db    31,1,2,"  Hold Fire/Space to drag   ESC: quit",0

; --- Mutable state -------------------------------------------------------
spd             db    SPD_MIN
last_fire       db    0
dragging        db    0
sel_icon        db    NO_ICON      ; selected icon index, or NO_ICON
drag_idx        db    NO_ICON      ; icon currently being dragged
li_idx          db    0            ; load_icon scratch
wbmp            dw    0            ; working icon bitmap pointer
wlabel          dw    0            ; working icon label pointer
wx              dw    0            ; working icon position
wy              dw    0
lcmd            db    31,0,0,0     ; locate control buffer (31, col, row, 0)
drag_x          dw    0
drag_y          dw    0
grab_dx         dw    0
grab_dy         dw    0
nicon_x         dw    0
nicon_y         dw    0
tgt_x           dw    0
tgt_y           dw    0
ro_i            db    0            ; repair_others loop index
dr_x0           dw    0            ; repair_others dirty rectangle
dr_y0           dw    0
dr_x1           dw    0
dr_y1           dw    0

; --- Icon table (parallel arrays; positions on the 16-unit grid) ---------
icon_xs         dw    80, 256, 432
icon_ys         dw    144, 144, 144
icon_bmps       dw    icon_floppy, icon_clock, icon_trash
icon_labels     dw    label_disk, label_clock, label_trash
label_disk      db    "Disk",0
label_clock     db    "Clock",0
label_trash     db    "Trash",0

end
                save  "GEOBENCH.BIN",geobench,end-geobench,DSK,"build/geobench.dsk"
