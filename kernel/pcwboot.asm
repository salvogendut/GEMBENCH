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
; non-DMA) to load a raw system image from the reserved tracks and
; jumps to it.  Loader parameters live in the spare disc-spec bytes,
; patched by tools/mkpcwdsk.py:
;
;   spec[10]    payload sector count
;   spec[11]    load address high byte (page-aligned load)
;   spec[12:14] entry address, little-endian
;   spec[15]    checksum filler (sum of sector mod 256 == #FF)
;
; REAL-HARDWARE protocol (#331, learned by diffing against a CP/M 3
; boot sector + the MCU bootstrap, both proven on a physical 8256):
;   - the uPD765's MSR stays STALE for ~12us after each command byte
;     written or result byte read: every such access is followed by an
;     EX (SP),HL settle chain before the next MSR poll, or the next
;     poll sees the old RQM and double-feeds/double-reads (the corrupt
;     commands behind the original real-HW boot failure - the emulator
;     updates MSR instantly and never showed it)
;   - seek/recalibrate completion = poll the ASIC's live FDC INTRQ
;     mirror (port #F8 read, bit 5), THEN acknowledge with a single
;     SENSE INTERRUPT - never hammer SENSE INT during a seek
;   - reads use the CP/M shape: TC clear (#F8 cmd 6) before the
;     command, READ DATA #66 (MFM+SK) with EOT=9, TC set (cmd 5) right
;     after the payload bytes, then wait INTRQ and read the results
;   - the transfer loop must beat the ~32us MFM byte window: INI with
;     the count in B (2 x 256), two ADDs + JP P for the EXM test
;
; Diagnosis beacons (zero disk I/O - a minimal roller table pointing
; every scanline at one shared cellrow):
;   fine stripes  #0F  boot code is executing
;   sparse stripes#03  a sector read hard-failed; ST0/ST1/ST2 are
;                      painted as 8 bit-blocks (lit = 1) and the
;                      machine freezes with the evidence up
;   solid lit     #FF  kernel image loaded, jumping
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
        call beacon
        ld a,4
        out (#F8),a             ; FDC interrupt routing: disabled (we poll
                                ; the raw INTRQ mirror on #F8 bit 5)
        ld a,9
        out (#F8),a             ; motor on (the bootstrap left it on)
        ld a,6
        out (#F8),a             ; terminal count: clear

        ld hl,cmd_spec          ; SPECIFY: timings + ND=1 (polled)
        ld b,3
        call fdc_send
        ld hl,cmd_rcal          ; RECALIBRATE to track 0
        ld b,2
        call fdc_send
        call wait_seek          ; INTRQ mirror, then one SENSE INT

        ld a,(ld_page)          ; running destination pointer
        ld h,a
        ld l,0
        ld (dest),hl

; One sector per READ command, CP/M-style: EOT stays 9 so the FDC keeps
; streaming into the inter-sector gap while we assert TC - the real chip
; gets its termination slack that way. Track 0 starts at R=2.
sec_loop:
        ld a,(ld_secs)          ; remaining sectors
        or a
        jp z,go
        dec a
        ld (ld_secs),a
        ld a,4                  ; attempts per sector
        ld (retry),a
sec_try:
        ld a,6
        out (#F8),a             ; TC clear before the command
        ld a,(cur_trk)
        ld (rd_c),a             ; command C = physical track
        ld a,(cur_r)
        ld (rd_r),a             ; command R = this sector (EOT stays 9)
        ld hl,rd_cmd            ; READ DATA #66, 9 command bytes
        ld b,9
        call fdc_send
        ld hl,(dest)
        ld c,1                  ; FDC data register for INI
        ld d,2                  ; 512 bytes = 2 x 256, count in B
rx_half:
        ld b,0
rx:
        in a,(0)                ; MSR
        add a,a                 ; bit7 RQM -> carry
        jr nc,rx
        add a,a                 ; bit5 EXM -> bit7
        jp p,rx_bad             ; result phase early = failed
        ini
        jr nz,rx
        dec d
        jr nz,rx_half
        ld a,5                  ; payload in: terminal count
        out (#F8),a
        ld a,6
        out (#F8),a
        push hl                 ; fdc_result walks st_buf in HL - keep the
        call fdc_result         ; advanced destination pointer!
        pop hl
        and #88                 ; fatal IC (invalid/ready-change) or NR only:
                                ; EN alone is normal for a TC-run command
        jr nz,rx_bad
        ld (dest),hl            ; commit the sector
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

rx_bad:
        call fdc_result         ; keep ST0/1/2 for the diagnosis
        ld hl,cmd_rcal          ; re-home + re-seek: real mechanics may
        ld b,2                  ; need it (the emulator never does)
        call fdc_send
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
        ld a,#03                ; BEACON C: sparse stripes = "reads failed",
        call beacon             ; with ST0/ST1/ST2 painted as bit blocks
        ld a,(st_buf)
        ld d,a
        ld hl,#4400             ; ST0 -> lines 0-1
        call st_row
        ld a,(st_buf+1)
        ld d,a
        ld hl,#4403             ; ST1 -> lines 3-4
        call st_row
        ld a,(st_buf+2)
        ld d,a
        ld hl,#4406             ; ST2 -> lines 6-7
        call st_row
bc_halt:
        jr bc_halt              ; freeze with the evidence up

go:
        ld a,#FF                ; BEACON B: solid = "kernel loaded, jumping"
        call beacon             ; (the kernel's video init repaints at once)
        ld hl,(ld_entry)        ; motor stays on - the kernel reads system
        jp (hl)                 ; files immediately (fs_init re-inits FDC)

; ---- FDC helpers (real-chip MSR settle discipline) ----------------------

; send B command bytes from (HL): RQM-gated, with the settle chain after
; every byte so the next MSR poll is fresh (the double-feed bug otherwise)
fdc_send:
        in a,(0)
        add a,a                 ; RQM -> carry
        jr nc,fdc_send
        ld a,(hl)
        out (1),a
        inc hl
        ex (sp),hl              ; ~76 T settle before the next MSR poll
        ex (sp),hl
        ex (sp),hl
        ex (sp),hl
        djnz fdc_send
        ret

; send the single command byte in A (same discipline)
fdc_send1:
        push af
fs1:    in a,(0)
        add a,a
        jr nc,fs1
        pop af
        out (1),a
        ex (sp),hl
        ex (sp),hl
        ex (sp),hl
        ex (sp),hl
        ret

; read one result byte -> A (settle after the read)
fdc_res:
        in a,(0)
        add a,a
        jr nc,fdc_res
        in a,(1)
        ex (sp),hl
        ex (sp),hl
        ex (sp),hl
        ex (sp),hl
        ret

; fdc_result: wait for the command-end INTRQ (the ASIC mirrors the raw
; line on #F8 bit 5), then read every result byte into st_buf. A = ST0.
fdc_result:
        in a,(#F8)
        and #20
        jr z,fdc_result
        ld hl,st_buf
        ld b,7
fres:
        in a,(0)
        bit 4,a                 ; command over (CB clear)?
        jr z,fres_done
        add a,a                 ; RQM?
        jr nc,fres
        in a,(1)
        ld (hl),a
        inc hl
        ex (sp),hl              ; settle before the next MSR poll
        ex (sp),hl
        ex (sp),hl
        ex (sp),hl
        djnz fres
fres_done:
        ld a,(st_buf)
        ret

; after RECALIBRATE/SEEK: wait for the INTRQ mirror, then acknowledge with
; ONE SENSE INTERRUPT (never hammered during the seek - real-chip rule)
wait_seek:
        in a,(#F8)
        and #20                 ; live FDC INTRQ
        jr z,wait_seek
        ld a,8                  ; SENSE INTERRUPT STATUS (the acknowledge)
        call fdc_send1
        call fdc_res            ; ST0
        cp #80                  ; spurious/no-op race: wait again
        jr z,wait_seek
        ld b,a
        call fdc_res            ; PCN, discard
        bit 5,b                 ; seek end?
        jr z,wait_seek
        ret

; ---- beacon: whole-screen pattern with NO disk I/O ----------------------
; Minimal roller table at phys #4200 (512-aligned, slot-1 identity RAM):
; every scanline points at the SAME 8-line cellrow at phys #4400 (roller
; word = #2200 | line), so filling 720 bytes paints the whole display.
beacon:
        ld c,a                  ; C = pattern byte
        ld hl,#4200             ; 256 roller words
        ld b,0
        ld e,0
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

; st_row: D = a status byte -> 8 bit-blocks (bit7 leftmost, lit = 1) on
; beacon-cellrow lines HL and HL+1. Blocks are 10 columns, columns 8 apart.
st_row:
        ld b,8
str_blk:
        rlc d                   ; bit7 -> carry (D restored after 8)
        ld a,#00
        jr nc,str_v
        ld a,#FF
str_v:
        push bc
        ld c,a
        ld b,10
str_col:
        ld (hl),c
        inc hl
        ld (hl),c               ; the line below too (2-line bar)
        dec hl
        ld a,l                  ; next column: +8
        add a,8
        ld l,a
        jr nc,str_nc
        inc h
str_nc:
        djnz str_col
        pop bc
        djnz str_blk
        ret

; ---- command templates / state ------------------------------------------
cmd_spec:
        db #03,#0F,#FF          ; SPECIFY: timings + ND=1 (non-DMA, polled)
cmd_rcal:
        db #07,#00              ; RECALIBRATE unit 0
cmd_seek:
        db #0F,#00              ; SEEK unit 0
sk_trk: db 0                    ;   new cylinder
rd_cmd:
        db #66                  ; READ DATA, MFM + SK (the bootstrap's byte)
        db #00                  ; unit 0 head 0
rd_c:   db 0                    ;   C = cylinder
        db #00                  ;   H
rd_r:   db 2                    ;   R = first sector wanted
        db #02                  ;   N = 512
        db #09                  ;   EOT = 9: keep streaming, TC terminates
        db #2A                  ;   GPL
        db #FF                  ;   DTL

cur_trk: db 0
cur_r:   db 2
dest:    dw 0
retry:   db 0
st_buf:  ds 7

boot_end:
        assert boot_end-spec <= 512
        save"build/pcwboot.bin",#F000,boot_end-spec
