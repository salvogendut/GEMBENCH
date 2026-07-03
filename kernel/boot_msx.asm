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

; msx_wait_tick: pace to the frame interrupt - wait for MSX_TICK to change
; (the H.TIMI handler in the page-3 glue increments it every VBLANK).
; PRESERVES DE/HL like the CPC's MC_WAIT_FLYBACK - k_poll carries the pointer
; target through this call (the M1 "pointer pinned to the bottom" bug).
msx_wait_tick
                push  hl
                ld    a,(MSX_TICK)
mwt_wait
                ei
                halt
                ld    hl,MSX_TICK
                cp    (hl)
                jr    z,mwt_wait
                pop   hl
                ret
