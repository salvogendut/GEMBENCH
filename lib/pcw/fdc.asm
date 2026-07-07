; ---------------------------------------------------------------------------
; lib/pcw/fdc.asm - polled uPD765A floppy driver for the PCW target (#331).
;
; The resident graduation of kernel/pcwboot.asm's loader: single-sector
; polled non-DMA reads (the FDC delivers ONE sector per READ DATA command
; in this setup - Phase 1 finding), with seek tracking and retries.
;
; Ports: #00 = main status register, #01 = data register (A7=0 selects the
; FDC, A0 = MSR/data). System control #F8: cmd 04 = FDC irq off (we poll),
; 05/06 = terminal count high/low, 09 = motor on. GEOBENCH runs DI - all
; transfers pace on the MSR RQM bit.
;
;   pcwfdc_init                     SPECIFY (ND=1) + motor + recalibrate
;   pcwfdc_read  D=track E=sector(1..9) HL=512-byte dest  -> CF set = ok
;   pcwfdc_write D=track E=sector(1..9) HL=512-byte src   -> CF set = ok
;
; The motor is turned on at init and left running.
; ---------------------------------------------------------------------------

pcwfdc_init
                ld    a,4
                out   (PCW_SYSCTL),a          ; route FDC interrupt: disabled
                ld    a,9
                out   (PCW_SYSCTL),a          ; motor on (stays on)
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

; pcwfdc_read: D = track, E = sector R, HL = 512-byte destination.
; CF set = sector read. Three attempts, recalibrating between them.
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
                ld    a,(fdr_trk)
                ld    (fdc_sk_trk),a
                ld    hl,fdc_cmd_seek
                ld    b,3
                call  fdc_send
                call  fdc_wait_seek
                ld    a,(fdr_trk)
                ld    (fdc_track),a
fdo_onspot
                ld    a,(fdr_trk)             ; READ DATA, R = EOT = the sector
                ld    (fdc_rd_c),a
                ld    a,(fdr_sec)
                ld    (fdc_rd_r),a
                ld    (fdc_rd_eot),a
                ld    hl,fdc_cmd_read
                ld    b,9
                call  fdc_send
                ld    hl,(fdr_dst)            ; polled transfer of 512 bytes
                ld    de,512
                ld    c,1
fdo_rx
                in    a,(0)
                add   a,a                     ; RQM -> carry
                jr    nc,fdo_rx
                add   a,a                     ; DIO
                add   a,a                     ; EXM -> carry
                jr    nc,fdo_end              ; result phase early = short read
                ini
                dec   de
                ld    a,d
                or    e
                jr    nz,fdo_rx
                ld    a,5                     ; all bytes in: pulse terminal count
                out   (PCW_SYSCTL),a
                ld    a,6
                out   (PCW_SYSCTL),a
fdo_end
                push  de
                call  fdc_drain               ; swallow the result bytes
                pop   de
                ld    a,d                     ; success = every byte arrived
                or    e
                jr    nz,fdo_fail
                scf
                ret
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
                ld    a,(fdr_trk)
                ld    (fdc_sk_trk),a
                ld    hl,fdc_cmd_seek
                ld    b,3
                call  fdc_send
                call  fdc_wait_seek
                ld    a,(fdr_trk)
                ld    (fdc_track),a
fdw_onspot
                ld    a,(fdr_trk)             ; WRITE DATA, R = EOT = the sector
                ld    (fdc_wr_c),a
                ld    a,(fdr_sec)
                ld    (fdc_wr_r),a
                ld    (fdc_wr_eot),a
                ld    hl,fdc_cmd_write
                ld    b,9
                call  fdc_send
                ld    hl,(fdr_dst)            ; polled transfer of 512 bytes OUT
                ld    de,512
                ld    c,1
fdw_tx
                in    a,(0)
                add   a,a                     ; RQM -> carry
                jr    nc,fdw_tx
                add   a,a                     ; DIO (0 = FDC wants data)
                add   a,a                     ; EXM -> carry
                jr    nc,fdw_end              ; result phase early = aborted
                outi
                dec   de
                ld    a,d
                or    e
                jr    nz,fdw_tx
                ld    a,5                     ; all bytes out: pulse terminal count
                out   (PCW_SYSCTL),a
                ld    a,6
                out   (PCW_SYSCTL),a
fdw_end
                push  de
                call  fdc_drain
                pop   de
                ld    a,d                     ; success = every byte delivered
                or    e
                jr    nz,fdw_fail
                scf
                ret
fdw_fail
                or    a
                ret

; --- primitives (as proven in kernel/pcwboot.asm) -----------------------------

; send B command bytes from (HL), waiting for RQM before each
fdc_send
                in    a,(0)
                add   a,a
                jr    nc,fdc_send
                ld    a,(hl)
                out   (1),a
                inc   hl
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
                ret

; read one result byte -> A
fdc_res
                in    a,(0)
                add   a,a
                jr    nc,fdc_res
                in    a,(1)
                ret

; discard result bytes until the FDC goes idle
fdc_drain
                in    a,(0)
                bit   4,a                     ; command busy?
                ret   z
                add   a,a                     ; RQM?
                jr    nc,fdc_drain
                in    a,(1)
                jr    fdc_drain

; after RECALIBRATE/SEEK: poll SENSE INTERRUPT STATUS until seek end
fdc_wait_seek
                ld    a,8
                call  fdc_send1
                call  fdc_res                 ; ST0
                cp    #80                     ; invalid = no interrupt pending yet
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
fdc_cmd_read    db    #46                     ; READ DATA, MFM
                db    #00                     ; unit 0 head 0
fdc_rd_c        db    0
                db    #00                     ; H
fdc_rd_r        db    1
                db    #02                     ; N = 512
fdc_rd_eot      db    1
                db    #2A                     ; GPL
                db    #FF                     ; DTL
fdc_cmd_write   db    #45                     ; WRITE DATA, MFM
                db    #00                     ; unit 0 head 0
fdc_wr_c        db    0
                db    #00                     ; H
fdc_wr_r        db    1
                db    #02                     ; N = 512
fdc_wr_eot      db    1
                db    #2A                     ; GPL
                db    #FF                     ; DTL

fdc_track       db    #FF                     ; head position shadow (#FF = unknown)
fdr_trk         db    0
fdr_sec         db    0
fdr_dst         dw    0
