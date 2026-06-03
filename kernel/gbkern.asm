; gbkern - GEOBENCH banked-kernel skeleton (Phase 1/2 proof).
;
; Resident at GB_KERNEL (#8000), it owns the machine and the stack and never
; lives in the #4000-#7FFF window, so it can page apps and its own data buffers
; in and out. It exposes a fixed API jump table (see lib/gbapp.inc), loads a
; real app binary off disk into PAGE_APP0, runs it there, and regains control
; when the app returns.
;
; This build also proves the "bank the buffers" model: the kernel keeps a data
; buffer in PAGE_DATA (a different 16K block of bank 0 than the app), and a
; service (gb_print_data) reaches it from inside an app call by saving the
; caller's page, swapping to PAGE_DATA, and restoring afterwards.
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
                jp    gb_print_data          ; GB_PDATA #800C

; ---------------------------------------------------------------------------
kernel_main
                ld    a,1
                call  SCR_SET_MODE           ; mode 1, screen cleared
                call  fs_init                ; pick storage backend (floppy here)
                call  data_init              ; seed the PAGE_DATA buffer
                ld    hl,msg_boot
                call  k_print
                call  app_launch             ; load HELLO.BIN into PAGE_APP0, run it
                ld    hl,msg_back
                call  k_print
km_halt
                jr    km_halt                 ; freeze on the result

; --- API implementations -------------------------------------------------
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

; gb_print_data: print the string in the kernel's PAGE_DATA buffer, preserving
; the caller's page. This is the banked-buffer service pattern in miniature.
gb_print_data
                ld    a,(bank_cur)           ; remember the caller's page
                ld    (gpd_save),a
                ld    a,PAGE_DATA            ; swap to the kernel data page
                call  bank_set
                ld    hl,DATA_BUF
                call  k_print                ; read+print from the data page
                ld    a,(gpd_save)           ; restore the caller's page
                jp    bank_set
gpd_save        db    0

; --- kernel data (PAGE_DATA) ---------------------------------------------
; data_init: seed the data-page buffer with a marker string.
data_init
                di
                ld    a,PAGE_DATA
                call  bank_set
                ld    hl,databuf_src
                ld    de,DATA_BUF
                ld    bc,databuf_end-databuf_src
                ldir
                call  bank_normal
                ei
                ret
databuf_src     db    "BANKED BUFFER OK",13,10,0
databuf_end

; --- app launch ----------------------------------------------------------
; app_launch: page PAGE_APP0 in, load the named app file directly into the
; #4000-#7FFF window, then CALL it. The app reaches the kernel API directly
; (resident). Restore normal RAM after it returns.
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

                include "../lib/fs.asm"
                include "../lib/fs_ide_fat.asm"
                include "../lib/fs_amsdos.asm"
                include "../lib/bank.asm"

hello_img       incbin "../build/HELLO.RAW"     ; packaged onto the disk as HELLO.BIN
hello_end
kern_end
                save  "GBKERN.BIN",GB_KERNEL,kern_end-GB_KERNEL,DSK,"build/gbkern.dsk"
                save  "HELLO.BIN",hello_img,hello_end-hello_img,DSK,"build/gbkern.dsk"
                save  "build/GBKERN.RAW",GB_KERNEL,kern_end-GB_KERNEL
