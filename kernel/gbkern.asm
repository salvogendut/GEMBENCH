; gbkern - GEOBENCH banked-kernel skeleton (Phase 2).
;
; Resident at GB_KERNEL (#8000), it owns the machine and the stack and never
; lives in the #4000-#7FFF window, so it can page apps and its own data buffers
; in and out. It exposes a fixed API jump table (see lib/gbapp.inc), loads a
; real app binary off disk into PAGE_APP0, and runs it there.
;
; Services with banked buffers follow the page-swap discipline: a service saves
; the caller's page (bank_cur), swaps to PAGE_DATA, touches its buffer, and
; restores the caller's page. gb_text_draw is the first real one - it renders
; the 6x8 font, whose glyphs live in PAGE_DATA. Strings come from the caller's
; page, so they are copied to a resident scratch BEFORE swapping to the font.
;
; Build: tools/build_kernel.sh   Run: 1984 --memory=128 --disk-a=build/gbkern.dsk --autostart=GBKERN

                include "../lib/gbapp.inc"
                include "../lib/firmware.inc"

                org   GB_KERNEL
; --- fixed API jump table (order is the ABI; see lib/gbapp.inc) -----------
                jp    kernel_main            ; GB_INIT  #8000
                jp    k_cls                  ; GB_CLS   #8003
                jp    k_print                ; GB_PRINT #8006
                jp    k_quit                 ; GB_QUIT  #8009
                jp    gb_text_draw           ; GB_TEXT   #800C
                jp    gb_open_window         ; GB_WINDOW #800F
                jp    gb_fs_dir_first        ; GB_DIR1   #8012
                jp    gb_fs_dir_next         ; GB_DIRN   #8015
                jp    gb_blit_entry          ; GB_BLITE  #8018
                jp    k_curshow              ; GB_CURSHOW #801B
                jp    k_poll                 ; GB_POLL    #801E
                jp    k_frame                ; GB_FRAME   #8021

; ---------------------------------------------------------------------------
kernel_main
                ld    a,1
                call  SCR_SET_MODE           ; mode 1, screen cleared
                call  TXT_CUR_DISABLE        ; no blinking firmware cursor blob
                call  TXT_CUR_OFF
                call  set_palette            ; GEOBENCH 4-pen palette
                call  fs_init                ; pick storage backend (floppy here)
                call  font_init              ; load the font into PAGE_DATA
                call  icon_init              ; load the icon set into PAGE_DATA
                call  app_launch             ; load FILEMGR.BIN into PAGE_APP0, run it
                ld    a,2                     ; app quit -> back to BASIC (mode 2,
                call  SCR_SET_MODE           ; clears) until the desktop kernel exists
                ret

; --- palette -------------------------------------------------------------
INK_DESKTOP     equ   1            ; blue  -> pen 0 (paper / backdrop)
INK_LIGHT       equ   26           ; white -> pen 1 (text)
INK_DARK        equ   0            ; black -> pen 2 (outlines / title bar)
INK_ACCENT      equ   6            ; red   -> pen 3 (accents)
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
                jp    SCR_SET_BORDER

; --- input + cursor services ---------------------------------------------
; k_curshow: draw the pointer (the app calls this once after drawing its UI).
k_curshow
                jp    cursor_show

; k_poll: frame-paced input poll. Moves the cursor by the held directions and
; redraws it; returns B = cursor byte col, C = cursor line, D flags: bit0 = a
; fresh click (fire just pressed), bit1 = quit (ESC). Interrupts must be on so
; the firmware scans the keyboard.
k_poll
                call  input_poll             ; in_dirs / in_fire / in_quit
                call  poll_move              ; -> DE = new x, HL = new y (clamped)
                call  MC_WAIT_FLYBACK        ; pace to 50 Hz; do the move in the blank
                call  cursor_move_to         ; erases+redraws ONLY if the position
                                             ; actually changed (re-drawing in place,
                                             ; e.g. holding a key into the edge clamp,
                                             ; corrupts the save-under). In the flyback
                                             ; blank so the move isn't seen mid-frame.
                ld    hl,(cursor_x)          ; cursor byte col = cursor_x / 8
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                ld    (poll_byte),a
                ld    hl,(cursor_y)          ; cursor line = 199 - cursor_y / 2
                srl   h
                rr    l
                ld    a,199
                sub   l
                ld    (poll_line),a
                ld    d,0
                ld    a,(in_fire)            ; click edge = fire & !last_fire
                ld    e,a
                ld    a,(poll_lastfire)
                cpl
                and   e
                jr    z,gp_noclick
                set   0,d
gp_noclick
                ld    a,e
                ld    (poll_lastfire),a
                ld    a,(in_quit)
                or    a
                jr    z,gp_noquit
                set   1,d
gp_noquit
                ld    a,(poll_byte)
                ld    b,a
                ld    a,(poll_line)
                ld    c,a
                ret
poll_lastfire   db    0
poll_byte       db    0
poll_line       db    0

; poll_move: compute the new cursor position from the held directions (in_dirs),
; clamped. Returns DE = new x, HL = new y. Does NOT write cursor_x/y - that is
; left to cursor_move_to, which only redraws when the position actually changes.
poll_move
                ld    a,(in_dirs)
                ld    c,a
                ld    hl,(cursor_x)
                bit   2,c                     ; DIR_LEFT
                jr    z,pm_right
                ld    de,-12
                add   hl,de
pm_right
                bit   3,c                     ; DIR_RIGHT
                jr    z,pm_xclamp
                ld    de,12
                add   hl,de
pm_xclamp
                call  clamp638
                ld    (pm_newx),hl
                ld    hl,(cursor_y)
                bit   0,c                     ; DIR_UP -> +y (screen up)
                jr    z,pm_down
                ld    de,12
                add   hl,de
pm_down
                bit   1,c                     ; DIR_DOWN -> -y
                jr    z,pm_yclamp
                ld    de,-12
                add   hl,de
pm_yclamp
                call  clamp398               ; HL = new y
                ld    de,(pm_newx)           ; DE = new x
                ret
pm_newx         dw    0
clamp638
                ld    de,638
                jr    clamp_hl
clamp398
                ld    de,398
clamp_hl                                       ; clamp HL to [0, DE]
                bit   7,h                     ; negative -> 0
                jr    z,ch_hi
                ld    hl,0
                ret
ch_hi
                push  hl
                or    a
                sbc   hl,de
                pop   hl
                ret   c                        ; HL < DE -> keep
                ex    de,hl                    ; clamp to DE
                ret

; k_frame (GB_FRAME): draw a 1px rectangle outline. B=x C=y D=w E=h (screen
; byte/line), A=pen (0..3). Screen only (no banked buffer), so no page swap.
k_frame
                call  pen_to_byte            ; pen -> Mode 1 fill byte
                ld    (gf_val),a
                ld    a,b
                ld    (gf_x),a
                ld    a,c
                ld    (gf_y),a
                ld    a,d
                ld    (gf_w),a
                ld    a,e
                ld    (gf_h),a
                ld    a,(gf_val)
                ld    (fb_val),a
                ld    a,(gf_x)               ; top edge
                ld    (fb_x),a
                ld    a,(gf_y)
                ld    (fb_y),a
                ld    a,(gf_w)
                ld    (fb_w),a
                ld    a,1
                ld    (fb_h),a
                call  fill_block
                ld    a,(gf_x)               ; bottom edge (y + h - 1)
                ld    (fb_x),a
                ld    a,(gf_y)
                ld    b,a
                ld    a,(gf_h)
                add   a,b
                dec   a
                ld    (fb_y),a
                ld    a,(gf_w)
                ld    (fb_w),a
                ld    a,1
                ld    (fb_h),a
                call  fill_block
                ld    a,(gf_x)               ; left edge
                ld    (fb_x),a
                ld    a,(gf_y)
                ld    (fb_y),a
                ld    a,1
                ld    (fb_w),a
                ld    a,(gf_h)
                ld    (fb_h),a
                call  fill_block
                ld    a,(gf_x)               ; right edge (x + w - 1)
                ld    b,a
                ld    a,(gf_w)
                add   a,b
                dec   a
                ld    (fb_x),a
                ld    a,(gf_y)
                ld    (fb_y),a
                ld    a,1
                ld    (fb_w),a
                ld    a,(gf_h)
                ld    (fb_h),a
                jp    fill_block
gf_x            db    0
gf_y            db    0
gf_w            db    0
gf_h            db    0
gf_val          db    0

; --- firmware text (kernel boot messages) --------------------------------
k_cls
                ld    a,1
                jp    SCR_SET_MODE            ; mode 1 clears; returns to caller
k_print
                ld    a,(hl)
                or    a
                ret   z
                call  TXT_OUTPUT
                inc   hl
                jr    k_print
k_quit
                ret                            ; (skeleton: app RETs anyway)

; --- gb_text_draw: 6x8 font text service ---------------------------------
; B = byte col, C = line, D = pen, E = paper, HL = string (caller's page).
; Copy the string to resident scratch (caller page still mapped), set up the
; renderer, then swap to PAGE_DATA for the glyphs, draw, and restore.
gb_text_draw
                ld    a,b                     ; position
                ld    (tc_x),a
                ld    a,c
                ld    (tc_y),a
                ld    b,d                     ; pens: B = pen, C = paper
                ld    c,e
                push  hl
                call  set_text_pens
                pop   hl
                ld    de,gtd_scratch          ; copy string out of the caller's page
                call  gtd_copy
                ld    a,(bank_cur)            ; save caller's page
                ld    (gtd_save),a
                ld    a,PAGE_DATA            ; swap to the font page
                call  bank_set
                ld    hl,gtd_scratch
                call  draw_text
                ld    a,(gtd_save)           ; restore caller's page
                jp    bank_set
gtd_copy                                       ; (HL) -> (DE) until NUL, cap 48
                ld    b,48
gtd_cloop
                ld    a,(hl)
                ld    (de),a
                or    a
                ret   z
                inc   hl
                inc   de
                djnz  gtd_cloop
                xor   a                        ; truncate + terminate
                ld    (de),a
                ret
gtd_scratch     defs  49
gtd_save        db    0

; --- gb_open_window: draw a window frame + title -------------------------
; B = x (byte col), C = y (line), D = w (bytes), E = h (lines), HL = title.
; The frame is plain fills (screen only); the title needs the font, so swap to
; PAGE_DATA for it. No save-under: closing a window redraws the desktop.
gb_open_window
                ld    a,b
                ld    (kw_x),a
                ld    a,c
                ld    (kw_y),a
                ld    a,d
                ld    (kw_w),a
                ld    a,e
                ld    (kw_h),a
                ld    de,kw_title            ; copy title out of the caller's page
                call  gtd_copy
                call  kwin_frame             ; frame: fills to screen, no font
                ld    a,(bank_cur)
                ld    (kw_save),a
                ld    a,PAGE_DATA            ; title needs the font page
                call  bank_set
                ld    b,1                     ; white on black title bar
                ld    c,2
                call  set_text_pens
                ld    a,(kw_x)
                add   a,4
                ld    (tc_x),a
                ld    a,(kw_y)
                add   a,3
                ld    (tc_y),a
                ld    hl,kw_title
                call  draw_text
                ld    a,(kw_save)
                jp    bank_set

; kwin_frame: blue interior, black title bar + borders, white close gadget.
kwin_frame
                ld    a,(kw_x)               ; interior (blue)
                ld    (fb_x),a
                ld    a,(kw_y)
                ld    (fb_y),a
                ld    a,(kw_w)
                ld    (fb_w),a
                ld    a,(kw_h)
                ld    (fb_h),a
                xor   a
                ld    (fb_val),a
                call  fill_block
                ld    a,(kw_x)               ; title bar (black, 14 high)
                ld    (fb_x),a
                ld    a,(kw_y)
                ld    (fb_y),a
                ld    a,(kw_w)
                ld    (fb_w),a
                ld    a,14
                ld    (fb_h),a
                ld    a,#0F
                ld    (fb_val),a
                call  fill_block
                ld    a,(kw_x)               ; left border
                ld    (fb_x),a
                ld    a,1
                ld    (fb_w),a
                ld    a,(kw_h)
                ld    (fb_h),a
                call  fill_block             ; (fb_y/fb_val still set)
                ld    a,(kw_x)               ; right border
                ld    b,a
                ld    a,(kw_w)
                add   a,b
                dec   a
                ld    (fb_x),a
                ld    a,1
                ld    (fb_w),a
                ld    a,(kw_h)
                ld    (fb_h),a
                call  fill_block
                ld    a,(kw_x)               ; bottom border
                ld    (fb_x),a
                ld    a,(kw_y)
                ld    b,a
                ld    a,(kw_h)
                add   a,b
                dec   a
                ld    (fb_y),a
                ld    a,(kw_w)
                ld    (fb_w),a
                ld    a,1
                ld    (fb_h),a
                call  fill_block
                ld    a,(kw_x)               ; close gadget (white)
                inc   a
                ld    (fb_x),a
                ld    a,(kw_y)
                add   a,2
                ld    (fb_y),a
                ld    a,2
                ld    (fb_w),a
                ld    a,10
                ld    (fb_h),a
                ld    a,#F0
                ld    (fb_val),a
                call  fill_block
                ret
kw_x            db    0
kw_y            db    0
kw_w            db    0
kw_h            db    0
kw_save         db    0
kw_title        defs  24

; --- directory enumeration services --------------------------------------
; Return CF set with HL -> a resident "NAME.EXT" string (0-term) for the entry,
; or NC at end of directory. fs_ent_* are resident, so no page swap is needed;
; the floppy backend is di-safe and uses its own resident buffers.
gb_fs_dir_first
                call  fs_dir_first
                jr    gdir_done
gb_fs_dir_next
                call  fs_dir_next
gdir_done
                ret   nc                       ; no/Last entry
                call  fmt_entry              ; fs_ent_name -> dir_namebuf
                ld    hl,dir_namebuf
                scf
                ret

; fmt_entry: fs_ent_name (8.3, space padded) -> dir_namebuf as "NAME.EXT", 0.
fmt_entry
                ld    de,dir_namebuf
                ld    hl,fs_ent_name
                ld    b,8
fe_name
                ld    a,(hl)
                cp    ' '
                jr    z,fe_ext
                ld    (de),a
                inc   de
                inc   hl
                djnz  fe_name
fe_ext
                ld    a,(showext)            ; name-only by default; type from icon
                or    a
                jr    z,fe_end
                ld    hl,fs_ent_name+8
                ld    a,(hl)
                cp    ' '
                jr    z,fe_end
                ld    a,'.'
                ld    (de),a
                inc   de
                ld    b,3
fe_xl
                ld    a,(hl)
                cp    ' '
                jr    z,fe_end
                ld    (de),a
                inc   de
                inc   hl
                djnz  fe_xl
fe_end
                xor   a
                ld    (de),a
                ret
dir_namebuf     defs  14
showext         db    0            ; 0 = name only (default), 1 = NAME.EXT

; --- gb_blit_entry: half-height type icon for the current entry ----------
; B = byte col, C = line. Picks the icon by fs_ent_name's extension, reads the
; bitmap + size from the .IST in PAGE_DATA, and blits its middle band.
gb_blit_entry
                ld    a,b
                ld    (be_x),a
                ld    a,c
                ld    (be_y),a
                call  ext_to_icon            ; A = slot (reads resident fs_ent_name)
                ld    (be_slot),a
                ld    a,(bank_cur)
                ld    (be_save),a
                ld    a,PAGE_DATA
                call  bank_set
                ld    a,(be_slot)
                call  icon_geom              ; sets bm_src/bm_w/bm_h/bm_x/bm_y
                call  blit_bitmap
                ld    a,(be_save)
                jp    bank_set
be_x            db    0
be_y            db    0
be_slot         db    0
be_save         db    0
ig_w            db    0
ig_h            db    0

; icon_geom: A = slot -> from the .IST directory (DATA_ICONS) set up a
; half-height blit (middle band) at (be_x, be_y). PAGE_DATA must be mapped.
icon_geom
                ld    l,a                     ; dir entry = DATA_ICONS+16 + slot*4
                ld    h,0
                add   hl,hl
                add   hl,hl
                ld    de,DATA_ICONS+16
                add   hl,de
                ld    e,(hl)                  ; offset (word)
                inc   hl
                ld    d,(hl)
                inc   hl
                ld    a,(hl)                  ; width (bytes)
                ld    (ig_w),a
                inc   hl
                ld    a,(hl)                  ; height (rows)
                ld    (ig_h),a
                ld    hl,DATA_ICONS          ; bitmap base = DATA_ICONS + offset
                add   hl,de
                ld    a,(ig_h)               ; + (h/4)*w  (skip the top quarter)
                srl   a
                srl   a
                ld    b,a
                ld    a,(ig_w)
                ld    e,a
                ld    d,0
ig_skip
                ld    a,b
                or    a
                jr    z,ig_done
                add   hl,de
                dec   b
                jr    ig_skip
ig_done
                ld    (bm_src),hl
                ld    a,(ig_w)
                ld    (bm_w),a
                ld    a,(ig_h)               ; half height
                srl   a
                ld    (bm_h),a
                ld    a,(be_x)
                ld    (bm_x),a
                ld    a,(be_y)
                ld    (bm_y),a
                ret

; ext_to_icon: A = icon slot for fs_ent_name (GEOBENCH/BAS/BIN/SCR/TXT -> their
; icons, else generic binary). Slots match the desktop's icon set order.
ext_to_icon
                ld    hl,name_geobench
                call  cmp_name8
                jr    z,eti_geo
                ld    hl,ext_bas
                call  cmp_ext
                jr    z,eti_bas
                ld    hl,ext_scr
                call  cmp_ext
                jr    z,eti_scr
                ld    hl,ext_txt
                call  cmp_ext
                jr    z,eti_txt
                ld    a,6                      ; binary (default)
                ret
eti_bas         ld    a,5
                ret
eti_scr         ld    a,7
                ret
eti_txt         ld    a,8
                ret
eti_geo         ld    a,4
                ret

cmp_name8                                      ; Z if name_geobench == fs_ent_name[0..7]
                ld    de,fs_ent_name
                ld    b,8
cn8
                ld    a,(de)
                cp    (hl)
                ret   nz
                inc   hl
                inc   de
                djnz  cn8
                xor   a
                ret
cmp_ext                                        ; Z if (HL) 3-char ext == fs_ent_name+8
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
ext_bas         db    "BAS"
ext_scr         db    "SCR"
ext_txt         db    "TXT"
name_geobench   db    "GEOBENCH"

; --- font in PAGE_DATA ----------------------------------------------------
; font_init: page PAGE_DATA in, load DEFAULT.FNT into it, cache the geometry.
font_init
                di
                ld    a,PAGE_DATA
                call  bank_set
                ld    hl,font_name           ; fs_req_name = "DEFAULT FNT"
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    hl,#1000               ; font fits easily
                ld    (fs_load_max),hl
                ld    hl,DATA_FONT           ; load into PAGE_DATA
                ld    (fs_load_dst),hl
                call  fs_load_file
                ld    hl,DATA_FONT           ; cache geometry (font_glyphs -> PAGE_DATA)
                call  font_apply_header
                call  bank_normal
                ei
                ret
font_name       db    "DEFAULT FNT"          ; 8.3, space-padded

; icon_init: load DEFAULT.IST into PAGE_DATA at DATA_ICONS.
icon_init
                di
                ld    a,PAGE_DATA
                call  bank_set
                ld    hl,icon_name           ; fs_req_name = "DEFAULT IST"
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    hl,#0C00               ; .IST <= 3K
                ld    (fs_load_max),hl
                ld    hl,DATA_ICONS
                ld    (fs_load_dst),hl
                call  fs_load_file
                call  bank_normal
                ei
                ret
icon_name       db    "DEFAULT IST"          ; 8.3, space-padded

; --- app launch ----------------------------------------------------------
app_launch
                di
                ld    a,PAGE_APP0
                call  bank_set
                ld    hl,app_name             ; fs_req_name = "HELLO   BIN"
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    hl,#3F00               ; cap: app must fit the 16K window
                ld    (fs_load_max),hl
                ld    hl,APP_BASE             ; load straight into the window
                ld    (fs_load_dst),hl
                call  fs_load_file
                jr    nc,al_fail
                ei                            ; app runs with interrupts on (the
                call  APP_BASE               ; firmware keyboard scan needs them)
                di
                call  bank_normal
                ei
                ret
al_fail
                call  bank_normal
                ei
                ld    hl,msg_fail
                jp    k_print

app_name        db    "FILEMGR BIN"          ; 8.3, space-padded
msg_fail        db    "APP LOAD FAILED",13,10,0

                include "../lib/screen.asm"
                include "../lib/text.asm"
                include "../lib/cursor_arrow.asm"
                include "../lib/cursor.asm"
                include "../lib/input.asm"
                include "../lib/fs.asm"
                include "../lib/fs_ide_fat.asm"
                include "../lib/fs_amsdos.asm"
                include "../lib/bank.asm"
kern_end                                        ; GBKERN.BIN is CODE ONLY (must end
                                                ; below HIMEM ~#A67B). The packaging
                                                ; incbins live above it - never loaded
                                                ; at runtime, only read by `save`.
app_img         incbin "../build/FILEMGR.RAW"   ; packaged on the disk as FILEMGR.BIN
app_imgend
font_img        incbin "../build/DEFAULT.FNT"   ; packaged on the disk as DEFAULT.FNT
font_imgend
icon_img        incbin "../build/DEFAULT.IST"   ; packaged on the disk as DEFAULT.IST
icon_imgend
                save  "GBKERN.BIN",GB_KERNEL,kern_end-GB_KERNEL,DSK,"build/gbkern.dsk"
                save  "FILEMGR.BIN",app_img,app_imgend-app_img,DSK,"build/gbkern.dsk"
                save  "DEFAULT.FNT",font_img,font_imgend-font_img,DSK,"build/gbkern.dsk"
                save  "DEFAULT.IST",icon_img,icon_imgend-icon_img,DSK,"build/gbkern.dsk"
                save  "build/GBKERN.RAW",GB_KERNEL,kern_end-GB_KERNEL
