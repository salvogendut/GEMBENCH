; ---------------------------------------------------------------------------
; lib/fs_amsdos_core.asm - shared low-level AMSDOS/uPD765 FDC primitives.
;
; Included by BOTH the resident backend (lib/fs_amsdos.asm: directory listing +
; file load + presence probe) AND the paged floppy *save* module
; (kernel/modules/floppysv.asm). One source, two assemblies - the gbfat /
; fs_fat32_core split applied to the floppy backend (#135). The includer supplies
; the shared fixed-address buffers (fsam_buf, fs_secbuf) and the name to match
; (fs_req_name); everything here is self-contained otherwise.
; ---------------------------------------------------------------------------

FSAM_MSR        equ   #FB7E
FSAM_DATA       equ   #FB7F
FSAM_MOTOR      equ   #FA7E

; ---------------------------------------------------------------------------
; fsam_read_dir: sniff the format on track 0, seek to the directory track and
; read its 4 sectors into fsam_buf.
fsam_read_dir
                ld    hl,fsam_buf                ; clear the directory buffer first (it is
                ld    de,fsam_buf+1              ; shared low RAM): a failed/empty-drive
                ld    bc,2048-1                  ; read then lists as empty rather than
                ld    (hl),#E5                   ; the previously-read drive's stale dir
                ldir                              ; (#65 - opening empty floppy B showed A)
                call  fsam_read_id               ; A = sector id under the head
                and   #F0
                cp    #40
                jr    z,frd_system
                cp    #C0
                jr    z,frd_data
                ld    a,#01                       ; IBM format
                ld    (fsam_base),a
                xor   a
                ld    (fsam_track),a
                jr    frd_go
frd_data
                ld    a,#C1
                ld    (fsam_base),a
                xor   a
                ld    (fsam_track),a
                jr    frd_go
frd_system
                ld    a,#41
                ld    (fsam_base),a
                ld    a,2
                ld    (fsam_track),a
frd_go
                ld    a,(fsam_track)
                call  fsam_seek

                ld    hl,fsam_buf
                ld    (fsam_dst),hl
                ld    a,(fsam_base)
                ld    e,a                          ; E = current sector id
                ld    b,4
frd_loop
                push  bc
                ld    a,(fsam_track)
                ld    d,a
                call  fsam_read_sector             ; 512 -> (fsam_dst), advances it
                pop   bc
                inc   e
                djnz  frd_loop
                ret

; ---------------------------------------------------------------------------
; Motor on, then recalibrate (seek to track 0).
fsam_motor_on
                ld    bc,FSAM_MOTOR
                ld    a,1
                out   (c),a
                ld    de,0                          ; spin-up delay
fmo_spin
                dec   de
                ld    a,d
                or    e
                jr    nz,fmo_spin
                ld    a,#07                         ; RECALIBRATE
                call  fsam_send
                ld    a,(fsam_unit)                  ; drive 0/1
                call  fsam_send
                jp    fsam_wait_seek

fsam_motor_off
                ld    bc,FSAM_MOTOR
                xor   a
                out   (c),a
                ret

; fsam_seek: A = track.
fsam_seek
                ld    d,a
                ld    a,#0F                         ; SEEK
                call  fsam_send
                ld    a,(fsam_unit)                  ; (head<<2)|drive
                call  fsam_send
                ld    a,d
                call  fsam_send
                ; fall through to wait
fsam_wait_seek
                ld    hl,0                            ; guard against a hang
fws_loop
                ld    bc,FSAM_MSR
                in    a,(c)
                and   1                              ; FDD0 still seeking?
                jr    z,fws_done
                dec   hl
                ld    a,h
                or    l
                jr    nz,fws_loop
fws_done
                ld    a,#08                          ; SENSE INTERRUPT STATUS
                call  fsam_send
                call  fsam_recv                      ; ST0
                call  fsam_recv                      ; PCN
                ret

; ---------------------------------------------------------------------------
; fsam_read_id: READ ID on track 0 -> A = sector id (R) under the head.
fsam_read_id
                ld    a,#4A
                call  fsam_send
                ld    a,(fsam_unit)
                call  fsam_send
                call  fsam_recv                      ; ST0
                call  fsam_recv                      ; ST1
                call  fsam_recv                      ; ST2
                call  fsam_recv                      ; C
                call  fsam_recv                      ; H
                call  fsam_recv                      ; R
                ld    h,a
                call  fsam_recv                      ; N
                ld    a,h
                ret

; fsam_read_sector: D=track, E=sector id. 512 bytes -> (fsam_dst); advances it.
fsam_read_sector
                push  de                             ; keep caller's track/sector id
                ld    a,#46                          ; READ DATA, MFM
                call  fsam_cmd9                       ; issue the command + params
                ld    hl,(fsam_dst)
                ld    de,512
frs_exec
                ld    bc,FSAM_MSR
                in    a,(c)
                bit   7,a                            ; RQM?
                jr    z,frs_exec
                bit   5,a                            ; still in execution phase?
                jr    z,frs_result
                ld    bc,FSAM_DATA
                in    a,(c)
                ld    (hl),a
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,frs_exec
frs_result
                ld    (fsam_dst),hl
                call  fsam_drain                      ; drain the 7 result bytes
                pop   de                             ; restore caller's track/sector id
                ret

; fsam_cmd9: issue a 9-byte READ/WRITE DATA command. A = command byte (&46 READ /
; &45 WRITE), D = track, E = sector id. Shared by fsam_read_sector/write_sector.
fsam_cmd9
                call  fsam_send                      ; command
                ld    a,(fsam_unit)
                call  fsam_send                      ; (head<<2)|drive
                ld    a,d
                call  fsam_send                      ; C = track
                ld    a,0
                call  fsam_send                      ; H = head
                ld    a,e
                call  fsam_send                      ; R = sector
                ld    a,2
                call  fsam_send                      ; N = 2 (512)
                ld    a,e
                call  fsam_send                      ; EOT = R (single sector)
                ld    a,#2A
                call  fsam_send                      ; GPL
                ld    a,#FF
                jp    fsam_send                      ; DTL (tail call)

; fsam_drain: read and discard the 7 FDC result-phase bytes.
fsam_drain
                ld    b,7
fdr_loop
                push  bc
                call  fsam_recv
                pop   bc
                djnz  fdr_loop
                ret

; ---------------------------------------------------------------------------
; fsam_send: write A as a command byte (wait RQM=1, DIO=0). Reached only after
; fsam_present confirms an FDC, so the wait stays unbounded (a present FDC answers
; in microseconds); no-controller machines are caught by fsam_present's pre-check.
fsam_send
                push  de                             ; preserve caller's track/sector
                ld    e,a
fsnd_wait
                ld    bc,FSAM_MSR
                in    a,(c)
                bit   7,a
                jr    z,fsnd_wait
                bit   6,a                            ; DIO must be 0 to accept
                jr    nz,fsnd_wait
                ld    a,e
                ld    bc,FSAM_DATA
                out   (c),a
                pop   de
                ret

; fsam_recv: read a result byte into A (wait RQM=1, DIO=1).
fsam_recv
frcv_wait
                ld    bc,FSAM_MSR
                in    a,(c)
                bit   7,a
                jr    z,frcv_wait
                bit   6,a                            ; DIO=1 -> data ready
                jr    z,frcv_wait
                ld    bc,FSAM_DATA
                in    a,(c)
                ret

; fsam_namematch: IX = dir entry; Z if its 8.3 name == fs_req_name (11 bytes).
fsam_namematch
                push  ix
                pop   hl
                inc   hl                              ; entry name starts at +1
                ld    de,fs_req_name
                ld    b,11
fnm_loop
                ld    a,(hl)
                and   #7F                             ; drop attribute bits
                ld    c,a
                ld    a,(de)
                cp    c
                jr    nz,fnm_no
                inc   hl
                inc   de
                djnz  fnm_loop
                xor   a
                ret
fnm_no
                or    1
                ret

; fsam_div9: HL / 9 -> B = quotient, A = remainder (0..8). Clobbers DE.
fsam_div9
                ld    b,0
fd9_loop
                ld    a,h
                or    a
                jr    nz,fd9_sub
                ld    a,l
                cp    9
                jr    c,fd9_done
fd9_sub
                or    a
                ld    de,9
                sbc   hl,de
                inc   b
                jr    fd9_loop
fd9_done
                ld    a,l
                ret

; --- shared core state -----------------------------------------------------
fsam_unit       defb  0            ; selected drive: 0 = A, 1 = B
fsam_base       defb  #C1          ; first physical sector id (format-dependent)
fsam_track      defb  0            ; directory track
fsam_dst        defw  0            ; fsam_read_sector destination, advances
