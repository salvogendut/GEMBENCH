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
                jp    gb_text_draw           ; GB_TEXT  #800C

; ---------------------------------------------------------------------------
kernel_main
                ld    a,1
                call  SCR_SET_MODE           ; mode 1, screen cleared
                call  fs_init                ; pick storage backend (floppy here)
                call  font_init              ; load the font into PAGE_DATA
                ld    hl,msg_boot
                call  k_print
                call  app_launch             ; load HELLO.BIN into PAGE_APP0, run it
                ld    hl,msg_back
                call  k_print
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
