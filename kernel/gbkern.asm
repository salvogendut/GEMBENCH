; gbkern - GEOBENCH banked-kernel skeleton (Phase 1 proof).
;
; Resident at GB_KERNEL (#8000), it owns the machine and the stack and never
; lives in the #4000-#7FFF window, so it can page apps in and out. It exposes a
; fixed API jump table (see lib/gbapp.inc), loads the HELLO app into an
; expansion bank, runs it there, and regains control when the app returns.
;
; This skeleton becomes the real desktop kernel later; for now it proves the
; load/run/return cycle with on-screen evidence.
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
                ld    hl,msg_boot
                call  k_print
                call  app_load               ; copy HELLO into bank 0
                call  app_run                ; page it in, run it, restore
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

; --- app loading / running -----------------------------------------------
; app_load: page expansion bank 0 in and copy the embedded HELLO image to
; APP_BASE, then restore normal RAM.
app_load
                di
                xor   a                        ; bank 0
                ld    c,0                       ; block 0
                call  bank_page
                ld    hl,hello_img             ; source: resident (>=#8000), mapped
                ld    de,APP_BASE              ; dest: the bank window
                ld    bc,hello_end-hello_img
                ldir
                call  bank_normal
                ei
                ret

; app_run: page bank 0 in and CALL the app; it runs from the bank and reaches
; the kernel API directly (resident). Restore normal RAM when it returns.
app_run
                di
                xor   a
                ld    c,0
                call  bank_page
                call  APP_BASE
                call  bank_normal
                ei
                ret

msg_boot        db    "GEOBENCH KERNEL (banked)",13,10,0
msg_back        db    "BACK IN KERNEL - APP RETURNED",13,10,0

hello_img       incbin "../build/HELLO.RAW"     ; the app, built first
hello_end

                include "../lib/bank.asm"
kern_end
                save  "GBKERN.BIN",GB_KERNEL,kern_end-GB_KERNEL,DSK,"build/gbkern.dsk"
                save  "build/GBKERN.RAW",GB_KERNEL,kern_end-GB_KERNEL
