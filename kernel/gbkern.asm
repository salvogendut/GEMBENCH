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
                jp    cursor_erase           ; GB_CURHIDE #8024
                jp    k_launch               ; GB_LAUNCH  #8027
                jp    k_getarg               ; GB_GETARG  #802A
                jp    k_run                  ; GB_RUN     #802D
                jp    k_icon                 ; GB_ICON    #8030
                jp    k_fill                 ; GB_FILL    #8033
                jp    k_saverect             ; GB_SAVERECT    #8036
                jp    k_restorerect          ; GB_RESTORERECT #8039
                jp    k_xorframe             ; GB_XORFRAME    #803C

; ---------------------------------------------------------------------------
kernel_main
                ld    a,1
                call  SCR_SET_MODE           ; mode 1, screen cleared
                call  TXT_CUR_DISABLE        ; no blinking firmware cursor blob
                call  TXT_CUR_OFF
                call  set_palette            ; GEOBENCH 4-pen palette
                call  fs_init                ; pick storage backend (floppy here)
                di                            ; probe RAM BEFORE PAGE_DATA is filled
                call  mem_detect             ; (it pokes every bank's #4000)
                ei
                ld    l,a                     ; total KB = 64 + banks*64
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    de,64
                add   hl,de
                call  fmt_mem                ; -> mem_str
                call  font_init              ; load the font into PAGE_DATA
                call  icon_init              ; load the icon set into PAGE_DATA
                call  clock_init             ; RTC or software clock -> time_str
                call  draw_topbar            ; the kernel owns the top bar
                ld    hl,name_desktop        ; the desktop is the first app
                call  launch_app             ; run DESKTOP in PAGE_APP0
                ld    a,2                     ; desktop quit (ESC) -> back to BASIC
                call  SCR_SET_MODE
                ret
name_desktop    db    "DESKTOP BIN"

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
                                             ; MUST precede clock_tick: it consumes the
                                             ; DE/HL target that clock_tick would clobber.
                call  clock_tick             ; keep the top-bar clock live
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
                ld    a,(in_fire)            ; bit2 = fire currently held (for drag)
                or    a
                jr    z,gp_nohold
                set   2,d
gp_nohold
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
                ld    (gf_pen),a             ; save params FIRST: pen_to_byte below
                ld    a,b                     ; clobbers E (height), so capture it now
                ld    (gf_x),a
                ld    a,c
                ld    (gf_y),a
                ld    a,d
                ld    (gf_w),a
                ld    a,e
                ld    (gf_h),a
                ld    a,(gf_pen)
                call  pen_to_byte            ; pen -> Mode 1 fill byte
                ld    (gf_val),a
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
gf_pen          db    0

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
; launch_app: HL = 8.3 app name. Load it into the next bank page (PAGE_APP0 +
; launch depth) and run it; restore the caller's page when it quits. Apps nest
; (desktop -> filemgr -> viewer); the caller's page is kept on the stack so any
; depth restores correctly.
launch_app
                ld    de,fs_req_name         ; name -> fs_req_name (HL in caller page)
                ld    bc,11
                ldir
                ld    a,(launch_depth)       ; target page = PAGE_APP0 + depth
                cp    3
                ret   nc                      ; no free page (max 3 apps) -> give up
                add   a,PAGE_APP0
                ld    c,a
                ld    a,(bank_cur)           ; save caller's page (per depth) on stack
                push  af
                ld    hl,launch_depth
                inc   (hl)
                di
                ld    a,c
                call  bank_set
                ld    hl,#3F00
                ld    (fs_load_max),hl
                ld    hl,APP_BASE
                ld    (fs_load_dst),hl
                call  fs_load_file
                jr    nc,la_done             ; missing -> just unwind
                ei
                call  APP_BASE
                di
la_done
                ld    hl,launch_depth
                dec   (hl)
                pop   af                       ; caller's page
                call  bank_set
                ei
                ret
launch_depth    db    0

; k_run (GB_RUN): run a named app. HL = 8.3 name (in the caller's page).
k_run
                jp    launch_app

; k_launch (GB_LAUNCH): open the current entry (fs_ent_name) with its app. Capture
; the file name (the load overwrites fs_ent_name), pick the app by type, run it.
k_launch
                ld    hl,fs_ent_name
                ld    de,launch_arg
                ld    bc,11
                ldir
                call  app_for_ext            ; HL = app .BIN for the type
                jp    launch_app

; k_getarg (GB_GETARG): HL = the launch arg (the 8.3 file name the app opened).
k_getarg
                ld    hl,launch_arg
                ret

; app_for_ext: HL = the app for fs_ent_name's type. Walks app_table: each entry
; is a 3-char extension + an 11-char 8.3 app name; a 0 ends the table -> default.
; (Only VIEWER exists today, so most types fall through to it; add rows as new
; apps land.)
app_for_ext
                ld    hl,app_table
afe_loop
                ld    a,(hl)                  ; 0 = end of table -> default app
                or    a
                jr    z,afe_default
                push  hl                       ; compare the 3-char extension
                ld    de,fs_ent_name+8
                ld    b,3
afe_cmp
                ld    a,(de)
                cp    (hl)
                jr    nz,afe_miss
                inc   hl
                inc   de
                djnz  afe_cmp
                pop   de                       ; matched -> HL = the app name (after ext)
                ret
afe_miss
                pop   hl                       ; skip this entry (3 ext + 11 name)
                ld    de,14
                add   hl,de
                jr    afe_loop
afe_default
                ld    hl,name_viewer
                ret
app_table
                db    "TXT","VIEWER  BIN"      ; .TXT -> VIEWER
                db    0                          ; end of table
name_viewer     db    "VIEWER  BIN"
launch_arg      defs  11

; k_icon (GB_ICON): blit a full icon. A = slot, B = x, C = y. Reads the bitmap
; from the .IST in PAGE_DATA, so swap pages around it.
k_icon
                ld    (gi_slot),a
                ld    a,b
                ld    (gi_x),a
                ld    a,c
                ld    (gi_y),a
                ld    a,(bank_cur)
                ld    (gi_save),a
                ld    a,PAGE_DATA
                call  bank_set
                ld    a,(gi_slot)
                call  icon_full_geom
                call  blit_bitmap
                ld    a,(gi_save)
                jp    bank_set
icon_full_geom                                 ; A = slot -> bm_src/w/h, bm_x/y
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl                     ; slot*4
                ld    de,DATA_ICONS+16
                add   hl,de
                ld    e,(hl)                  ; offset
                inc   hl
                ld    d,(hl)
                inc   hl
                ld    a,(hl)                  ; width
                ld    (bm_w),a
                inc   hl
                ld    a,(hl)                  ; height (full)
                ld    (bm_h),a
                ld    hl,DATA_ICONS
                add   hl,de
                ld    (bm_src),hl
                ld    a,(gi_x)
                ld    (bm_x),a
                ld    a,(gi_y)
                ld    (bm_y),a
                ret
gi_slot         db    0
gi_x            db    0
gi_y            db    0
gi_save         db    0

; k_fill (GB_FILL): filled rectangle. B=x C=y D=w E=h A=pen. Capture the params
; before pen_to_byte (it clobbers E).
k_fill
                ld    (kf_pen),a
                ld    a,b
                ld    (fb_x),a
                ld    a,c
                ld    (fb_y),a
                ld    a,d
                ld    (fb_w),a
                ld    a,e
                ld    (fb_h),a
                ld    a,(kf_pen)
                call  pen_to_byte
                ld    (fb_val),a
                jp    fill_block
kf_pen          db    0

; k_saverect / k_restorerect (GB_SAVERECT / GB_RESTORERECT): save/restore a
; screen rectangle to/from a caller buffer. B=x C=y D=w E=h HL=buffer (w*h
; bytes). The buffer lives in the caller's page (mapped during the call); the
; screen is resident, so no page swap is needed.
k_saverect
                call  set_sb
                jp    save_block
k_restorerect
                call  set_sb
                jp    restore_block
set_sb
                ld    a,b
                ld    (sb_x),a
                ld    a,c
                ld    (sb_y),a
                ld    a,d
                ld    (sb_w),a
                ld    a,e
                ld    (sb_h),a
                ld    (sb_buf),hl
                ret

; k_xorframe (GB_XORFRAME): XOR a 1px rectangle outline into the screen. B=x
; C=y D=w E=h. Self-erasing rubber-band: call again at the same spot to undo.
k_xorframe
                ld    a,b
                ld    (xf_x),a
                ld    a,c
                ld    (xf_y),a
                ld    a,d
                ld    (xf_w),a
                ld    a,e
                ld    (xf_h),a
                ld    a,(xf_x)               ; top edge
                ld    d,a
                ld    a,(xf_y)
                ld    e,a
                ld    a,(xf_w)
                ld    b,a
                call  xf_hline
                ld    a,(xf_x)               ; bottom edge (y+h-1)
                ld    d,a
                ld    a,(xf_y)
                ld    b,a
                ld    a,(xf_h)
                add   a,b
                dec   a
                ld    e,a
                ld    a,(xf_w)
                ld    b,a
                call  xf_hline
                ld    a,(xf_x)               ; left edge
                ld    d,a
                ld    a,(xf_y)
                ld    e,a
                ld    a,(xf_h)
                ld    b,a
                call  xf_vline
                ld    a,(xf_x)               ; right edge (x+w-1)
                ld    b,a
                ld    a,(xf_w)
                add   a,b
                dec   a
                ld    d,a
                ld    a,(xf_y)
                ld    e,a
                ld    a,(xf_h)
                ld    b,a
                jp    xf_vline
xf_hline                                       ; D=x E=y B=count -> XOR a row of bytes
                ld    a,b
                ld    (xf_cnt),a
                call  scr_addr
                ld    a,(xf_cnt)
                ld    b,a
xfh_loop
                ld    a,(hl)
                xor   #FF
                ld    (hl),a
                inc   hl
                djnz  xfh_loop
                ret
xf_vline                                       ; D=x E=y B=rows -> XOR a column
                ld    a,b
                ld    (xf_cnt),a
xfv_loop
                push  de
                call  scr_addr
                ld    a,(hl)
                xor   #FF
                ld    (hl),a
                pop   de
                inc   e
                ld    a,(xf_cnt)
                dec   a
                ld    (xf_cnt),a
                jr    nz,xfv_loop
                ret
xf_x            db    0
xf_y            db    0
xf_w            db    0
xf_h            db    0
xf_cnt          db    0

; ===========================================================================
; Top bar (kernel-owned): total RAM (left) + clock (right) on lines 0-7. The
; kernel keeps the clock ticking via clock_tick in k_poll, so it stays live
; whatever app is focused. Apps must keep clear of the top 8 lines.
; ===========================================================================
CLK_COL         equ   68
TICKS_PER_SEC   equ   50
RTC_ADDR        equ   #FD15        ; Dallas RTC on SymbiFace II / Cyboard
RTC_DATA        equ   #FD14

draw_topbar
                xor   a                        ; white strip across the top
                ld    (fb_x),a
                ld    (fb_y),a
                ld    a,80
                ld    (fb_w),a
                ld    a,8
                ld    (fb_h),a
                ld    a,#F0
                ld    (fb_val),a
                call  fill_block
                ld    a,(bank_cur)
                ld    (tb_save),a
                ld    a,PAGE_DATA            ; text needs the font page
                call  bank_set
                ld    b,2                     ; black on white
                ld    c,1
                call  set_text_pens
                ld    a,1
                ld    (tc_x),a
                xor   a
                ld    (tc_y),a
                ld    hl,mem_str
                call  draw_text
                ld    a,CLK_COL
                ld    (tc_x),a
                xor   a
                ld    (tc_y),a
                ld    hl,time_str
                call  draw_text
                ld    a,(tb_save)
                jp    bank_set
draw_clock
                ld    a,(bank_cur)
                ld    (tb_save),a
                ld    a,PAGE_DATA
                call  bank_set
                ld    b,2
                ld    c,1
                call  set_text_pens
                ld    a,CLK_COL
                ld    (tc_x),a
                xor   a
                ld    (tc_y),a
                ld    hl,time_str
                call  draw_text
                ld    a,(tb_save)
                jp    bank_set
tb_save         db    0

; clock_tick: once per frame from k_poll. Every 50 frames refresh the time and,
; if "HH:MM" changed, redraw the clock (with the pointer lifted).
clock_tick
                ld    a,(clk_frames)
                inc   a
                cp    TICKS_PER_SEC
                jr    c,ct_keep
                xor   a
                ld    (clk_frames),a
                ld    a,(have_rtc)
                or    a
                call  z,sw_tick
                call  read_time
                call  clk_changed
                ret   z
                ld    hl,time_str
                ld    de,clk_shown
                ld    bc,6
                ldir
                call  cursor_erase
                call  draw_clock
                jp    cursor_draw
ct_keep
                ld    (clk_frames),a
                ret

clock_init
                xor   a
                ld    (sw_sec),a
                ld    (sw_min),a
                ld    (sw_hour),a
                ld    (clk_frames),a
                call  rtc_detect
                call  read_time
                ld    hl,time_str
                ld    de,clk_shown
                ld    bc,6
                ldir
                ret
rtc_detect
                ld    e,#5A
                call  rtc_nvram_rw
                cp    #5A
                jr    nz,rd_none
                ld    e,#A5
                call  rtc_nvram_rw
                cp    #A5
                jr    nz,rd_none
                ld    a,1
                ld    (have_rtc),a
                ret
rd_none
                xor   a
                ld    (have_rtc),a
                ret
rtc_nvram_rw                                   ; E = value -> A = read-back of NVRAM 0x0E
                ld    a,#0E
                ld    bc,RTC_ADDR
                out   (c),a
                ld    bc,RTC_DATA
                out   (c),e
                ld    a,#0E
                ld    bc,RTC_ADDR
                out   (c),a
                ld    bc,RTC_DATA
                in    a,(c)
                ret
read_rtc_reg                                   ; A = reg -> A = value
                ld    bc,RTC_ADDR
                out   (c),a
                ld    bc,RTC_DATA
                in    a,(c)
                ret
read_time                                      ; -> time_str "HH:MM"
                ld    a,(have_rtc)
                or    a
                jr    z,rt_soft
                ld    a,#04
                call  read_rtc_reg
                ld    (rt_h),a
                ld    a,#02
                call  read_rtc_reg
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
put_bcd2                                        ; A = BCD -> two digits at (DE)
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
bin_to_bcd                                      ; A (0..99) -> packed BCD
                ld    b,#FF
btb_loop
                inc   b
                sub   10
                jr    nc,btb_loop
                add   a,10
                ld    c,a
                ld    a,b
                rlca
                rlca
                rlca
                rlca
                or    c
                ret
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
clk_changed                                     ; Z if time_str == clk_shown (5 chars)
                ld    hl,time_str
                ld    de,clk_shown
                ld    b,5
ckc_loop
                ld    a,(de)
                cp    (hl)
                ret   nz
                inc   hl
                inc   de
                djnz  ckc_loop
                xor   a
                ret

; fmt_mem: HL = total KB -> mem_str as "<decimal>K".
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
                ld    a,l
                add   a,'0'
                ld    (ix+0),a
                ld    (ix+1),'K'
                ld    (ix+2),0
                ret
fm_digit
                ld    a,#FF
fmd_loop
                inc   a
                or    a
                sbc   hl,de
                jr    nc,fmd_loop
                add   hl,de
                or    a
                jr    nz,fmd_emit
                ld    a,(fm_lead)
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

; mem_detect: count present 64K expansion banks (port &7F00 value &C4+bank*8
; pages a bank's block 0 into #4000-#7FFF). MUST run resident and BEFORE
; PAGE_DATA is populated (it pokes every bank's #4000). Returns A = bank count.
mem_detect
                ld    hl,(#4000)
                ld    (md_save),hl
                ld    d,0
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
                ld    bc,#7FC0
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
                call  md_valid
                jr    z,md_next
                ld    hl,md_count
                inc   (hl)
                call  md_update
md_next
                inc   d
                ld    a,d
                cp    8
                jr    nz,md_detect
                ld    bc,#7FC0
                out   (c),c
                ld    hl,(md_save)
                ld    (#4000),hl
                ld    a,(md_count)
                ret
md_port
                ld    a,d
                add   a,a
                add   a,a
                add   a,a
                or    #C4
                or    e
                ld    l,a
                ret
md_valid
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
md_update
                ld    a,#FF
                ld    (#4000),a
                ld    (#4001),a
                ld    (md_last),a
                ld    (md_last+1),a
                ret

mem_str         defs  8
fm_lead         db    0
time_str        defs  6
clk_shown       defs  6
sw_sec          db    0
sw_min          db    0
sw_hour         db    0
clk_frames      db    0
have_rtc        db    0
rt_h            db    0
rt_m            db    0
md_save         dw    0
md_count        db    0
md_last         dw    0

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
dtp_img         incbin "../build/DESKTOP.RAW"   ; packaged on the disk as DESKTOP.BIN
dtp_imgend
app_img         incbin "../build/FILEMGR.RAW"   ; packaged on the disk as FILEMGR.BIN
app_imgend
vwr_img         incbin "../build/VIEWER.RAW"    ; packaged on the disk as VIEWER.BIN
vwr_imgend
font_img        incbin "../build/DEFAULT.FNT"   ; packaged on the disk as DEFAULT.FNT
font_imgend
icon_img        incbin "../build/DEFAULT.IST"   ; packaged on the disk as DEFAULT.IST
icon_imgend
                save  "GBKERN.BIN",GB_KERNEL,kern_end-GB_KERNEL,DSK,"build/gbkern.dsk"
                save  "DESKTOP.BIN",dtp_img,dtp_imgend-dtp_img,DSK,"build/gbkern.dsk"
                save  "FILEMGR.BIN",app_img,app_imgend-app_img,DSK,"build/gbkern.dsk"
                save  "VIEWER.BIN",vwr_img,vwr_imgend-vwr_img,DSK,"build/gbkern.dsk"
                save  "DEFAULT.FNT",font_img,font_imgend-font_img,DSK,"build/gbkern.dsk"
                save  "DEFAULT.IST",icon_img,icon_imgend-icon_img,DSK,"build/gbkern.dsk"
                save  "build/GBKERN.RAW",GB_KERNEL,kern_end-GB_KERNEL
