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
                include "../lib/text.asm"
                include "../lib/window.asm"
; --- Icon set ------------------------------------------------------------
; An icon set (.IST) is a 16-byte header, a per-icon directory, then the icon
; bitmaps. Each icon carries its OWN size, so a set can mix sizes; the desktop
; reads an icon's size and lays out its box (compute_geometry) at draw time.
;   Header(16): "GBIS"(0-3) version=2(4) count(5) reserved(6-15)
;   Directory(count*4): per slot -> offset(2, from file start) width(1) height(1)
;   Bitmaps: each width*height bytes, in slot order.
; Each icon label is a SLOT INDEX; icon_addr looks up its offset, set_geom_slot
; its size. The whole .IST is loaded into icon_set as-is (no shifting). At
; startup icon_load validates it, else copies the compiled-in default set.
ICON_NSLOT      equ   9
IST_HDR         equ   16           ; header size
IST_DIR         equ   ICON_NSLOT*4 ; per-icon directory (offset,w,h)
IST_DATA        equ   IST_HDR + IST_DIR        ; bitmaps start here (52)
ROM_ICON_SZ     equ   256          ; the default set is all 32x32 (8 x 32 bytes)
ROMSET_SIZE     equ   IST_DATA + ICON_NSLOT*ROM_ICON_SZ   ; full default .IST = 2356
ICON_LOAD_MAX   equ   2560         ; cap on a set's on-disk size (floppy adds an
                                   ; AMSDOS header); also bounds the load buffer

icon_rom_data   incbin "../build/DEFAULT.IST"  ; compiled-in default set (full .IST)

icon_set        defs  ICON_LOAD_MAX+128        ; active set (RAM); the loaded .IST
icon_floppy     equ   0            ; icon labels are slot indices
icon_ide        equ   1
icon_clock      equ   2
icon_trash      equ   3
icon_geobench   equ   4
icon_basic      equ   5
icon_binary     equ   6
icon_picture    equ   7
icon_text       equ   8

; --- Font set ------------------------------------------------------------
; A font set (.FNT) is a 16-byte header then fixed-width glyph bitmaps (one
; byte per row, <= 8 px wide). It is loaded and selected like an icon set: the
; FONT= key in GEOBENCH.CFG names it; font_load reads <FONT>.FNT, validates it,
; and falls back to the compiled-in default. lib/text.asm reads the geometry
; (first/last char, width, height) from the header and renders pixel-accurately
; so a narrow font (the default is 6x8) blits at sub-byte positions; an 8x8 set
; (CLASSIC.FNT) renders byte-aligned exactly like the old fixed font.
;   Header(16): "GBFN"(0-3) version=1(4) first(5) last(6) width(7) height(8)
;               bytes-per-row(9) reserved(10-15)
;   Glyphs: (last-first+1) * height bytes, top `width` bits per row are pixels.
FONT_HDR        equ   16
FONT_NCH        equ   96           ; default ships chars 32..127
FONTSET_SIZE    equ   FONT_HDR + FONT_NCH*8     ; compiled-in default .FNT = 784
FONT_LOAD_MAX   equ   1024         ; cap on a font's on-disk size / load buffer

font_rom_data   incbin "../build/DEFAULT.FNT"  ; compiled-in default font (6x8)

font_set        defs  FONT_LOAD_MAX+128         ; active font (RAM)

                include "../lib/fs.asm"
                include "../lib/fs_ide_fat.asm"
                include "../lib/fs_amsdos.asm"
                include "../lib/config.asm"

; --- Palette (firmware ink numbers 0..26) --------------------------------
INK_DESKTOP     equ   1           ; blue        -> pen 0 (paper / backdrop)
INK_LIGHT       equ   26          ; bright white-> pen 1 (title bar, text)
INK_DARK        equ   0           ; black       -> pen 2 (pointer, outlines)
INK_ACCENT      equ   6           ; bright red  -> pen 3 (accents)

; --- Pointer movement / bounds (graphics coords: 0..639 x, 0..399 y) -----
; The pointer accelerates while a direction is held: it starts at SPD_MIN for
; precise taps and ramps by SPD_INC each frame up to SPD_MAX, resetting to
; SPD_MIN whenever no direction is held.
SPD_MIN         equ   1           ; step on the first frame (sub-pixel: fine)
SPD_INC         equ   1           ; added each held frame (gentle ramp = precise)
SPD_MAX         equ   8           ; top speed (4 px/frame in Mode 1)
DCLICK_FRAMES   equ   50          ; double-click window (frames; ~1s, forgiving for joystick)
PXMIN           equ   0            ; the bitmap cursor clamps its own sprite,
PXMAX           equ   639          ; so the hotspot may range the full screen
PYMIN           equ   0
PYMAX           equ   399

