; ---------------------------------------------------------------------------
; lib/pcw/fdc.asm - polled uPD765A floppy driver for the PCW target (#331).
;
; The resident graduation of kernel/pcwboot.asm's loader, following the
; REAL-CHIP protocol learned from a proven CP/M 3 boot sector + the MCU
; bootstrap (see pcwboot.asm's header):
;   - MSR settle: after every command byte written or result byte read,
;     an EX (SP),HL chain runs before the next MSR poll (the real chip's
;     status stays stale ~12us; polling early double-feeds/double-reads -
;     the emulator updates MSR instantly and never shows it)
;   - seek/recalibrate completion = the ASIC's live FDC INTRQ mirror
;     (port #F8 read, bit 5), then ONE acknowledging SENSE INTERRUPT
;   - transfers: TC clear before the command, READ #66 / WRITE #45 with
;     EOT = 9 (the FDC streams into the gap while we assert TC), TC set
;     right after the payload, then wait INTRQ and read the results
;   - the polled loops keep the count in B (2 x 256) to beat the ~32us
;     MFM byte window
;
; Ports: #00 = main status register, #01 = data register. #F8 cmds:
; 04 = FDC irq routing off (we poll the raw mirror), 05/06 = TC set/clear,
; 09 = motor on. GEOBENCH runs DI.
;
;   pcwfdc_init                     SPECIFY (ND=1) + motor + recalibrate
;   pcwfdc_setunit A=0/1            select drive (B double-steps CF2 media)
;   pcwfdc_read  D=track E=sector(1..9) HL=512-byte dest  -> CF set = ok
;   pcwfdc_read1                    one attempt, no retry (presence probe)
;   pcwfdc_write D=track E=sector(1..9) HL=512-byte src   -> CF set = ok
;
; The motor is turned on at init and left running.
; ---------------------------------------------------------------------------

pcwfdc_init
                ld    a,4
                out   (PCW_SYSCTL),a          ; irq routing off: we poll #F8 bit5
                ld    a,9
                out   (PCW_SYSCTL),a          ; motor on (stays on)
                ld    a,6
                out   (PCW_SYSCTL),a          ; terminal count clear
                ld    hl,fdc_cmd_spec         ; SPECIFY: timings + ND=1 (polled)
                ld    b,3
                call  fdc_send
                ; fall through: recalibrate = seek to a known track 0

; fdc_recal: home the head and reset the track shadow.
fdc_recal
                ld    hl,fdc_cmd_rcal
                ld    b,2
                call  fdc_send
                call  fdc_wait_seek
                xor   a
                ld    (fdc_track),a
                ret

; pcwfdc_setunit: A = drive unit (0/1) -> select it in every command and
; force a fresh seek. Drive B is the 80-track CF2DD mechanism: a 40-track
; CF2 disc in it is DOUBLE-STEPPED (media track = head/2), so unit 1
; seeks NCN = 2*track. The READ/WRITE C field stays the media track.
pcwfdc_setunit
                ld    (fdc_unit),a
                ld    (fdc_dbl),a             ; unit 1 = the DD drive: double-step
                ld    (fdc_cmd_rcal+1),a
                ld    (fdc_cmd_seek+1),a
                ld    (fdc_rd_u),a
                ld    (fdc_wr_u),a
                ld    a,#FF
                ld    (fdc_track),a
                ret

; fdc_ncn: the media track fdr_trk -> A = the physical seek target.
fdc_ncn
                ld    a,(fdc_dbl)
                or    a
                ld    a,(fdr_trk)
                ret   z
                add   a,a
                ret

; pcwfdc_read: D = track, E = sector R, HL = 512-byte destination.
; CF set = sector read. Three attempts, recalibrating between them.
; pcwfdc_read1: one attempt, no retry - for presence probes.
pcwfdc_read1
                ld    (fdr_dst),hl
                ld    a,d
                ld    (fdr_trk),a
                ld    a,e
                ld    (fdr_sec),a
                ld    b,1
                jr    fdr_try
pcwfdc_read
                ld    (fdr_dst),hl
                ld    a,d
                ld    (fdr_trk),a
                ld    a,e
                ld    (fdr_sec),a
                ld    b,3                     ; attempts
fdr_try
                push  bc
                call  fdr_once
                pop   bc
                ret   c
                push  bc
                call  fdc_recal               ; re-home before retrying
                pop   bc
                djnz  fdr_try
                or    a                       ; NC = hard failure
                ret

fdr_once
                ld    a,(fdc_track)           ; seek only when the head moves
                ld    hl,fdr_trk
                cp    (hl)
                jr    z,fdo_onspot
                call  fdc_ncn                 ; media -> physical (drive B x2)
                ld    (fdc_sk_trk),a
                ld    hl,fdc_cmd_seek
                ld    b,3
                call  fdc_send
                call  fdc_wait_seek
                ld    a,(fdr_trk)
                ld    (fdc_track),a
fdo_onspot
                ld    a,6
                out   (PCW_SYSCTL),a          ; TC clear before the command
                ld    a,(fdr_trk)             ; READ DATA #66: R = the sector,
                ld    (fdc_rd_c),a            ; EOT stays 9 (TC terminates)
                ld    a,(fdr_sec)
                ld    (fdc_rd_r),a
                ld    hl,fdc_cmd_read
                ld    b,9
                call  fdc_send
                ld    hl,(fdr_dst)            ; polled transfer of 512 bytes
                ld    c,1
                ld    d,2                     ; 2 x 256, count in B (byte window)
fdo_half
                ld    b,0
fdo_rx
                in    a,(0)
                add   a,a                     ; RQM -> carry
                jr    nc,fdo_rx
                add   a,a                     ; EXM -> bit7
                jp    p,fdo_bad               ; result phase early = failed
                ini
                jr    nz,fdo_rx
                dec   d
                jr    nz,fdo_half
                ld    a,5                     ; payload in: terminal count
                out   (PCW_SYSCTL),a
                ld    a,6
                out   (PCW_SYSCTL),a
                call  fdc_result              ; wait INTRQ, read results, A = ST0
                and   #88                     ; fatal IC or NR only (EN = TC-normal)
                jr    nz,fdo_fail
                scf
                ret
fdo_bad
                call  fdc_result              ; swallow the error result
fdo_fail
                or    a
                ret

; pcwfdc_write: D = track, E = sector R, HL = 512-byte source.
; CF set = sector written. Three attempts, recalibrating between them.
pcwfdc_write
                ld    (fdr_dst),hl
                ld    a,d
                ld    (fdr_trk),a
                ld    a,e
                ld    (fdr_sec),a
                ld    b,3
fdw_try
                push  bc
                call  fdw_once
                pop   bc
                ret   c
                push  bc
                call  fdc_recal
                pop   bc
                djnz  fdw_try
                or    a
                ret

fdw_once
                ld    a,(fdc_track)           ; seek only when the head moves
                ld    hl,fdr_trk
                cp    (hl)
                jr    z,fdw_onspot
                call  fdc_ncn                 ; media -> physical (drive B x2)
                ld    (fdc_sk_trk),a
                ld    hl,fdc_cmd_seek
                ld    b,3
                call  fdc_send
                call  fdc_wait_seek
                ld    a,(fdr_trk)
                ld    (fdc_track),a
fdw_onspot
                ld    a,6
                out   (PCW_SYSCTL),a          ; TC clear before the command
                ld    a,(fdr_trk)             ; WRITE DATA #45: R = the sector,
                ld    (fdc_wr_c),a            ; EOT stays 9 (TC terminates)
                ld    a,(fdr_sec)
                ld    (fdc_wr_r),a
                ld    hl,fdc_cmd_write
                ld    b,9
                call  fdc_send
                ld    hl,(fdr_dst)            ; polled transfer of 512 bytes OUT
                ld    c,1
                ld    d,2
fdw_half
                ld    b,0
fdw_tx
                in    a,(0)
                add   a,a                     ; RQM -> carry
                jr    nc,fdw_tx
                add   a,a                     ; EXM -> bit7
                jp    p,fdw_bad               ; result phase early = aborted
                outi
                jr    nz,fdw_tx
                dec   d
                jr    nz,fdw_half
                ld    a,5                     ; payload out: terminal count
                out   (PCW_SYSCTL),a
                ld    a,6
                out   (PCW_SYSCTL),a
                call  fdc_result
                and   #88
                jr    nz,fdw_fail
                scf
                ret
fdw_bad
                call  fdc_result
fdw_fail
                or    a
                ret

; --- primitives (real-chip MSR settle discipline throughout) ----------------

; send B command bytes from (HL): RQM-gated + settle after every byte
fdc_send
                in    a,(0)
                add   a,a
                jr    nc,fdc_send
                ld    a,(hl)
                out   (1),a
                inc   hl
                ex    (sp),hl                 ; ~76 T: let MSR settle before
                ex    (sp),hl                 ; the next poll (real chip)
                ex    (sp),hl
                ex    (sp),hl
                djnz  fdc_send
                ret

; send the single command byte in A
fdc_send1
                push  af
fdc_s1w
                in    a,(0)
                add   a,a
                jr    nc,fdc_s1w
                pop   af
                out   (1),a
                ex    (sp),hl
                ex    (sp),hl
                ex    (sp),hl
                ex    (sp),hl
                ret

; read one result byte -> A (settle after the read)
fdc_res
                in    a,(0)
                add   a,a
                jr    nc,fdc_res
                in    a,(1)
                ex    (sp),hl
                ex    (sp),hl
                ex    (sp),hl
                ex    (sp),hl
                ret

; fdc_result: wait for the command-end INTRQ (raw mirror on #F8 bit 5),
; then read every result byte into fdc_st. Returns A = ST0.
fdc_result
                in    a,(PCW_SYSCTL)
                and   #20
                jr    z,fdc_result
                ld    hl,fdc_st
                ld    b,7
fdc_rs
                in    a,(0)
                bit   4,a                     ; command over (CB clear)?
                jr    z,fdc_rsdone
                add   a,a                     ; RQM?
                jr    nc,fdc_rs
                in    a,(1)
                ld    (hl),a
                inc   hl
                ex    (sp),hl                 ; settle before the next poll
                ex    (sp),hl
                ex    (sp),hl
                ex    (sp),hl
                djnz  fdc_rs
fdc_rsdone
                ld    a,(fdc_st)
                ret

; after RECALIBRATE/SEEK: wait for the INTRQ mirror, then acknowledge with
; ONE SENSE INTERRUPT - never hammered during the seek (real-chip rule)
fdc_wait_seek
                in    a,(PCW_SYSCTL)
                and   #20                     ; live FDC INTRQ
                jr    z,fdc_wait_seek
                ld    a,8                     ; SENSE INTERRUPT (the acknowledge)
                call  fdc_send1
                call  fdc_res                 ; ST0
                cp    #80                     ; spurious race: wait again
                jr    z,fdc_wait_seek
                ld    b,a
                call  fdc_res                 ; PCN, discard
                bit   5,b                     ; seek end?
                jr    z,fdc_wait_seek
                ret

; --- command templates / state -------------------------------------------------
fdc_cmd_spec    db    #03,#0F,#FF             ; SPECIFY: timings + non-DMA
fdc_cmd_rcal    db    #07,#00                 ; RECALIBRATE unit 0
fdc_cmd_seek    db    #0F,#00                 ; SEEK unit 0
fdc_sk_trk      db    0
fdc_cmd_read    db    #66                     ; READ DATA, MFM + SK
fdc_rd_u        db    #00                     ; unit + head
fdc_rd_c        db    0
                db    #00                     ; H
fdc_rd_r        db    1
                db    #02                     ; N = 512
                db    #09                     ; EOT = 9 (TC terminates)
                db    #2A                     ; GPL
                db    #FF                     ; DTL
fdc_cmd_write   db    #45                     ; WRITE DATA, MFM
fdc_wr_u        db    #00                     ; unit + head
fdc_wr_c        db    0
                db    #00                     ; H
fdc_wr_r        db    1
                db    #02                     ; N = 512
                db    #09                     ; EOT = 9 (TC terminates)
                db    #2A                     ; GPL
                db    #FF                     ; DTL

fdc_track       db    #FF                     ; head position shadow (#FF = unknown)
fdc_unit        db    0                       ; selected drive unit (0 = A, 1 = B)
fdc_dbl         db    0                       ; 1 = double-step (CF2 in the DD drive)
fdr_trk         db    0
fdr_sec         db    0
fdr_dst         dw    0
fdc_st          ds    7                       ; last command's result bytes
