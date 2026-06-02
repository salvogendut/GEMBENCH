; ---------------------------------------------------------------------------
; lib/fs_amsdos.asm - storage backend: the AMSDOS directory read straight off
; the floppy via the uPD765 FDC. No AMSDOS/UniDOS ROM involvement, so it works
; on any CPC with a disc drive regardless of which DOS ROM is fitted.
;
; Exposes the backend interface (see lib/fs.asm); fields fs_ent_name/attr/size
; live in lib/fs.asm and are shared with the IDE backend.
;   fsam_dir_first -> CF set = first entry ready, NC = empty
;   fsam_dir_next  -> CF set = next entry ready,  NC = end of directory
;
; uPD765 ports (fixed on every CPC):
;   &FB7E MSR (read): b7 RQM, b6 DIO(1=FDC->CPU), b5 EXM, b4 CB, b0 FDD0 seeking
;   &FB7F data    &FA7E motor (write, bit0 = on)
;
; AMSDOS directory: 64 entries x 32 bytes = 4 sectors (512-byte, N=2). Format is
; sniffed with a READ ID: DATA = track 0 sectors &C1.., SYSTEM = track 2 &41..,
; IBM = track 0 &01.. . CP/M-2.2 dir entry: byte0 user (&E5 = empty), 1..8 name,
; 9..11 ext (top bits = attributes), 12 Ex / 14 S2 = extent number, 15 Rc.
; ---------------------------------------------------------------------------

FSAM_MSR        equ   #FB7E
FSAM_DATA       equ   #FB7F
FSAM_MOTOR      equ   #FA7E

; ---------------------------------------------------------------------------
; fsam_dir_first: read the whole directory into fsam_buf, then return entry 0.
fsam_dir_first
                call  fsam_motor_on            ; spin up + recalibrate to track 0
                call  fsam_read_dir            ; 4 dir sectors -> fsam_buf
                call  fsam_motor_off
                xor   a
                ld    (fsam_idx),a
                jp    fsam_scan

; fsam_dir_next: advance to the next valid entry.
fsam_dir_next
fsam_scan
                ld    a,(fsam_idx)
                cp    64
                jr    nc,fsam_end             ; past the last directory entry

                ld    l,a                       ; entry ptr = fsam_buf + idx*32
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    de,fsam_buf
                add   hl,de                     ; HL -> entry

                ld    a,(hl)
                cp    #E5
                jr    z,fsam_skip               ; deleted / empty slot
                push  hl
                ld    de,12
                add   hl,de
                ld    a,(hl)                     ; Ex (extent low)
                or    a
                pop   hl
                jr    nz,fsam_skip              ; only extent 0 = one row per file
                push  hl
                ld    de,14
                add   hl,de
                ld    a,(hl)                     ; S2 (extent high)
                or    a
                pop   hl
                jr    nz,fsam_skip
                push  hl
                ld    de,10
                add   hl,de
                ld    a,(hl)                     ; ext[1] bit7 = system attribute
                and   #80
                pop   hl
                jr    nz,fsam_skip              ; hide system files (as CAT does)

                ; valid entry -> fill the shared output fields.
                push  hl
                inc   hl                         ; -> filename (8) then ext (3)
                ld    de,fs_ent_name
                ld    b,11
fsam_cpy
                ld    a,(hl)
                and   #7F                        ; drop attribute bits
                ld    (de),a
                inc   hl
                inc   de
                djnz  fsam_cpy
                pop   hl

                xor   a                           ; AMSDOS is flat: no attr/dirs
                ld    (fs_ent_attr),a

                push  hl                          ; size = Rc * 128 (extent 0)
                ld    de,15
                add   hl,de
                ld    a,(hl)                       ; record count
                pop   hl
                ld    l,a
                ld    h,0
                add   hl,hl                        ; *2
                add   hl,hl                        ; *4
                add   hl,hl                        ; *8
                add   hl,hl                        ; *16
                add   hl,hl                        ; *32
                add   hl,hl                        ; *64
                add   hl,hl                        ; *128
                ld    (fs_ent_size),hl
                xor   a
                ld    (fs_ent_size+2),a
                ld    (fs_ent_size+3),a

                ld    a,(fsam_idx)
                inc   a
                ld    (fsam_idx),a
                scf
                ret
fsam_skip
                ld    a,(fsam_idx)
                inc   a
                ld    (fsam_idx),a
                jr    fsam_scan
fsam_end
                or    a                            ; CF clear = end of directory
                ret

; ---------------------------------------------------------------------------
; fsam_read_dir: sniff the format on track 0, seek to the directory track and
; read its 4 sectors into fsam_buf.
fsam_read_dir
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
                ld    a,0
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
                ld    a,0                            ; (head<<2)|drive
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
                ld    a,0
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
                call  fsam_send
                ld    a,0
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
                call  fsam_send                      ; DTL

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
                ld    b,7                             ; drain the 7 result bytes
frs_res_loop
                push  bc
                call  fsam_recv
                pop   bc
                djnz  frs_res_loop
                pop   de                             ; restore caller's track/sector id
                ret

; ---------------------------------------------------------------------------
; fsam_send: write A as a command byte (wait RQM=1, DIO=0).
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

; --- state ---------------------------------------------------------------
fsam_base       defb  #C1
fsam_track      defb  0
fsam_idx        defb  0
fsam_dst        defw  0
fsam_buf        defs  2048
