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
                call  fsam_send
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

; ---------------------------------------------------------------------------
; fsam_present: is there a readable disk in drive (fsam_unit)? Spins the motor,
; recalibrates and tries a READ ID; a normal result (ST0 IC bits 7-6 == 00)
; means a disk is in the drive. CF set = present.
fsam_present
                call  fsam_motor_on                  ; motor + recalibrate the unit
                ld    a,#4A                          ; READ ID
                call  fsam_send
                ld    a,(fsam_unit)
                call  fsam_send
                call  fsam_recv                      ; ST0
                push  af                              ; save it (motor_off clobbers BC)
                call  fsam_recv                      ; ST1
                call  fsam_recv                      ; ST2
                call  fsam_recv                      ; C
                call  fsam_recv                      ; H
                call  fsam_recv                      ; R
                call  fsam_recv                      ; N
                call  fsam_motor_off
                pop   af                             ; ST0 IC bits 7-6 == 00 => OK
                and   #C0
                ret   nz                             ; abnormal -> CF clear (absent)
                scf
                ret

; ---------------------------------------------------------------------------
; fsam_load_file: load fs_req_name (8.3) from the floppy into (fs_load_dst).
; Single extent (Ex=0, <=16KB) only; strips a 128-byte AMSDOS header if present.
; CF set = loaded (fs_ent_size = byte size), NC = not found.
;
; AMSDOS DATA format: 1KB allocation blocks = 2 sectors. Block B's two 512-byte
; sectors are logical sectors L = B*2 and B*2+1; L -> track = L/9, physical
; sector = &C1 + (L mod 9).
fsam_load_file
                call  fsam_motor_on                  ; spin up + recalibrate
                call  fsam_read_dir                  ; directory -> fsam_buf

                ld    ix,fsam_buf                    ; find Ex=0 entry by name
                ld    b,64
fslf_scan
                ld    a,(ix+0)
                cp    #E5
                jr    z,fslf_next
                ld    a,(ix+12)                      ; first extent only
                or    a
                jr    nz,fslf_next
                call  fsam_namematch
                jr    z,fslf_found
fslf_next
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  fslf_scan
fslf_toobig
                call  fsam_motor_off
                or    a                               ; not found / too big
                ret

fslf_found
                ld    a,(ix+15)                      ; on-disk bytes = Rc*128 > buffer?
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl                           ; Rc * 128
                ld    de,(fs_load_max)
                ex    de,hl
                or    a
                sbc   hl,de                           ; max - Rc*128
                jr    c,fslf_toobig                   ; Rc*128 > max -> refuse
                push  ix                              ; copy 16 block numbers out
                pop   hl
                ld    de,16
                add   hl,de
                ld    de,fslf_blocks
                ld    bc,16
                ldir
                ld    a,(ix+15)                      ; Rc records -> sectors = ceil(Rc/4)
                add   a,3
                rrca                                  ; /4 (Rc<=128 so bit7 clear after +3)
                rrca
                and   #3F
                ld    (fslf_secs),a
                ld    a,(ix+15)                      ; remember Rc for the no-header size
                ld    (fslf_rc),a

                ld    hl,(fs_load_dst)
                ld    (fsam_dst),hl                  ; fsam_read_sector advances this
                xor   a
                ld    (fslf_si),a
                ld    a,#FF
                ld    (fslf_curtrk),a                ; force a seek on the first sector
fslf_rd
                ld    a,(fslf_secs)
                or    a
                jr    z,fslf_done
                dec   a
                ld    (fslf_secs),a

                ld    a,(fslf_si)                    ; block index = si / 2
                srl   a
                ld    e,a
                ld    d,0
                ld    hl,fslf_blocks
                add   hl,de
                ld    l,(hl)                          ; L = block*2 + (si & 1)
                ld    h,0
                add   hl,hl
                ld    a,(fslf_si)
                and   1
                or    l
                ld    l,a
                call  fsam_div9                       ; HL/9 -> B=track, A=remainder
                ld    c,a                             ; remainder
                ld    a,b                             ; track changed? seek
                ld    e,a                             ; keep track in E
                ld    a,(fslf_curtrk)
                cp    e
                jr    z,fslf_noseek
                ld    a,e
                ld    (fslf_curtrk),a
                push  bc
                ld    a,e
                call  fsam_seek
                pop   bc
fslf_noseek
                ld    a,(fslf_curtrk)
                ld    d,a                             ; D = track
                ld    a,#C1
                add   a,c
                ld    e,a                             ; E = physical sector
                call  fsam_read_sector

                ld    a,(fslf_si)
                inc   a
                ld    (fslf_si),a
                jr    fslf_rd
fslf_done
                call  fsam_motor_off
                ; --- strip a 128-byte AMSDOS header if the checksum matches ---
                ld    hl,(fs_load_dst)
                ld    de,0                            ; sum of bytes [0..66]
                ld    b,67
fslf_sum
                ld    a,(hl)
                add   a,e
                ld    e,a
                jr    nc,fslf_nc
                inc   d
fslf_nc
                inc   hl
                djnz  fslf_sum
                ld    hl,(fs_load_dst)               ; compare to word at [67]
                ld    bc,67
                add   hl,bc
                ld    a,(hl)
                cp    e
                jr    nz,fslf_nohdr
                inc   hl
                ld    a,(hl)
                cp    d
                jr    nz,fslf_nohdr
                ld    hl,(fs_load_dst)               ; header: length = word @ [24]
                ld    bc,24
                add   hl,bc
                ld    c,(hl)
                inc   hl
                ld    b,(hl)
                ld    (fs_ent_size),bc
                ld    hl,0
                ld    (fs_ent_size+2),hl
                ld    hl,(fs_load_dst)               ; shift content down past header
                ld    de,128
                add   hl,de
                ld    de,(fs_load_dst)
                ld    bc,(fs_ent_size)
                ld    a,b
                or    c
                jr    z,fslf_ok                       ; zero-length -> nothing to move
                ldir
                jr    fslf_ok
fslf_nohdr
                ld    a,(fslf_rc)                    ; no header: size = Rc * 128
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl                           ; *128
                ld    (fs_ent_size),hl
                ld    hl,0
                ld    (fs_ent_size+2),hl
fslf_ok
                scf
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

; --- state ---------------------------------------------------------------
fslf_blocks     defs  16           ; allocation block numbers of the found extent
fslf_secs       defb  0            ; sectors left to read
fslf_si         defb  0            ; sector index within the file
fslf_rc         defb  0            ; record count (for the no-header size)
fslf_curtrk     defb  0            ; track the head is currently on
fsam_unit       defb  0            ; selected drive: 0 = A, 1 = B
fsam_base       defb  #C1
fsam_track      defb  0
fsam_idx        defb  0
fsam_dst        defw  0
fsam_buf        defs  2048
