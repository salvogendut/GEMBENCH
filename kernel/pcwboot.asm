; -----------------------------------------------------------------------
; pcwboot.asm - GEOBENCH boot sector for the Amstrad PCW 8256/8512 (#331)
;
; The PCW has no ROM: at power-on the printer-controller MCU shifts a
; 275-byte bootstrap into low RAM, which reads track 0 / sector R=1
; (this sector, 512 bytes) to #F000, checks that the 8-bit sum of the
; whole sector is #FF, and jumps to #F010 - just past the 16-byte PCW
; disc specification that starts the sector.
;
; This boot sector then drives the uPD765A FDC directly (polled,
; non-DMA - there is no OS and no DMA controller) to load a raw system
; image from the reserved tracks (T0/R2..R9, then whole tracks) and
; jumps to it.  Loader parameters live in the spare disc-spec bytes and
; are patched by tools/mkpcwdsk.py:
;
;   spec[10]    payload sector count
;   spec[11]    load address high byte (page-aligned load)
;   spec[12:14] entry address, little-endian
;   spec[15]    checksum filler (sum of sector mod 256 == #FF)
;
; Hardware used (see docs/PCW.md):
;   FDC  in/out port #00 = main status register, #01 = data register
;   #F8  system control:  04 = FDC irq off (we poll)   09/0A = motor
;                         05/06 = terminal count high/low
;
; Assemble: rasm kernel/pcwboot.asm   (saves build/pcwboot.bin)
; -----------------------------------------------------------------------

        org #F000

; ---- 16-byte PCW disc specification (XBIOS reads [0..9]) --------------
spec:
        db 0                    ; [0] format: SS 180K
        db 0                    ; [1] sided
        db 40                   ; [2] tracks per side
        db 9                    ; [3] sectors per track
        db 2                    ; [4] psh (512-byte sectors)
        db 1                    ; [5] OFF reserved tracks (patched)
        db 3                    ; [6] BSH (1K blocks)
        db 2                    ; [7] directory blocks
        db #2A                  ; [8] GAP3 read/write
        db #52                  ; [9] GAP3 format
ld_secs: db 0                   ; [10] payload sectors      (patched)
ld_page: db #10                 ; [11] load address hi byte (patched)
ld_entry: dw #1000              ; [12] entry address        (patched)
        db 0                    ; [14] spare
        db 0                    ; [15] checksum filler      (patched)

; ---- entry (#F010) -----------------------------------------------------
entry:
        di
        ld sp,#F000             ; stack just below this sector
        ld a,#0F                ; BEACON A: fine stripes = "boot code runs"
        call beacon             ; (real-HW diagnosis, #331: the pattern on
                                ; screen tells which stage died)
        ld a,4
        out (#F8),a             ; route FDC interrupt: disabled (poll)
        ld a,9
        out (#F8),a             ; motor on (bootstrap left it on; be sure)

        ld hl,cmd_init          ; SPECIFY (non-DMA) + RECALIBRATE,
        ld b,5                  ; streamed back-to-back (neither has a
        call fdc_send           ; result phase)
        call wait_seek          ; poll SENSE INTERRUPT until seek end

        ld a,(ld_page)          ; running destination pointer
        ld h,a
        ld l,0
        ld (dest),hl

; One READ DATA command per sector (R = EOT): the FDC - real PCW CP/M
; workloads and the 1985 model alike - delivers a single sector per
; command in this polled non-DMA setup, so multi-sector reads are not
; used.  Track 0 starts at R=2 (R=1 is this boot sector).
sec_loop:
        ld a,(ld_secs)          ; remaining sectors
        or a
        jp z,go
        dec a
        ld (ld_secs),a
        ld a,3                  ; attempts per sector (real drives can
        ld (retry),a            ; drop a revolution; the emulator never)
sec_try:
        ld a,(cur_trk)
        ld (rd_c),a             ; command C = physical track
        ld a,(cur_r)
        ld (rd_r),a             ; command R = EOT = this sector
        ld (rd_eot),a

        ld hl,rd_cmd            ; READ DATA, 9 command bytes
        ld b,9
        call fdc_send
        ld hl,(dest)
        ld c,1                  ; FDC data register for INI
        ld d,2                  ; 512 bytes = 2 x 256, count in B: the
rx_half:                        ; loop must beat the ~32us MFM byte
        ld b,0                  ; window on real hardware (boot-ROM form)
rx:
        in a,(0)                ; main status register
        add a,a                 ; bit7 RQM -> carry
        jr nc,rx
        add a,a                 ; bit6 DIO
        add a,a                 ; bit5 EXM -> carry
        jr nc,rx_bad            ; result phase early = overrun/miss
        ini                     ; (HL) <- data reg, HL++, B--
        jr nz,rx
        dec d
        jr nz,rx_half
        ld a,5                  ; all bytes in: pulse terminal count so
        out (#F8),a             ; the FDC ends the command cleanly
        ld a,6
        out (#F8),a
        call fdc_drain          ; swallow the 7 result bytes
        ld (dest),hl            ; commit the sector

        jr sec_next
rx_bad:
        call fdc_drain          ; failed: drain, re-home + re-seek (real
        ld hl,cmd_init+3        ; mechanics may need it), leave dest as it
        ld b,2                  ; was, and re-read the same sector
        call fdc_send           ; (cmd_init+3 = the RECALIBRATE pair)
        call wait_seek
        ld a,(cur_trk)
        or a
        jr z,rb_home
        ld (sk_trk),a
        ld hl,cmd_seek
        ld b,3
        call fdc_send
        call wait_seek
rb_home:
        ld a,(retry)
        dec a
        ld (retry),a
        jp nz,sec_try
        ld a,#03                ; BEACON C: sparse stripes = "reads failed";
        call beacon             ; freeze with the evidence on screen instead
bc_halt:
        jr bc_halt              ; of blink-looping through reboots
sec_next:
        ld a,(cur_r)            ; advance sector; past R=9 -> next track
        inc a
        cp 10
        jr c,same_trk
        ld a,(cur_trk)
        inc a
        ld (cur_trk),a
        ld (sk_trk),a
        ld hl,cmd_seek          ; SEEK to the new track
        ld b,3
        call fdc_send
        call wait_seek
        ld a,1                  ; restart at R=1
same_trk:
        ld (cur_r),a
        jp sec_loop

go:
        ld a,#FF                ; BEACON B: solid lit = "kernel loaded, jumping"
        call beacon             ; (the kernel's own video init repaints at once)
        ld hl,(ld_entry)        ; motor stays on - the kernel starts reading
                                ; system files immediately (fs_init re-inits FDC)
        jp (hl)

; ---- beacon: whole-screen pattern with NO disk I/O ----------------------
; Minimal roller table at phys #4200 (512-aligned, slot-1 identity RAM):
; every scanline points at the SAME 8-line cellrow at phys #4400 (roller
; word = #2200 | line), so filling 720 bytes paints the whole display.
beacon:
        ld c,a                  ; C = pattern byte
        ld hl,#4200             ; 256 roller words
        ld b,0
        ld e,0                  ; line counter
bk_tab:
        ld a,e
        and 7
        ld (hl),a               ; low byte = line (word base #2200)
        inc hl
        ld a,#22
        ld (hl),a
        inc hl
        inc e
        djnz bk_tab
        ld hl,#4400             ; the shared cellrow
        ld de,720
bk_fill:
        ld (hl),c
        inc hl
        dec de
        ld a,d
        or e
        jr nz,bk_fill
        ld a,#21                ; roller base = phys #4200
        out (#F5),a
        xor a
        out (#F6),a             ; scroll 0
        ld a,#40
        out (#F7),a             ; screen enable, normal video
        ld a,7
        out (#F8),a             ; display on
        ret

; ---- FDC helpers -------------------------------------------------------

; send B command bytes from (HL), waiting for RQM before each
fdc_send:
        in a,(0)
        add a,a                 ; RQM -> carry
        jr nc,fdc_send
        ld a,(hl)
        out (1),a
        inc hl
        djnz fdc_send
        ret

; send the single command byte in A
fdc_send1:
        push af
fs1:    in a,(0)
        add a,a
        jr nc,fs1
        pop af
        out (1),a
        ret

; read one result byte -> A
fdc_res:
        in a,(0)
        add a,a
        jr nc,fdc_res
        in a,(1)
        ret

; discard result bytes until the FDC goes idle
fdc_drain:
        in a,(0)
        bit 4,a                 ; command busy?
        ret z
        add a,a                 ; RQM?
        jr nc,fdc_drain
        in a,(1)                ; result byte, discard
        jr fdc_drain

; after RECALIBRATE/SEEK: poll SENSE INTERRUPT STATUS until seek end
wait_seek:
        ld a,8                  ; SENSE INTERRUPT STATUS
        call fdc_send1
        call fdc_res            ; ST0
        cp #80                  ; invalid = no interrupt pending yet
        jr z,wait_seek
        ld b,a
        call fdc_res            ; PCN, discard
        bit 5,b                 ; ST0 seek-end?
        jr z,wait_seek
        ret

; ---- command templates / state ------------------------------------------
cmd_init:
        db #03,#0F,#FF          ; SPECIFY: timings + ND=1 (non-DMA, polled)
        db #07,#00              ; RECALIBRATE unit 0
cmd_seek:
        db #0F,#00              ; SEEK unit 0
sk_trk: db 0                    ;   new cylinder
rd_cmd:
        db #46                  ; READ DATA, MFM
        db #00                  ; unit 0 head 0
rd_c:   db 0                    ;   C = cylinder
        db #00                  ;   H
rd_r:   db 2                    ;   R = first sector
        db #02                  ;   N = 512
rd_eot: db 9                    ;   EOT = last sector
        db #2A                  ;   GPL
        db #FF                  ;   DTL

cur_trk: db 0
cur_r:   db 2
dest:    dw 0
retry:   db 0

boot_end:
        assert boot_end-spec <= 512
        save"build/pcwboot.bin",#F000,boot_end-spec
