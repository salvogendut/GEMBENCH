; gbkern - GEOBENCH banked-kernel skeleton (Phase 1 proof).
;
; Resident at GB_KERNEL (#8000), it owns the machine and the stack and never
; lives in the #4000-#7FFF window, so it can page apps in and out. It exposes a
; fixed API jump table (see lib/gbapp.inc), loads a real app binary off disk
; STRAIGHT INTO an expansion bank, runs it there, and regains control when the
; app returns.
;
; The fs layer (dispatcher + backends) is resident with the kernel, and its
; sector/dir buffers live >= #8000, so a load can write into the #4000-#7FFF
; window while a bank is paged in. The app is a separate file (HELLO.BIN) on the
; same disk - not embedded in the kernel.
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

; ---------------------------------------------------------------------------
kernel_main
                ld    a,1
                call  SCR_SET_MODE           ; mode 1, screen cleared
                call  fs_init                ; pick storage backend (floppy here)
                ld    hl,msg_boot
                call  k_print
                call  app_launch             ; load HELLO.BIN into a bank, run it
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

; --- app launch ----------------------------------------------------------
; app_launch: page expansion bank 0 in, load the named app file directly into
; the #4000-#7FFF window (fs code + buffers stay resident), then CALL it. The
; app reaches the kernel API directly (resident). Restore normal RAM after.
app_launch
                di
                xor   a                        ; bank 0
                ld    c,0                       ; block 0
                call  bank_page

                ld    hl,app_name             ; fs_req_name = "HELLO   BIN"
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    hl,#3F00               ; cap: app must fit the 16K window
                ld    (fs_load_max),hl
                ld    hl,APP_BASE             ; load straight into the bank
                ld    (fs_load_dst),hl
                call  fs_load_file
                jr    nc,al_fail

                call  APP_BASE               ; run the app from the bank
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