; --- Icons ---------------------------------------------------------------
; Icons live in a table of parallel arrays (icon_xs/icon_ys/icon_shapes).
; icon_x,icon_y is the lower-left of the WxH bounding box. Selection and the
; drag outline are a square frame FRAME_G units OUTSIDE the box, drawn in the
; plain backdrop margin so erasing them with the backdrop pen stays safe.
; The box, frame, hit-test and list rows are all derived at runtime from the
; active icon size (compute_geometry / box_w, box_h, ixmax_v, ...); only the
; margins below are constant. Largest icon is 8x32 bytes (the load buffer cap).
NUM_ICONS       equ   5            ; max icon slots (Floppy A/B + IDE + Clock + Trash)
FRAME_G         equ   4            ; selection/drag frame margin (2 px outside)
LABEL_BAND      equ   16           ; bottom band reserved for the label (8 px)
SHAPE_INSET     equ   8            ; icon bitmap inset from the box sides (4 px)
NO_ICON         equ   255
IXMIN           equ   FRAME_G
; Lower bound keeps the label (the box's bottom text row) on screen.
IYMIN           equ   16
PEN_DESKTOP     equ   0            ; backdrop (used to erase)
PEN_BODY        equ   1            ; white icon body
PEN_BORDER      equ   2            ; black square-icon border
PEN_SELECT      equ   3            ; accent selection / drag frame

; ---------------------------------------------------------------------------
desktop_start
                ld    a,1
                call  SCR_SET_MODE           ; Mode 1, 320x200, 4 pens. Clears.
                di                           ; probe RAM (pages &4000; IRQs off)
                call  mem_detect             ; A = number of 64K expansion banks
                ei
                ld    l,a                    ; total KB = 64 + banks*64
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl                   ; banks * 64
                ld    de,64
                add   hl,de                   ; + base 64K
                call  fmt_mem                 ; -> mem_str "<KB>K"
                call  clock_init             ; RTC? else software clock -> time_str
                call  fs_init                ; pick default backend (IDE? else floppy)
                call  cfg_load               ; read GEOBENCH.CFG -> cfg_* settings
                call  icon_load              ; load <ICONS>.IST over icon_set
                call  font_load              ; load <FONT>.FNT over font_set
                call  build_desktop_icons    ; probe drives -> live icon table
                call  TXT_CUR_DISABLE        ; no blinking text cursor blob
                call  TXT_CUR_OFF
                call  set_palette
                call  draw_title_bar
                call  draw_help
                call  draw_all_icons
                call  cursor_show            ; cursor last, so it stays on top

; --- Main loop -----------------------------------------------------------
mainloop
                call  MC_WAIT_FLYBACK        ; pace at 50 Hz, redraw in vblank
                call  input_poll             ; -> in_dirs, in_quit

                ld    a,(dclick_timer)       ; count down the double-click window
                or    a
                jr    z,ml_nodc
                dec   a
                ld    (dclick_timer),a
ml_nodc
                ld    a,(in_dirs)            ; effective movement directions -> B
                ld    b,a
                ld    a,(win_open)          ; with a window open (not dragging) the
                or    a                       ; keyboard up/down scroll its list, so
                jr    z,ml_dirs              ; the pointer takes vertical only from
                ld    a,(win_dragging)      ; the joystick/mouse
                or    a
                jr    nz,ml_dirs
                call  handle_scroll          ; keyboard up/down -> list scroll
                ld    a,(in_dirs)
                and   #0C                     ; keep left/right
                ld    c,a
                ld    a,(in_joy_dirs)        ; vertical from joystick/mouse only
                and   #03
                or    c
                ld    b,a
ml_dirs
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
                ld    a,(win_dragging)
                or    a
                jr    nz,ml_windrag
                ld    de,(tgt_x)             ; not dragging: just move the cursor
                ld    hl,(tgt_y)
                call  cursor_move_to
                jr    ml_fire
ml_drag
                call  drag_frame             ; dragging an icon
                jr    ml_fire
ml_windrag
                call  win_drag_frame         ; dragging a window
ml_fire
                call  handle_fire
                call  update_clock           ; tick the top-bar clock

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
                ld    hl,maxspd             ; cap at the current max (boosted in
                cp    (hl)                    ; a window drag)
                jr    c,us_store
                ld    a,(maxspd)
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
                ld    a,(dragging)            ; released: drop the dragged icon
                or    a
                jp    nz,drop_drag
                ld    a,(win_dragging)        ; or finish a window drag
                or    a
                ret   z
                xor   a
                ld    (win_dragging),a
                jp    win_drop
hf_down
                ld    a,c
                or    a
                ret   nz                      ; already held -> not a fresh press

                ld    a,(win_open)            ; window interactions (it's on top)
                or    a
                jr    z,hf_icons
                call  close_hit
                jr    nc,hf_titlecheck
                call  cursor_erase            ; close gadget -> close the window
                call  window_close
                jp    cursor_draw
hf_titlecheck
                call  title_hit               ; title bar -> start dragging it
                jr    nc,hf_icons
                jp    win_grab
hf_icons
                call  hit_test_icons          ; A = icon index, carry if hit
                jr    c,hf_grab
                jp    deselect_current        ; pressed empty space
hf_grab
                ld    b,a                     ; icon index under the pointer
                ld    a,(dclick_timer)        ; second click on the same icon soon
                or    a                        ; after the first = double-click
                jr    z,hf_firstclick
                ld    a,(dclick_idx)
                cp    b
                jr    nz,hf_firstclick
                ld    de,icon_first          ; drive icons carry a backend; others 0
                call  icon_word               ; B = idx -> HL = icon_first[idx]
                ld    a,h
                or    l
                jr    z,hf_firstclick         ; not a drive (Clock/Trash) -> ignore
                ld    (fs_p_first),hl          ; bind this drive's backend, then open
                ld    de,icon_next
                call  icon_word
                ld    (fs_p_next),hl
                ld    de,icon_labels          ; window title = the icon's label
                call  icon_word
                ld    (wnd_title),hl
                ld    a,b                      ; floppy drive unit (IDE ignores it)
                ld    l,a
                ld    h,0
                ld    de,icon_unit
                add   hl,de
                ld    a,(hl)
                ld    (fsam_unit),a
                jp    open_disk_window
hf_firstclick
                ld    a,b                     ; remember this click for double-click
                ld    (dclick_idx),a
                ld    a,DCLICK_FRAMES
                ld    (dclick_timer),a
                ld    a,b
                ld    (drag_idx),a            ; the icon under the pointer
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
                ld    a,(drag_idx)           ; frame/clamp use the dragged icon's size
                call  set_geom_for
                call  cursor_erase
                ld    hl,(drag_x)            ; erase the drag frame where it is
                ld    (wx),hl
                ld    hl,(drag_y)
                ld    (wy),hl
                ld    a,PEN_DESKTOP
                call  draw_frame
                call  repair_others           ; (still dragging -> skips this icon)
                ld    a,(drag_idx)           ; repair_others changed geometry; restore
                call  set_geom_for
                xor   a
                ld    (dragging),a

                ld    hl,(drag_x)            ; snap the dropped position to the grid
                call  snap16
                ld    de,IXMIN
                call  clamp_lo
                ld    de,(ixmax_v)
                call  clamp_hi
                ld    (wx),hl
                ld    hl,(drag_y)
                call  snap16
                ld    de,IYMIN
                call  clamp_lo
                ld    de,(iymax_v)
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
                ld    hl,n_icons             ; loop bound = active icon count
                cp    (hl)
                jr    c,ral_loop
                ret

; ---------------------------------------------------------------------------
; drag_frame: move the drag frame to follow the pointer (target - grab offset)
; and the cursor to its target, recompositing only if something moved.
drag_frame
                ld    a,(drag_idx)           ; clamp/frame use the dragged icon's size
                call  set_geom_for
                ld    hl,(tgt_x)             ; new frame x = tgt_x - grab_dx
                ld    de,(grab_dx)
                or    a
                sbc   hl,de
                jr    nc,df_xok
                ld    hl,0                    ; floor underflow
df_xok
                ld    de,IXMIN
                call  clamp_lo
                ld    de,(ixmax_v)
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
                ld    de,(iymax_v)
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
                ld    a,(drag_idx)           ; repair_others changed geometry; restore
                call  set_geom_for
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
                ld    a,(li_idx)             ; bitmap = slot index (word array)
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,icon_bmps
                add   hl,de
                ld    a,(hl)                  ; slot index
                push  af
                call  set_geom_slot          ; this icon's size + box geometry
                pop   af
                call  icon_addr               ; -> bitmap address
                ld    (wbmp),hl
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
                ld    hl,n_icons             ; loop bound = active icon count
                cp    (hl)
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
                ld    hl,(wy)                 ; bm_y = bm_y_base - wy/2  (icon top line)
                srl   h
                rr    l
                ld    a,(bm_y_base)
                sub   l
                ld    (bm_y),a
                ld    hl,(wbmp)
                ld    (bm_src),hl
                ld    a,(icon_w)
                ld    (bm_w),a
                ld    a,(icon_h)
                ld    (bm_h),a
                call  blit_bitmap
                ret

; draw_icon_full: body + label. Used at startup, on drop, and by repair_others
; (bitmap text is safe on the per-frame path).
draw_icon_full
                call  draw_body
                ld    a,1                     ; white label
                call  draw_label
                ret

; draw_label: A = text pen. Draw the current icon's label (wlabel) centred in
; the box's bottom band, using the bitmap font on the backdrop.
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
dl_pos                                         ; tc_x = (wx + box_w/2 - len*font_w)/8,
                ld    c,b                     ; centred on the box (graphics units: 2
                ld    hl,(wx)                ; per pixel). Subtract the half text width
                ld    de,(box_wh)            ; in graphics (= len*font_w) before /8.
                add   hl,de                  ; Labels wider than the box clamp to 0.
                ld    a,(font_w)
                ld    e,a
                ld    d,0
dl_subw
                ld    a,c
                or    a
                jr    z,dl_div
                or    a                       ; clear carry for sbc
                sbc   hl,de
                dec   c
                jr    dl_subw
dl_div
                bit   7,h                     ; negative -> clamp to left edge
                jr    nz,dl_zero
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                jr    dl_storex
dl_zero
                xor   a
dl_storex
                ld    (tc_x),a
                ld    hl,(wy)                ; tc_y = 192 - wy/2 (box bottom 8px)
                srl   h
                rr    l
                ld    a,192
                sub   l
                ld    (tc_y),a
                pop   af                      ; pen
                ld    b,a
                ld    c,PEN_DESKTOP
                call  set_text_pens
                ld    hl,(wlabel)
                jp    draw_text

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
                ld    de,(box_w1)
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
                ld    de,(box_h1)
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
                ld    hl,n_icons             ; loop bound = active icon count
                cp    (hl)
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
                call  draw_icon_full          ; body + label (bitmap text, safe)
rep_next
                ld    a,(ro_i)
                inc   a
                ld    (ro_i),a
                ld    hl,n_icons             ; loop bound = active icon count
                cp    (hl)
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
                ld    de,(box_w)
                add   hl,de
                ld    de,(dr_x0)
                call  cmp_hl_de
                jr    c,ro_none
                ld    hl,(dr_y1)
                ld    de,(wy)
                call  cmp_hl_de
                jr    c,ro_none
                ld    hl,(wy)
                ld    de,(box_h)
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
                ld    de,(box_w)
                add   hl,de
                ld    (rx1),hl
                ld    hl,(wy)
                ld    de,(box_h)
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
                ld    de,(box_wsi)
                add   hl,de
                ld    (rx1),hl
                ld    hl,(wy)
                ld    de,(box_h)
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
                ld    de,(box_wfg)
                add   hl,de
                ld    (rx1),hl
                ld    hl,(wy)
                ld    de,(box_hfg)
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

; Full-width white title bar on the top 8 lines: black bitmap text on white.
draw_title_bar
                xor   a                       ; white bar (fast direct fill)
                ld    (fb_x),a
                ld    (fb_y),a
                ld    a,80
                ld    (fb_w),a
                ld    a,8
                ld    (fb_h),a
                ld    a,#F0                   ; white
                ld    (fb_val),a
                call  fill_block
                ld    b,2                     ; black on white
                ld    c,1
                call  set_text_pens
                ld    a,1                     ; total RAM on the left
                ld    (tc_x),a
                xor   a
                ld    (tc_y),a
                ld    hl,mem_str
                call  draw_text
                jp    draw_clock              ; time on the right

; fmt_mem: HL = total KB -> mem_str as "<decimal>K" (leading zeros suppressed).
fmt_mem
                ld    ix,mem_str
                xor   a
                ld    (fm_lead),a
                ld    de,10000
                call  fm_digit
                ld    de,1000
                call  fm_digit
                ld    de,100
                call  fm_digit
                ld    de,10
                call  fm_digit
                ld    a,l                     ; units digit (always shown)
                add   a,'0'
                ld    (ix+0),a
                ld    (ix+1),'K'
                ld    (ix+2),0
                ret
fm_digit                                       ; HL/DE -> digit in A, HL=remainder
                ld    a,#FF
fmd_loop
                inc   a
                or    a                        ; clear carry
                sbc   hl,de
                jr    nc,fmd_loop
                add   hl,de                    ; undo the overshoot
                or    a
                jr    nz,fmd_emit
                ld    a,(fm_lead)              ; leading zero -> skip
                or    a
                ret   z
                xor   a
fmd_emit
                ld    b,a
                ld    a,1
                ld    (fm_lead),a
                ld    a,b
                add   a,'0'
                ld    (ix+0),a
                inc   ix
                ret

; ===========================================================================
; Clock (top-bar, right side). Uses the Dallas RTC (&FD14 addr / &FD15 data)
; if one is present, otherwise a software clock counting 50Hz frames from boot.
; ===========================================================================

CLK_COL         equ   68           ; byte column of "HH:MM" (right of the 80-byte bar)
TICKS_PER_SEC   equ   50

; Dallas RTC on the SymbiFace II / Cyboard: &FD15 = address, &FD14 = data.
RTC_ADDR        equ   #FD15
RTC_DATA        equ   #FD14

; clock_init: detect the RTC, zero the software clock, prime the display string.
clock_init
                xor   a
                ld    (sw_sec),a
                ld    (sw_min),a
                ld    (sw_hour),a
                ld    (clk_frames),a
                call  rtc_detect
                call  read_time              ; -> time_str
                ld    hl,time_str            ; clk_shown = time_str
                ld    de,clk_shown
                ld    bc,6
                ldir
                ret

; rtc_detect: write/read-back NVRAM reg 0x0E twice. have_rtc = 1 if present.
rtc_detect
                ld    e,#5A
                call  rtc_nvram_rw            ; write 5A, read back -> A
                cp    #5A
                jr    nz,rd_none
                ld    e,#A5
                call  rtc_nvram_rw            ; confirm with a second value
                cp    #A5
                jr    nz,rd_none
                ld    a,1
                ld    (have_rtc),a
                ret
rd_none
                xor   a
                ld    (have_rtc),a
                ret

; rtc_nvram_rw: E = value to write to NVRAM reg 0x0E -> A = value read back.
rtc_nvram_rw
                ld    a,#0E
                ld    bc,RTC_ADDR
                out   (c),a                   ; select reg 0x0E
                ld    bc,RTC_DATA
                out   (c),e                   ; write the value
                ld    a,#0E
                ld    bc,RTC_ADDR
                out   (c),a                   ; reselect 0x0E
                ld    bc,RTC_DATA
                in    a,(c)                   ; read it back
                ret

; read_rtc_reg: A = register -> A = value.
read_rtc_reg
                ld    bc,RTC_ADDR
                out   (c),a
                ld    bc,RTC_DATA
                in    a,(c)
                ret

; read_time: fill time_str with "HH:MM" from the RTC or the software clock.
read_time
                ld    a,(have_rtc)
                or    a
                jr    z,rt_soft
                ld    a,#04
                call  read_rtc_reg            ; hours (BCD)
                ld    (rt_h),a
                ld    a,#02
                call  read_rtc_reg            ; minutes (BCD)
                ld    (rt_m),a
                jr    rt_fmt
rt_soft
                ld    a,(sw_hour)
                call  bin_to_bcd
                ld    (rt_h),a
                ld    a,(sw_min)
                call  bin_to_bcd
                ld    (rt_m),a
rt_fmt
                ld    de,time_str
                ld    a,(rt_h)
                call  put_bcd2
                ld    a,':'
                ld    (de),a
                inc   de
                ld    a,(rt_m)
                call  put_bcd2
                xor   a
                ld    (de),a
                ret

; put_bcd2: A = BCD byte -> two ASCII digits at (DE), DE advanced.
put_bcd2
                push  af
                rrca
                rrca
                rrca
                rrca
                and   #0F
                add   a,'0'
                ld    (de),a
                inc   de
                pop   af
                and   #0F
                add   a,'0'
                ld    (de),a
                inc   de
                ret

; bin_to_bcd: A (0..99) -> packed BCD.
bin_to_bcd
                ld    b,#FF
btb_loop
                inc   b
                sub   10
                jr    nc,btb_loop
                add   a,10                    ; A = units, B = tens
                ld    c,a
                ld    a,b
                rlca
                rlca
                rlca
                rlca
                or    c
                ret

; sw_tick: advance the software clock by one second.
sw_tick
                ld    a,(sw_sec)
                inc   a
                cp    60
                jr    c,swt_sec
                xor   a
                ld    (sw_sec),a
                ld    a,(sw_min)
                inc   a
                cp    60
                jr    c,swt_min
                xor   a
                ld    (sw_min),a
                ld    a,(sw_hour)
                inc   a
                cp    24
                jr    c,swt_hour
                xor   a
swt_hour
                ld    (sw_hour),a
                ret
swt_min
                ld    (sw_min),a
                ret
swt_sec
                ld    (sw_sec),a
                ret

; update_clock: once per frame. Every 50 frames = 1s, refresh the time; redraw
; the top-bar clock only when "HH:MM" actually changes.
update_clock
                ld    a,(clk_frames)
                inc   a
                cp    TICKS_PER_SEC
                jr    c,uc_save
                xor   a
                ld    (clk_frames),a
                ld    a,(have_rtc)            ; software clock advances itself
                or    a
                call  z,sw_tick
                call  read_time              ; -> time_str
                call  clk_changed            ; differs from clk_shown?
                ret   z
                ld    hl,time_str            ; remember + redraw
                ld    de,clk_shown
                ld    bc,6
                ldir
                call  cursor_erase
                call  draw_clock
                jp    cursor_draw
uc_save
                ld    (clk_frames),a
                ret

; clk_changed: Z if time_str == clk_shown (5 chars), NZ if different.
clk_changed
                ld    hl,time_str
                ld    de,clk_shown
                ld    b,5
ckc_loop
                ld    a,(de)
                cp    (hl)
                ret   nz                      ; differ -> NZ
                inc   hl
                inc   de
                djnz  ckc_loop
                xor   a                        ; equal -> Z
                ret

; draw_clock: draw time_str at the top-right of the (white) title bar.
draw_clock
                ld    b,2                     ; black on white
                ld    c,1
                call  set_text_pens
                ld    a,CLK_COL
                ld    (tc_x),a
                xor   a
                ld    (tc_y),a
                ld    hl,time_str
                jp    draw_text

; Help line on screen line 9, white bitmap text on the blue backdrop.
draw_help
                ld    b,1                     ; white on blue
                ld    c,0
                call  set_text_pens
                ld    a,1
                ld    (tc_x),a
                ld    a,9
                ld    (tc_y),a
                ld    hl,help_text
                jp    draw_text

; icon_word: read a word from a parallel icon array. DE = array base, B = icon
; index -> HL = array[B]. Preserves B/C; clobbers A, DE, HL.
icon_word
                ld    a,b
                add   a,a                     ; idx * 2 (index < NUM_ICONS)
                ld    l,a
                ld    h,0
                add   hl,de                   ; HL -> array[idx]
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                ret

; icon_load: load the icon set named by cfg_icons (e.g. "DEFAULT" -> DEFAULT.IST)
; into icon_set, validating its header (magic, count, size <= 8x32). On any
; failure the compiled-in default set (icon_rom, 32x32) is used. Either way
; compute_geometry then derives the whole layout from the active icon size. Call
; after cfg_load, before drawing icons.
icon_load
                ld    hl,ICON_LOAD_MAX        ; never load more than the buffer holds
                ld    (fs_load_max),hl

                ld    hl,cfg_icons           ; fs_req_name = cfg_icons.IST (8.3)
                ld    de,fs_req_name
                ld    b,8
il_name
                ld    a,(hl)
                or    a
                jr    z,il_pad               ; cfg_icons ended -> space-pad
                ld    (de),a
                inc   hl
                inc   de
                djnz  il_name
                jr    il_ext
il_pad
                ld    a,' '
il_padloop
                ld    (de),a
                inc   de
                djnz  il_padloop
il_ext
                ld    a,'I'
                ld    (de),a
                inc   de
                ld    a,'S'
                ld    (de),a
                inc   de
                ld    a,'T'
                ld    (de),a
                ld    hl,icon_set
                ld    (fs_load_dst),hl
                call  fs_load_file
                jr    nc,il_default          ; missing / too big -> default

                ld    a,(icon_set+0)         ; magic "GBIS"
                cp    'G'
                jr    nz,il_default
                ld    a,(icon_set+1)
                cp    'B'
                jr    nz,il_default
                ld    a,(icon_set+2)
                cp    'I'
                jr    nz,il_default
                ld    a,(icon_set+3)
                cp    'S'
                jr    nz,il_default
                ld    a,(icon_set+4)         ; version == 2
                cp    2
                jr    nz,il_default
                ld    a,(icon_set+5)         ; count == 9
                cp    ICON_NSLOT
                jr    nz,il_default

                ld    ix,icon_set+IST_HDR    ; walk the directory: each w<=8, h<=32,
                ld    hl,0                    ; summing w*h for the size check
                ld    (il_sum),hl
                ld    a,ICON_NSLOT
                ld    (il_cnt),a
il_dloop
                ld    a,(ix+2)               ; width 1..8 bytes
                or    a
                jp    z,il_default
                cp    9
                jp    nc,il_default
                ld    c,a
                ld    a,(ix+3)               ; height 1..32 rows
                or    a
                jp    z,il_default
                cp    33
                jp    nc,il_default
                ld    b,a                     ; il_sum += w*h
                ld    d,0
                ld    e,c
                ld    hl,(il_sum)
il_mul          add   hl,de
                djnz  il_mul
                ld    (il_sum),hl
                ld    de,4
                add   ix,de
                ld    a,(il_cnt)
                dec   a
                ld    (il_cnt),a
                jr    nz,il_dloop

                ld    hl,(il_sum)           ; size == IST_DATA + sum(w*h)
                ld    de,IST_DATA
                add   hl,de
                ex    de,hl
                ld    hl,(fs_ent_size)
                or    a
                sbc   hl,de
                jp    nz,il_default
                ret                          ; valid: icon_set holds the set
il_default
                ld    hl,icon_rom_data       ; bad/missing -> compiled-in default set
                ld    de,icon_set
                ld    bc,ROMSET_SIZE
                ldir
                ret

; font_load: load the font set named by cfg_font (e.g. "DEFAULT" -> DEFAULT.FNT)
; into font_set, validating its header (magic, version, geometry). On any
; failure the compiled-in default font is used. Either way font_apply_header
; then caches the geometry for lib/text.asm. Call after cfg_load, before any
; text is drawn.
font_load
                ld    hl,FONT_LOAD_MAX        ; never load more than the buffer holds
                ld    (fs_load_max),hl

                ld    hl,cfg_font            ; fs_req_name = cfg_font.FNT (8.3)
                ld    de,fs_req_name
                ld    b,8
fl_name
                ld    a,(hl)
                or    a
                jr    z,fl_pad               ; cfg_font ended -> space-pad
                ld    (de),a
                inc   hl
                inc   de
                djnz  fl_name
                jr    fl_ext
fl_pad
                ld    a,' '
fl_padloop
                ld    (de),a
                inc   de
                djnz  fl_padloop
fl_ext
                ld    a,'F'
                ld    (de),a
                inc   de
                ld    a,'N'
                ld    (de),a
                inc   de
                ld    a,'T'
                ld    (de),a
                ld    hl,font_set
                ld    (fs_load_dst),hl
                call  fs_load_file
                jr    nc,fl_default          ; missing / too big -> default

                ld    a,(font_set+0)         ; magic "GBFN"
                cp    'G'
                jr    nz,fl_default
                ld    a,(font_set+1)
                cp    'B'
                jr    nz,fl_default
                ld    a,(font_set+2)
                cp    'F'
                jr    nz,fl_default
                ld    a,(font_set+3)
                cp    'N'
                jr    nz,fl_default
                ld    a,(font_set+4)         ; version == 1
                cp    1
                jr    nz,fl_default
                ld    a,(font_set+9)         ; bytes per row == 1 (width <= 8)
                cp    1
                jr    nz,fl_default

                ld    a,(font_set+7)         ; width 1..8 pixels
                or    a
                jr    z,fl_default
                cp    9
                jr    nc,fl_default
                ld    a,(font_set+8)         ; height 1..16 rows
                or    a
                jr    z,fl_default
                cp    17
                jr    nc,fl_default

                ld    a,(font_set+5)         ; first <= last
                ld    b,a
                ld    a,(font_set+6)
                cp    b
                jr    c,fl_default           ; last < first -> bad
                sub   b
                inc   a                        ; A = count = last - first + 1
                ld    e,a                      ; size == 16 + count*height
                ld    d,0
                ld    a,(font_set+8)
                ld    b,a
                ld    hl,0
fl_mul          add   hl,de
                djnz  fl_mul
                ld    de,FONT_HDR
                add   hl,de
                ex    de,hl
                ld    hl,(fs_ent_size)
                or    a
                sbc   hl,de
                jr    nz,fl_default
                ld    hl,font_set            ; valid -> cache geometry
                call  font_apply_header
                ret
fl_default
                ld    hl,font_rom_data       ; bad/missing -> compiled-in default font
                ld    de,font_set
                ld    bc,FONTSET_SIZE
                ldir
                ld    hl,font_set
                call  font_apply_header
                ret

; icon_addr: A = slot index -> HL = its bitmap (icon_set + dir[slot].offset).
icon_addr
                add   a,a
                add   a,a                     ; slot * 4
                ld    e,a
                ld    d,0
                ld    hl,icon_set+IST_HDR
                add   hl,de                   ; -> directory entry
                ld    a,(hl)                  ; offset (word)
                ld    c,a
                inc   hl
                ld    b,(hl)
                ld    hl,icon_set
                add   hl,bc
                ret

; set_geom_slot: A = slot index -> set icon_w/icon_h from dir[slot] and derive
; the box geometry. Call before drawing/measuring that icon.
set_geom_slot
                add   a,a
                add   a,a                     ; slot * 4
                ld    e,a
                ld    d,0
                ld    hl,icon_set+IST_HDR
                add   hl,de
                inc   hl
                inc   hl                       ; -> width
                ld    a,(hl)
                ld    (icon_w),a
                inc   hl
                ld    a,(hl)                   ; -> height
                ld    (icon_h),a
                jp    compute_geometry

; set_geom_for: A = icon index (live table) -> geometry of its slot's icon.
set_geom_for
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,icon_bmps
                add   hl,de
                ld    a,(hl)                  ; slot index
                jp    set_geom_slot

; compute_geometry: from icon_w/icon_h derive icon_bytes and the box layout.
; All values are in graphics units (8 per byte across, 2 per row down) except
; bm_y_base/list_* which are in lines/rows.
compute_geometry
                ld    a,(icon_w)            ; icon_bytes = icon_w * icon_h
                ld    e,a
                ld    d,0
                ld    a,(icon_h)
                ld    b,a
                ld    hl,0
cg_bytes        add   hl,de
                djnz  cg_bytes
                ld    (icon_bytes),hl

                ld    a,(icon_w)            ; box_w = icon_w*8 + 2*SHAPE_INSET
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    de,2*SHAPE_INSET
                add   hl,de
                ld    (box_w),hl

                ld    a,(icon_h)            ; box_h = icon_h*2 + LABEL_BAND
                ld    l,a
                ld    h,0
                add   hl,hl
                ld    de,LABEL_BAND
                add   hl,de
                ld    (box_h),hl

                ld    hl,(box_w)            ; box_w1 = box_w + 1
                inc   hl
                ld    (box_w1),hl
                ld    hl,(box_h)            ; box_h1 = box_h + 1
                inc   hl
                ld    (box_h1),hl
                ld    hl,(box_w)            ; box_wsi = box_w - SHAPE_INSET
                ld    de,SHAPE_INSET
                or    a
                sbc   hl,de
                ld    (box_wsi),hl
                ld    hl,(box_w)            ; box_wfg = box_w + FRAME_G
                ld    de,FRAME_G
                add   hl,de
                ld    (box_wfg),hl
                ld    hl,(box_h)            ; box_hfg = box_h + FRAME_G
                ld    de,FRAME_G
                add   hl,de
                ld    (box_hfg),hl
                ld    hl,(box_w)            ; box_wh = box_w / 2
                srl   h
                rr    l
                ld    (box_wh),hl

                ld    hl,(box_h)            ; bm_y_base = 199 - box_h/2
                srl   h
                rr    l
                ld    a,199
                sub   l
                ld    (bm_y_base),a

                ld    hl,639               ; ixmax_v = 639 - box_w - FRAME_G
                ld    de,(box_w)
                or    a
                sbc   hl,de
                ld    de,FRAME_G
                or    a
                sbc   hl,de
                ld    (ixmax_v),hl
                ld    hl,366               ; iymax_v = 366 - box_h - FRAME_G
                ld    de,(box_h)
                or    a
                sbc   hl,de
                ld    de,FRAME_G
                or    a
                sbc   hl,de
                ld    (iymax_v),hl

                ld    a,(icon_h)            ; list_bmh = icon_h / 2 (half-height row)
                srl   a
                ld    (list_bmh),a
                ld    a,(icon_h)            ; list_off = (icon_h/4) * icon_w
                srl   a
                srl   a
                ld    e,a
                ld    d,0
                ld    a,(icon_w)
                ld    b,a
                ld    hl,0
cg_loff         add   hl,de
                djnz  cg_loff
                ld    (list_off),hl
                ret

; build_desktop_icons: probe storage and fill the live icon arrays from
; cand_tbl. Present drives stack down the left column (y from 258, step -108);
; Clock/Trash keep their fixed candidate positions. Sets n_icons.
build_desktop_icons
                xor   a
                ld    (n_icons),a
                ld    hl,258                 ; top of the left-hand drive column
                ld    (bdi_lefty),hl
                ld    ix,cand_tbl
                ld    b,CAND_COUNT
bdi_loop
                push  bc
                ld    a,(ix+13)              ; kind: 0 always, 1 floppy, 2 IDE
                or    a
                jr    z,bdi_add
                cp    2
                jr    z,bdi_ide
                ld    a,(ix+12)             ; floppy: probe drive 'unit' for a disk
                ld    (fsam_unit),a
                call  fsam_present
                jr    nc,bdi_skip
                jr    bdi_add
bdi_ide
                call  fs_ide_present
                jr    nc,bdi_skip
bdi_add
                call  add_live_icon
bdi_skip
                pop   bc
                ld    de,CAND_SIZE
                add   ix,de
                djnz  bdi_loop
                ret

; add_live_icon: append candidate (IX) to the live arrays at slot n_icons. A
; drive (icon_first != 0) lands in the left column; others use their own x,y.
add_live_icon
                ld    a,(ix+8)              ; drive? (first != 0)
                or    (ix+9)
                jr    z,ali_sys
                ld    de,icon_xs            ; drive: left column
                ld    hl,8
                call  bdi_store_w
                ld    de,icon_ys
                ld    hl,(bdi_lefty)
                call  bdi_store_w
                ld    hl,(bdi_lefty)        ; step the column down for the next
                ld    de,108
                or    a
                sbc   hl,de
                ld    (bdi_lefty),hl
                jr    ali_rest
ali_sys
                ld    de,icon_xs           ; system icon: fixed candidate position
                ld    l,(ix+0)
                ld    h,(ix+1)
                call  bdi_store_w
                ld    de,icon_ys
                ld    l,(ix+2)
                ld    h,(ix+3)
                call  bdi_store_w
ali_rest
                ld    de,icon_bmps
                ld    l,(ix+4)
                ld    h,(ix+5)
                call  bdi_store_w
                ld    de,icon_labels
                ld    l,(ix+6)
                ld    h,(ix+7)
                call  bdi_store_w
                ld    de,icon_first
                ld    l,(ix+8)
                ld    h,(ix+9)
                call  bdi_store_w
                ld    de,icon_next
                ld    l,(ix+10)
                ld    h,(ix+11)
                call  bdi_store_w
                ld    a,(ix+12)            ; unit (byte array)
                ld    de,icon_unit
                call  bdi_store_b
                ld    a,(n_icons)          ; commit the slot
                inc   a
                ld    (n_icons),a
                ret

; bdi_store_w: store HL into (DE)[n_icons] (word array). Clobbers A,BC,DE,HL.
bdi_store_w
                ld    a,(n_icons)
                add   a,a
                ld    c,a
                ld    b,0
                ex    de,hl                  ; HL = array base, DE = value
                add   hl,bc
                ld    (hl),e
                inc   hl
                ld    (hl),d
                ret
; bdi_store_b: store A into (DE)[n_icons] (byte array). Clobbers BC,HL.
bdi_store_b
                ld    c,a
                ld    a,(n_icons)
                ld    l,a
                ld    h,0
                add   hl,de
                ld    (hl),c
                ret

; open_disk_window: open the Disk window on the currently-bound backend
; (fs_p_first/next and wnd_title set by the caller), read the directory and show
; its files as a scrolling list.
open_disk_window
                ld    a,(win_open)            ; already open? leave it
                or    a
                ret   nz
                call  deselect_current        ; clear the icon's selection frame
                ld    a,(win_placed)         ; first open: initial position;
                or    a                        ; later: reopen where it was left
                jr    nz,ofw_placed
                ld    a,4
                ld    (wnd_x),a
                ld    a,26
                ld    (wnd_y),a
                ld    a,1
                ld    (win_placed),a
ofw_placed
                ld    a,52
                ld    (wnd_w),a
                ld    a,112
                ld    (wnd_h),a
                ld    a,#F0                   ; white (the pattern overwrites it)
                ld    (wnd_content),a
                call  cursor_erase
                call  window_open
                call  fs_load_dir            ; read the real directory off disc
                xor   a
                ld    (disk_scroll),a
                call  draw_floppy_content
                jp    cursor_draw

; draw_floppy_content: checkerboard the interior, then draw the file list.
; Redrawn after every window_open (open and on drop).
draw_floppy_content
                ld    a,(wnd_x)              ; checkerboard the content area
                inc   a
                ld    (fb_x),a
                ld    a,(wnd_y)
                add   a,14                    ; below the title bar
                ld    (fb_y),a
                ld    a,(wnd_w)
                sub   2
                ld    (fb_w),a
                ld    a,(wnd_h)
                sub   15
                ld    (fb_h),a
                ld    a,#00                   ; solid blue interior (pen 0)
                ld    (fb_val),a
                call  fill_block
                jp    draw_disk_list

; redraw_list: repaint just the interior (after a scroll), keeping the cursor.
redraw_list
                call  cursor_erase
                call  draw_floppy_content
                jp    cursor_draw

; handle_scroll: keyboard up/down scroll the list by one entry, rate-limited so
; a held key steps smoothly. Clamps to [0, count-DISK_VISIBLE].
SCROLL_DELAY    equ   6
handle_scroll
                ld    a,(scroll_timer)
                or    a
                jr    z,hsc_ready
                dec   a
                ld    (scroll_timer),a
                ret
hsc_ready
                ld    a,(in_kbd_dirs)
                bit   0,a                       ; DIR_UP
                jr    nz,hsc_up
                bit   1,a                       ; DIR_DOWN
                jr    nz,hsc_down
                ret
hsc_up
                ld    a,(disk_scroll)
                or    a
                ret   z                         ; already at the top
                dec   a
                ld    (disk_scroll),a
                jr    hsc_apply
hsc_down
                ld    a,(disk_count)
                cp    DISK_VISIBLE+1
                ret   c                         ; everything already fits
                sub   DISK_VISIBLE              ; A = max scroll offset
                ld    b,a
                ld    a,(disk_scroll)
                cp    b
                ret   nc                        ; already at the bottom
                inc   a
                ld    (disk_scroll),a
hsc_apply
                ld    a,SCROLL_DELAY
                ld    (scroll_timer),a
                jp    redraw_list

; --- File list -----------------------------------------------------------
MAX_ENTRIES     equ   64           ; directory entries kept in RAM
DISK_VISIBLE    equ   5            ; list rows shown at once
DISK_ROW_TOP    equ   16           ; first row, lines below the window top
DISK_ROW_H      equ   18           ; row pitch (16px icon + 2px gap)

; fs_load_dir: enumerate the backend directory into disk_entries[] (11-byte
; name + 1 attr per entry) and record disk_count.
fs_load_dir
                ld    hl,disk_entries
                ld    (fld_dst),hl
                xor   a                         ; count kept in memory: fs_dir_next
                ld    (disk_count),a            ; clobbers BC, so C can't hold it
                call  fs_dir_first
                jr    nc,fld_done
fld_loop
                ld    de,(fld_dst)
                ld    hl,fs_ent_name
                ld    bc,11
                ldir
                ld    a,(fs_ent_attr)
                ld    (de),a
                inc   de
                ld    (fld_dst),de
                ld    a,(disk_count)
                inc   a
                ld    (disk_count),a
                cp    MAX_ENTRIES
                jr    nc,fld_done
                call  fs_dir_next
                jr    c,fld_loop
fld_done
                ret

; draw_disk_list: draw the DISK_VISIBLE rows starting at disk_scroll, each as a
; half-height type icon plus the file name.
draw_disk_list
                xor   a
                ld    (df_i),a
ddl_loop
                ld    a,(disk_scroll)         ; entry index = disk_scroll + row
                ld    b,a
                ld    a,(df_i)
                add   a,b
                ld    c,a
                ld    a,(disk_count)
                cp    c
                ret   z                        ; ran past the last entry
                ret   c

                ld    a,c                      ; entry ptr = disk_entries + idx*12
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                ld    d,h
                ld    e,l                       ; DE = idx*4
                add   hl,hl                      ; HL = idx*8
                add   hl,de                      ; HL = idx*12
                ld    de,disk_entries
                add   hl,de
                ld    de,fs_ent_name           ; stage into the entry fields
                push  bc
                ld    bc,12
                ldir
                pop   bc

                ld    a,(df_i)                  ; row y = wnd_y + ROW_TOP + i*18
                add   a,a                       ; i*2
                ld    b,a
                add   a,a                       ; i*4
                add   a,a                       ; i*8
                add   a,a                       ; i*16
                add   a,b                       ; i*16 + i*2 = i*18
                ld    b,a
                ld    a,(wnd_y)
                add   a,DISK_ROW_TOP
                add   a,b
                ld    (df_yb),a

                call  ext_to_icon              ; HL = slot index
                ld    a,l
                push  af
                call  set_geom_slot          ; this icon's size (list_off/list_bmh)
                pop   af
                call  icon_addr               ; -> bitmap address
                ld    de,(list_off)           ; middle rows (half height)
                add   hl,de
                ld    (bm_src),hl
                ld    a,(wnd_x)
                add   a,2
                ld    (bm_x),a
                ld    a,(df_yb)
                ld    (bm_y),a
                ld    a,(icon_w)
                ld    (bm_w),a
                ld    a,(list_bmh)
                ld    (bm_h),a
                call  blit_bitmap

                call  build_label              ; df_label = "NAME.EXT"
                ld    a,(wnd_x)
                add   a,11
                ld    (tc_x),a
                ld    a,(df_yb)
                add   a,4
                ld    (tc_y),a
                ld    b,1                       ; white text on blue
                ld    c,0
                call  set_text_pens
                ld    hl,df_label
                call  draw_text

                ld    a,(df_i)
                inc   a
                ld    (df_i),a
                cp    DISK_VISIBLE
                jp    c,ddl_loop
                ret

; ext_to_icon: HL -> the file-type icon for fs_ent_name's 3-char extension.
ext_to_icon
                ld    hl,name_geobench        ; GEOBENCH program -> its own icon
                call  cmp_name8
                jr    z,eti_geo
                ld    hl,ext_bas
                call  cmp_ext
                jr    z,eti_bas
                ld    hl,ext_bin
                call  cmp_ext
                jr    z,eti_bin
                ld    hl,ext_scr
                call  cmp_ext
                jr    z,eti_scr
                ld    hl,ext_txt
                call  cmp_ext
                jr    z,eti_txt
                ld    hl,icon_binary         ; default: generic binary
                ret
eti_bas         ld    hl,icon_basic
                ret
eti_bin         ld    hl,icon_binary
                ret
eti_scr         ld    hl,icon_picture
                ret
eti_txt         ld    hl,icon_text
                ret
eti_geo         ld    hl,icon_geobench
                ret

; cmp_name8: Z if the 8-char name template at HL equals fs_ent_name (8.3 name).
cmp_name8
                ld    de,fs_ent_name
                ld    b,8
cn8_loop
                ld    a,(de)
                cp    (hl)
                ret   nz
                inc   hl
                inc   de
                djnz  cn8_loop
                xor   a                        ; all matched -> Z
                ret
name_geobench   db    "GEOBENCH"

; cmp_ext: compare the 3-char template at HL with fs_ent_name+8. Z if equal.
cmp_ext
                ld    de,fs_ent_name+8
                ld    a,(de)
                cp    (hl)
                ret   nz
                inc   hl
                inc   de
                ld    a,(de)
                cp    (hl)
                ret   nz
                inc   hl
                inc   de
                ld    a,(de)
                cp    (hl)
                ret

; build_label: render fs_ent_name into df_label as "NAME.EXT" (trailing pad
; spaces dropped, the ".EXT" omitted when the extension is blank), null-term.
build_label
                ld    de,df_label
                ld    hl,fs_ent_name
                ld    b,8
blab_name
                ld    a,(hl)
                cp    ' '
                jr    z,blab_ext
                ld    (de),a
                inc   de
                inc   hl
                djnz  blab_name
blab_ext
                ld    hl,fs_ent_name+8
                ld    a,(hl)
                cp    ' '
                jr    z,blab_end              ; no extension
                ld    a,'.'
                ld    (de),a
                inc   de
                ld    b,3
blab_xloop
                ld    a,(hl)
                cp    ' '
                jr    z,blab_end
                ld    (de),a
                inc   de
                inc   hl
                djnz  blab_xloop
blab_end
                xor   a
                ld    (de),a
                ret

ext_bas         db    "BAS"
ext_bin         db    "BIN"
ext_scr         db    "SCR"
ext_txt         db    "TXT"
df_label        defs  13
fld_dst         dw    0            ; fs_load_dir write pointer
disk_count      db    0            ; entries read into disk_entries
disk_scroll     db    0            ; index of the top visible row
scroll_timer    db    0            ; frames until the next held-key scroll step
disk_entries    defs  MAX_ENTRIES*12

; ---------------------------------------------------------------------------
; win_grab: begin dragging. The window goes transparent (its filled body is
; restored to the desktop) and a red outline takes its place.
win_grab
                ld    a,1
                ld    (win_dragging),a
                ld    a,20                   ; faster cursor while dragging a window
                ld    (maxspd),a
                call  cursor_to_screen
                ld    a,(ch_xb)              ; cursor offset into the window
                ld    hl,wnd_x
                sub   (hl)
                ld    (win_grab_dx),a
                ld    a,(ch_ln)
                ld    hl,wnd_y
                sub   (hl)
                ld    (win_grab_dy),a
                ld    a,(wnd_x)             ; outline starts at the window position
                ld    (wo_x),a
                ld    a,(wnd_y)
                ld    (wo_y),a
                call  cursor_erase
                call  window_close            ; window -> transparent
                ld    a,PEN_SELECT            ; red outline
                call  draw_wo
                jp    cursor_draw

; win_drag_frame: move the red outline to follow the pointer.
win_drag_frame
                ld    hl,(tgt_x)             ; new pos = cursor(screen) - grab offset
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                ld    hl,win_grab_dx
                sub   (hl)
                jr    nc,wdf_xok             ; floor underflow to 0
                xor   a
wdf_xok
                ld    (wnd_nx),a
                ld    hl,(tgt_y)
                srl   h
                rr    l
                ld    a,199
                sub   l
                ld    hl,win_grab_dy
                sub   (hl)
                jr    nc,wdf_yok             ; floor underflow to 0
                xor   a
wdf_yok
                ld    (wnd_ny),a
                call  clamp_win_pos

                ld    a,(wnd_nx)             ; outline moved?
                ld    hl,wo_x
                cp    (hl)
                jr    nz,wdf_move
                ld    a,(wnd_ny)
                ld    hl,wo_y
                cp    (hl)
                jr    nz,wdf_move
                ld    de,(tgt_x)
                ld    hl,(tgt_y)
                jp    cursor_move_to
wdf_move
                call  cursor_erase
                ld    a,PEN_DESKTOP           ; erase the old outline + repair icons
                call  draw_wo
                call  repair_others
                ld    a,(wo_y)               ; restore chrome only if it was up top
                cp    17
                jr    nc,wdf_nochrome
                call  redraw_chrome
wdf_nochrome
                ld    a,(wnd_nx)
                ld    (wo_x),a
                ld    a,(wnd_ny)
                ld    (wo_y),a
                ld    a,PEN_SELECT            ; draw the outline at the new position
                call  draw_wo
                ld    hl,(tgt_x)
                ld    (cursor_x),hl
                ld    hl,(tgt_y)
                ld    (cursor_y),hl
                jp    cursor_draw

; win_drop: erase the outline and stamp the filled window at the final position.
win_drop
                ld    a,SPD_MAX              ; restore the precise cursor speed
                ld    (maxspd),a
                call  cursor_erase
                ld    a,PEN_DESKTOP
                call  draw_wo
                call  repair_others
                call  redraw_chrome
                ld    a,(wo_x)
                ld    (wnd_x),a
                ld    a,(wo_y)
                ld    (wnd_y),a
                call  window_open
                call  draw_floppy_content      ; restore the window's interior
                jp    cursor_draw

; redraw_chrome: repaint the desktop title bar and help line (restores text the
; window outline may have nicked).
redraw_chrome
                call  draw_title_bar
                jp    draw_help

; draw_wo: A = pen. Draw the drag outline box at (wo_x,wo_y), window-sized.
draw_wo
                push  af
                call  set_wo_rect
                pop   af
                call  draw_box
                ret

; set_wo_rect: graphics-coord rectangle (rx0..ry1) for the outline at wo_x,wo_y.
set_wo_rect
                ld    a,(wo_x)              ; rx0 = wo_x * 8
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    (rx0),hl
                ld    a,(wo_x)              ; rx1 = (wo_x + wnd_w) * 8
                ld    hl,wnd_w
                add   a,(hl)
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    (rx1),hl
                ld    a,200                 ; ry0 = (200 - wo_y - wnd_h) * 2
                ld    hl,wo_y               ; (bottom edge = window's last row)
                sub   (hl)
                ld    hl,wnd_h
                sub   (hl)
                ld    l,a
                ld    h,0
                add   hl,hl
                ld    (ry0),hl
                ld    a,199                 ; ry1 = (199 - wo_y) * 2
                ld    hl,wo_y
                sub   (hl)
                ld    l,a
                ld    h,0
                add   hl,hl
                ld    (ry1),hl
                ret

; clamp_win_pos: clamp wnd_nx to <= 80-wnd_w and wnd_ny to <= 200-wnd_h.
; (Underflow to 0 is handled by the caller.)
clamp_win_pos
                ld    a,80
                ld    hl,wnd_w
                sub   (hl)
                ld    b,a                     ; B = 80 - wnd_w (max x)
                ld    a,(wnd_nx)
                cp    b
                jr    c,cwp_xok
                ld    a,b
                ld    (wnd_nx),a
cwp_xok
                ld    a,200
                ld    hl,wnd_h
                sub   (hl)
                ld    b,a                     ; B = 200 - wnd_h (max y)
                ld    a,(wnd_ny)
                cp    b
                jr    c,cwp_yok
                ld    a,b
                ld    (wnd_ny),a
cwp_yok
                ret

; --- Desktop data --------------------------------------------------------
mem_str         defs  8            ; total-RAM string for the top bar ("128K")
fm_lead         db    0            ; fmt_mem leading-zero flag
have_rtc        db    0            ; 1 = Dallas RTC present, 0 = software clock
sw_sec          db    0            ; software clock (binary)
sw_min          db    0
sw_hour         db    0
clk_frames      db    0            ; 50Hz frame counter -> seconds
rt_h            db    0            ; current hours/minutes (BCD) for formatting
rt_m            db    0
time_str        defs  6            ; "HH:MM" + NUL
clk_shown       defs  6            ; last "HH:MM" drawn (redraw only on change)
help_text       db    "Hold Fire/Space to drag   ESC: quit",0

; --- Mutable state -------------------------------------------------------
spd             db    SPD_MIN
maxspd         db    SPD_MAX      ; current top speed (raised while window-dragging)
last_fire       db    0
dragging        db    0
win_dragging    db    0            ; dragging the window by its title bar
win_grab_dx     db    0            ; cursor offset into the window at grab
win_grab_dy     db    0
wnd_nx          db    0            ; proposed new window position
wnd_ny          db    0
wo_x            db    0            ; drag outline position
wo_y            db    0
dclick_timer    db    0            ; frames left to register a double-click
dclick_idx      db    0            ; icon index of the first click
win_placed      db    0            ; 0 until the window's first open (initial pos)
df_i            db    0            ; draw_disk_contents loop index
df_xb           db    0            ; current file-icon x byte
df_yb           db    0            ; current file-icon y line
sel_icon        db    NO_ICON      ; selected icon index, or NO_ICON
drag_idx        db    NO_ICON      ; icon currently being dragged
li_idx          db    0            ; load_icon scratch
il_sum          dw    0            ; icon_load: directory size sum
il_cnt          db    0            ; icon_load: directory entries left
; --- active icon size + derived box geometry (set by compute_geometry) ---
icon_w          db    8            ; bytes per row (32x32 default)
icon_h          db    32           ; rows
icon_bytes      dw    256          ; icon_w * icon_h (slot stride)
box_w           dw    80           ; bounding box (graphics): icon_w*8 + 2*INSET
box_h           dw    80           ; icon_h*2 + LABEL_BAND
box_w1          dw    81           ; box_w + 1 (hit-test)
box_h1          dw    81
box_wsi         dw    72           ; box_w - SHAPE_INSET (shape rect)
box_wfg         dw    84           ; box_w + FRAME_G (frame rect)
box_hfg         dw    84
box_wh          dw    40           ; box_w / 2 (label centering)
bm_y_base       db    159          ; 199 - box_h/2 (icon top line)
ixmax_v         dw    555          ; 639 - box_w - FRAME_G (drag clamp)
iymax_v         dw    282          ; 366 - box_h - FRAME_G
list_off        dw    64           ; (icon_h/4)*icon_w (half-height list offset)
list_bmh        db    16           ; icon_h/2 (half-height list rows)
wbmp            dw    0            ; working icon bitmap pointer
wlabel          dw    0            ; working icon label pointer
wx              dw    0            ; working icon position
wy              dw    0
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

; --- Live icon table (parallel arrays, built at startup by ---------------
; build_desktop_icons from cand_tbl). Only drives that actually have a disk get
; a slot, so the row reflects the real hardware. Drive icons carry a backend
; (icon_first/next != 0) + a unit; system icons leave those 0.
n_icons         db    0            ; active icon count (set by build_desktop_icons)
icon_xs         defs  NUM_ICONS*2
icon_ys         defs  NUM_ICONS*2
icon_bmps       defs  NUM_ICONS*2
icon_labels     defs  NUM_ICONS*2
icon_first      defs  NUM_ICONS*2  ; backend fs_dir_first (0 = system icon)
icon_next       defs  NUM_ICONS*2
icon_unit       defs  NUM_ICONS    ; floppy drive unit (0 = A, 1 = B)
bdi_lefty       dw    0            ; next free y in the left-hand drive column

; --- Candidate icons (static source; build_desktop_icons filters by presence)
; record: x(w) y(w) bmp(w) label(w) first(w) next(w) unit(b) kind(b)
; kind 0 = always; 1 = floppy (probe drive 'unit' for a disk); 2 = IDE (probe).
; Drives use placeholder x,y (overridden to the left column); the order here is
; the priority order in that column.
CAND_SIZE       equ   14
cand_tbl
                dw    0, 0, icon_floppy, label_dska, fsam_dir_first,  fsam_dir_next
                db    0, 1
                dw    0, 0, icon_floppy, label_dskb, fsam_dir_first,  fsam_dir_next
                db    1, 1
                dw    0, 0, icon_ide,    label_ide,  fside_dir_first, fside_dir_next
                db    0, 2
                dw    524, 258, icon_clock, label_clock, 0, 0
                db    0, 0
                dw    524, 16,  icon_trash, label_trash, 0, 0
                db    0, 0
CAND_COUNT      equ   5
label_dska      db    "Disk A",0
label_dskb      db    "Disk B",0
label_ide       db    "IDE",0
label_clock     db    "Clock",0
label_trash     db    "Trash",0

; ---------------------------------------------------------------------------
; mem_detect: count present 64K expansion banks (adapted from
; llopis/amstrad-diagnostics). The gate-array RAM-config port (&7Fxx) value
; &C4+bank*8 pages a 64K bank's block 0 into &4000-&7FFF; we mark each bank's
; &4000 and count the ones that keep their mark. Returns A = bank count.
;
; MUST be located above &8000: paging swaps &4000-&7FFF (where the rest of
; GEOBENCH runs), but RAM block 2 (&8000-&BFFF, this code + the stack) is left
; alone by configs &C4..&C7. Only &4000-&4001 is touched, saved and restored.
; Call with interrupts disabled.
mem_detect
                ld    hl,(#4000)             ; save main &4000-&4001
                ld    (md_save),hl

                ld    d,0                     ; clear every bank's marker to 0
md_clear
                ld    e,0
                call  md_port
                ld    bc,#7F00
                out   (c),l
                xor   a
                ld    (#4000),a
                ld    (#4001),a
                inc   d
                ld    a,d
                cp    8
                jr    nz,md_clear

                ld    bc,#7FC0               ; main marker = &FFFF (normal config)
                out   (c),c
                ld    a,#FF
                ld    (#4000),a
                ld    (#4001),a

                xor   a
                ld    (md_count),a
                ld    a,#FF
                ld    (md_last),a
                ld    (md_last+1),a

                ld    d,0
md_detect
                ld    e,0
                call  md_port
                ld    bc,#7F00
                out   (c),l
                call  md_valid               ; NZ = present, Z = absent/mirror
                jr    z,md_next
                ld    hl,md_count
                inc   (hl)
                call  md_update
md_next
                inc   d
                ld    a,d
                cp    8
                jr    nz,md_detect

                ld    bc,#7FC0               ; restore normal config + &4000
                out   (c),c
                ld    hl,(md_save)
                ld    (#4000),hl
                ld    a,(md_count)
                ret

md_port                                       ; D=bank E=block -> L = port value
                ld    a,d
                add   a,a
                add   a,a
                add   a,a                     ; bank*8
                or    #C4
                or    e
                ld    l,a
                ret

md_valid                                      ; read marker; NZ=present, Z=absent
                ld    a,(#4000)
                cp    #FF
                jr    z,md_invalid
                ld    e,a
                ld    a,(md_last)
                cp    e
                jr    z,md_invalid
                ld    a,(#4001)
                cp    #FF
                jr    z,md_invalid
                ld    e,a
                ld    a,(md_last+1)
                cp    e
                jr    z,md_invalid
                ld    a,1
                or    a
                ret
md_invalid
                xor   a
                ret

md_update                                      ; mark counted bank, remember it
                ld    a,#FF
                ld    (#4000),a
                ld    (#4001),a
                ld    (md_last),a
                ld    (md_last+1),a
                ret

md_save         dw    0
md_count        db    0
md_last         dw    0

end
                save  "GEOBENCH.BIN",geobench,end-geobench,DSK,"build/geobench.dsk"
                save  "build/GEOBENCH.RAW",geobench,end-geobench

; Put the config and default icon set on the floppy too, so a floppy-only
; machine loads them just like the IDE build (fsam_load_file strips the AMSDOS
; header RASM adds). build/DEFAULT.IST must be packed (tools/packicons.py)
; before assembling -- tools/build.sh does that.
cfg_file        incbin "../GEOBENCH.CFG.example"
cfg_file_end
                save  "GEOBENCH.CFG",cfg_file,cfg_file_end-cfg_file,DSK,"build/geobench.dsk"
                save  "DEFAULT.IST",icon_rom_data,ROMSET_SIZE,DSK,"build/geobench.dsk"
                save  "DEFAULT.FNT",font_rom_data,FONTSET_SIZE,DSK,"build/geobench.dsk"
