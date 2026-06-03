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

SCR_SET_MODE    equ   #BC0E
TXT_OUTPUT      equ   #BB5A

                include "../lib/gbapp.inc"

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

; ---------------------------------------------------------------------------
kernel_main
                ld    a,1
                call  SCR_SET_MODE           ; mode 1, screen cleared
                call  fs_init                ; pick storage backend (floppy here)
                call  font_init              ; load the font into PAGE_DATA
                call  app_launch             ; load HELLO.BIN into PAGE_APP0, run it
km_halt
                jr    km_halt                 ; freeze on the result

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
                call  APP_BASE               ; run the app from its page
                call  bank_normal
                ei
                ret
al_fail
                call  bank_normal
                ei
                ld    hl,msg_fail
                jp    k_print

app_name        db    "HELLO   BIN"          ; 8.3, space-padded
msg_boot        db    "GEOBENCH KERNEL (banked)",13,10,0
msg_back        db    "BACK IN KERNEL - APP RETURNED",13,10,0
msg_fail        db    "APP LOAD FAILED",13,10,0

                include "../lib/screen.asm"
                include "../lib/text.asm"
                include "../lib/fs.asm"
                include "../lib/fs_ide_fat.asm"
                include "../lib/fs_amsdos.asm"
                include "../lib/bank.asm"

hello_img       incbin "../build/HELLO.RAW"     ; packaged onto the disk as HELLO.BIN
hello_end
font_img        incbin "../build/DEFAULT.FNT"   ; packaged onto the disk as DEFAULT.FNT
font_end
kern_end
                save  "GBKERN.BIN",GB_KERNEL,kern_end-GB_KERNEL,DSK,"build/gbkern.dsk"
                save  "HELLO.BIN",hello_img,hello_end-hello_img,DSK,"build/gbkern.dsk"
                save  "DEFAULT.FNT",font_img,font_end-font_img,DSK,"build/gbkern.dsk"
                save  "build/GBKERN.RAW",GB_KERNEL,kern_end-GB_KERNEL
