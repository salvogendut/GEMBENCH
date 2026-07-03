; kernel/boot_msx.asm - GEOBENCH boot/exit flow for the MSX2 target (#287).
;
; The MSX counterpart of kernel/boot.asm, included immediately after the fixed
; API table so kernel_main stays the GB_INIT target and k_exit the GB_EXIT
; target. The bootstrap stub (kernel/msx_stub.asm) has already: verified DOS 2,
; captured the mapper support routines + TPA page-1 segment into the page-3
; glue, copied this kernel to #8000, hooked H.TIMI, run CHGMOD 6 and set
; SP = MSX_STACK_TOP. GB_EXIT unwinds all of that and _TERMs back to the
; DOS prompt.

kernel_main
                ld    (BOOT_SP),sp           ; entry SP, for GB_EXIT's longjmp
                ld    hl,0                    ; empty the shared clipboard (#142)
                ld    (CLIP_LEN),hl
                xor   a                       ; UI_MODAL boots as TPA garbage under DOS
                ld    (UI_MODAL),a           ; (menu_dispatch would swallow EVERY top-bar
                                              ; click as "a dialog is up", #287)
                call  msx_video_init         ; 212 lines, 16x16 sprites, parked pointer
                ld    hl,pal_def             ; seed the default inks (GBCFG may rewrite
                ld    de,KCFG_INKS           ; KCFG_INKS from INKS= later)
                ld    bc,5
                ldir
                ld    a,1                     ; solid backdrop until BACKDROP= says else
                ld    (BD_SOLID),a
                call  set_palette
                call  k_cls                   ; pen-0 desktop while loading
                call  fs_init
                call  input_init
                call  msx_mem_init           ; PAGE_DATA segment + KCFG_MEMKB
                call  cfg_boot               ; parse GEOBENCH.CFG (paged C module)
                call  set_palette            ; re-apply now KCFG_INKS holds INKS=
                call  clip_set_full          ; boot clip rect = full screen (#273)
                call  assets_load            ; font + icons + cursor + backdrop
                call  clock_init
                ld    hl,WM_NWIN            ; clear WM low-RAM state
                ld    de,WM_NWIN+1
                ld    bc,WM_Z+WM_MAXWIN-WM_NWIN-1
                ld    (hl),0
                ldir
                call  app_pool_init
                ld    a,#FF
                ld    (WM_FPREV),a
                ld    hl,kern_end-GB_KERNEL
                ld    (GB_KSIZE),hl
                ifdef GB_FSTEST              ; #287: deterministic BDOS write-path self-test.
                call  msx_fstest             ; save GBTEST.TXT, then _TERM so the host can
                jp    km_finish              ; mount the image and check it - no desktop.
                endif
                ifdef GB_FILLTEST            ; #287: fill 4 bands pens 0-3 via k_fill, hang.
                ld    b,0                     ; B = pen
gft_band        push  bc
                ld    a,b                     ; pen
                push  af
                ld    c,b                     ; y = pen*48
                ld    a,b
                add   a,a
                add   a,a
                add   a,a                     ; *8
                ld    e,a
                add   a,a                     ; *16
                add   a,a                     ; *32... want *48 = *32 + *16
                add   a,e                     ; a = pen*48
                ld    c,a                     ; C = y
                ld    b,0                     ; B = x
                ld    d,128                   ; D = w (full width)
                ld    e,48                    ; E = h
                pop   af                      ; A = pen
                call  k_fill
                pop   bc
                inc   b
                ld    a,b
                cp    4
                jr    c,gft_band
gft_hang        jr    gft_hang
                endif
                ld    hl,name_desktop
                call  launch_app             ; the WM master loop never returns
km_finish                                      ; reached by k_exit's longjmp
                di
                ld    hl,MSX_HOOKSAVE        ; restore the original H.TIMI hook
                ld    de,H_TIMI
                ld    bc,5
                ldir
                ei
                call  msx_free_segments      ; hand every ALL_SEG segment back to DOS
                ld    ix,INITXT              ; text mode for the DOS prompt
                call  msx_bios
                ld    c,_TERM0               ; clean exit to COMMAND2
                jp    BDOS

                ifdef GB_FSTEST
; msx_fstest (#287): exercise the BDOS write path exactly as gb_fs_save/the
; Notepad save would - fs_save_file creates GBTEST.TXT in the CWD (root) with a
; known payload; then fs_delete_file removes a scratch file to prove _DELETE.
; The host build script mounts the image afterward and checks the content.
msx_fstest
                ld    hl,fstest_name         ; fs_req_name = "GBTEST  TXT"
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    hl,fstest_data         ; save the payload
                ld    (fs_save_src),hl
                ld    hl,fstest_len
                ld    (fs_save_len),hl
                call  fs_save_file
                ret
fstest_name     db    "GBTEST  TXT"
fstest_data     db    "GEOBENCH MSX2 write path OK",13,10
fstest_len      equ   $-fstest_data
                endif

; k_exit (GB_EXIT): longjmp out of the nested WM call chain, then unwind.
k_exit
                di
                call  bank_normal            ; TPA segment back at #4000-#7FFF
                ld    sp,(BOOT_SP)
                jp    km_finish
name_desktop    db    "DESKTOP APP"

; msx_mem_init: allocate the PAGE_DATA segment and publish the RAM size.
; No free segment is fatal - GEOBENCH cannot run without its data page, so
; report and exit cleanly rather than limp.
msx_mem_init
                xor   a                       ; ALL_SEG: A=0 user segment, B=0 any mapper
                ld    b,a
                ld    hl,(MSX_ALLSEG)
                call  jp_hl
                jr    c,mmi_fatal
                ld    (MSX_PAGE_DATA),a
                ld    a,(MSX_TOTSEG)         ; KCFG_MEMKB = total segments * 16
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    (KCFG_MEMKB),hl
                ret
mmi_fatal
                ld    sp,(BOOT_SP)           ; no segment for PAGE_DATA -> back to DOS
                ld    ix,INITXT
                call  msx_bios
                ld    c,_TERM0
                jp    BDOS

; app_pool_init: APP_PAGES[0] = the TPA's own page-1 segment (the desktop rides
; it for free), then ALL_SEG until the pool is full or DOS runs dry. On a stock
; 128K machine that yields 1 window (the desktop) + whatever DOS left over.
app_pool_init
                ld    hl,APP_PAGES
                ld    a,(MSX_TPASEG)
                ld    (hl),a
                inc   hl
                ld    c,1                     ; C = entries so far
api_more
                ld    a,c
                cp    WM_MAXWIN
                jr    nc,api_done
                push  hl
                push  bc
                xor   a                       ; ALL_SEG a user segment
                ld    b,a
                ld    hl,(MSX_ALLSEG)
                call  jp_hl
                pop   bc
                pop   hl
                jr    c,api_done             ; DOS has no more -> pool complete
                ld    (hl),a
                inc   hl
                inc   c
                jr    api_more
api_done
                ld    a,c
                ld    (APP_NPAGES),a
                ld    hl,APP_BUSY            ; mark every page free
                ld    de,APP_BUSY+1
                ld    bc,WM_MAXWIN-1
                ld    (hl),0
                ldir
                ret

; msx_free_segments: FRE_SEG the PAGE_DATA segment + every pool segment except
; APP_PAGES[0] (that one is the TPA's own). Exit path only.
msx_free_segments
                ld    a,(MSX_PAGE_DATA)
                call  mfs_free
                ld    a,(APP_NPAGES)
                or    a
                ret   z
                dec   a
                ret   z                       ; only the TPA entry
                ld    b,a                     ; B = count above [0]
                ld    hl,APP_PAGES+1
mfs_loop
                ld    a,(hl)
                push  hl
                push  bc
                call  mfs_free
                pop   bc
                pop   hl
                inc   hl
                djnz  mfs_loop
                ret
mfs_free
                ld    hl,(MSX_FRESEG)
                jp    jp_hl

; msx_wait_tick: pace k_poll to ONE true video frame by waiting for a vertical-
; retrace edge on the VDP status flag (S#2 bit6 VR), NOT the H.TIMI tick. Under
; this machine + Nextor the BIOS frame interrupt STORMS (~8x/frame), so a tick-
; counted wait let k_poll run ~8x too fast: the pointer's acceleration ramp
; maxed out instantly (uncontrollable leaps) and the idle/saver timer counted 8x
; fast (saver in ~9s). The VR flag toggles exactly once per frame regardless of
; the interrupt rate. Brief DI so the R#15 select + poll don't race the BIOS ISR
; (which needs R#15=0/S#0); R#15 restored to 0 before EI, so the one pending
; frame interrupt acks S#0 cleanly - which also tames the storm.
; PRESERVES DE/HL like the CPC's MC_WAIT_FLYBACK - k_poll carries the pointer
; target through this call (the M1 "pointer pinned to the bottom" bug). #287
msx_wait_tick
                push  hl
                di
                ld    a,2                     ; select status register S#2 (VR flag)
                out   (VDP_CTRL),a
                ld    a,15|#80
                out   (VDP_CTRL),a
mwt_indisp      in    a,(VDP_CTRL)            ; wait until out of retrace (VR = 0)
                and   #40
                jr    nz,mwt_indisp
mwt_retrace     in    a,(VDP_CTRL)            ; then wait for retrace to begin (VR 0->1)
                and   #40
                jr    z,mwt_retrace
                xor   a                        ; restore R#15 = 0 (S#0, the ISR default)
                out   (VDP_CTRL),a
                ld    a,15|#80
                out   (VDP_CTRL),a
                ei
                pop   hl
                ret
