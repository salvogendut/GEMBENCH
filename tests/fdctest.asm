; fdctest - read the AMSDOS directory straight off the floppy via the uPD765
; FDC (no AMSDOS/UniDOS), and print the 8.3 filenames. This validates the logic
; that lib/fs_amsdos.asm uses as a storage backend.
;
; uPD765 on the CPC (fixed ports on every machine):
;   &FB7E  Main Status Register (read): b7 RQM, b6 DIO(1=FDC->CPU), b5 EXM,
;          b4 CB(busy), b0 FDD0 seeking
;   &FB7F  Data register (read/write command/result/data bytes)
;   &FA7E  Motor control (write, bit0 = motor on)
;
; AMSDOS disc geometry: 512-byte sectors, N=2. The directory is 64 entries of
; 32 bytes = 4 sectors. DATA format: track 0, sectors &C1..&C4. SYSTEM format:
; track 2, sectors &41..&44. We sniff the format with a READ ID.

SCR_SET_MODE    equ   #BC0E
TXT_OUTPUT      equ   #BB5A

FDC_MSR         equ   #FB7E
FDC_DATA        equ   #FB7F
FDC_MOTOR       equ   #FA7E

                org   #4000
start
                ld    a,1
                call  SCR_SET_MODE

                call  fdc_motor_on            ; spin up, recalibrate to track 0
                call  read_directory          ; 4 dir sectors -> dirbuf
                call  fdc_motor_off

                ld    ix,dirbuf
                ld    b,64                    ; 64 directory entries
ent_loop
                ld    a,(ix+0)                ; user byte
                cp    #E5
                jr    z,next                  ; deleted / empty
                ld    a,(ix+12)               ; extent low (Ex)
                or    a
                jr    nz,next                 ; only extent 0 (one row per file)
                ld    a,(ix+14)               ; extent high (S2)
                or    a
                jr    nz,next
                ld    a,(ix+10)               ; ext[1] bit7 = system attribute
                and   #80
                jr    nz,next                 ; hide system files (as CAT does)
                call  print_entry
next
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  ent_loop
done
                jr    done

; print "NAME.EXT" from (IX): bytes 1..8 name, 9..11 ext (mask off attr bits)
print_entry
                push  bc
                push  ix
                pop   hl
                inc   hl                      ; skip user byte -> filename
                ld    b,8
                call  putn
                ld    a,'.'
                call  putc
                push  ix
                pop   hl
                ld    de,9
                add   hl,de                   ; -> extension
                ld    b,3
                call  putn
                ld    a,13
                call  putc
                ld    a,10
                call  putc
                pop   bc
                ret

; print B chars from (HL), masking attribute bit7; control -> '.'
putn
                ld    a,(hl)
                and   #7F
                cp    32
                jr    nc,putn1
                ld    a,'.'
putn1
                push  bc
                push  hl
                call  TXT_OUTPUT
                pop   hl
                pop   bc
                inc   hl
                djnz  putn
                ret
putc
                push  bc
                push  hl
                call  TXT_OUTPUT
                pop   hl
                pop   bc
                ret

; ---------------------------------------------------------------------------
; read_directory: sniff the format on track 0, then read the 4 directory
; sectors into dirbuf (2048 bytes).
read_directory
                call  fdc_read_id            ; -> A = sector id under the head
                and   #F0
                cp    #40
                jr    z,rd_system
                ; DATA (C1..) or IBM (01..) -> directory on track 0
                cp    #C0
                jr    z,rd_data
                ld    a,#01                   ; IBM base
                ld    (dir_base),a
                xor   a
                ld    (dir_track),a
                jr    rd_go
rd_data
                ld    a,#C1
                ld    (dir_base),a
                xor   a
                ld    (dir_track),a
                jr    rd_go
rd_system
                ld    a,#41
                ld    (dir_base),a
                ld    a,2
                ld    (dir_track),a
rd_go
                ld    a,(dir_track)
                call  fdc_seek

                ld    hl,dirbuf
                ld    (fdc_dst),hl
                ld    a,(dir_base)
                ld    e,a                      ; E = current sector id
                ld    b,4                      ; 4 sectors
rd_loop
                push  bc
                ld    a,(dir_track)
                ld    d,a
                call  fdc_read_sector          ; reads 512 into (fdc_dst), advances it
                pop   bc
                inc   e
                djnz  rd_loop
                ret

; ---------------------------------------------------------------------------
; Motor on + recalibrate to track 0.
fdc_motor_on
                ld    bc,FDC_MOTOR
                ld    a,1
                out   (c),a
                call  fdc_spinup
                ; recalibrate (seek to track 0)
                ld    a,#07
                call  fdc_send
                ld    a,0
                call  fdc_send
                call  fdc_wait_seek
                ret

fdc_motor_off
                ld    bc,FDC_MOTOR
                xor   a
                out   (c),a
                ret

fdc_spinup
                ld    de,0
fsp_loop
                dec   de
                ld    a,d
                or    e
                jr    nz,fsp_loop
                ret

; fdc_seek: A = track. Issue SEEK then wait for completion.
fdc_seek
                ld    d,a
                ld    a,#0F
                call  fdc_send
                ld    a,0                      ; (head<<2)|drive
                call  fdc_send
                ld    a,d
                call  fdc_send
                call  fdc_wait_seek
                ret

; Wait for the in-progress seek to finish, then SENSE INTERRUPT STATUS to clear
; it (the FDC needs this before the next command).
fdc_wait_seek
                ld    hl,0                     ; guard against a hang
fws_loop
                ld    bc,FDC_MSR
                in    a,(c)
                and   1                        ; FDD0 still seeking?
                jr    z,fws_done
                dec   hl
                ld    a,h
                or    l
                jr    nz,fws_loop
fws_done
                ld    a,#08                    ; sense interrupt status
                call  fdc_send
                call  fdc_recv                 ; ST0
                call  fdc_recv                 ; PCN
                ret

; ---------------------------------------------------------------------------
; fdc_read_id: READ ID on track 0, returns A = sector id (R) under the head.
fdc_read_id
                ld    a,#4A                    ; READ ID, MFM
                call  fdc_send
                ld    a,0                      ; (head<<2)|drive
                call  fdc_send
                call  fdc_recv                 ; ST0
                call  fdc_recv                 ; ST1
                call  fdc_recv                 ; ST2
                call  fdc_recv                 ; C
                call  fdc_recv                 ; H
                call  fdc_recv                 ; R
                ld    h,a                       ; keep R
                call  fdc_recv                 ; N
                ld    a,h
                ret

; ---------------------------------------------------------------------------
; fdc_read_sector: D=track, E=sector id. Reads 512 bytes to (fdc_dst) and
; advances fdc_dst by 512.
fdc_read_sector
                push  de                       ; keep caller's track/sector id
                ld    a,#46                    ; READ DATA, MFM
                call  fdc_send
                ld    a,0                      ; (head<<2)|drive
                call  fdc_send
                ld    a,d
                call  fdc_send                 ; C = track
                ld    a,0
                call  fdc_send                 ; H = head
                ld    a,e
                call  fdc_send                 ; R = sector
                ld    a,2
                call  fdc_send                 ; N = 2 (512 bytes)
                ld    a,e
                call  fdc_send                 ; EOT = R (read a single sector)
                ld    a,#2A
                call  fdc_send                 ; GPL
                ld    a,#FF
                call  fdc_send                 ; DTL

                ld    hl,(fdc_dst)
                ld    de,512
frs_exec
                ld    bc,FDC_MSR
                in    a,(c)
                bit   7,a                      ; RQM?
                jr    z,frs_exec
                bit   5,a                      ; still in execution phase?
                jr    z,frs_result
                ld    bc,FDC_DATA
                in    a,(c)
                ld    (hl),a
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,frs_exec
frs_result
                ld    (fdc_dst),hl             ; next sector lands after this one
                ld    b,7                      ; drain the 7 result bytes
frs_res_loop
                push  bc
                call  fdc_recv
                pop   bc
                djnz  frs_res_loop
                pop   de                       ; restore caller's track/sector id
                ret

; ---------------------------------------------------------------------------
; fdc_send: write A as a command byte (wait RQM=1, DIO=0).
fdc_send
                push  de                       ; preserve caller's track/sector
                ld    e,a
fsnd_wait
                ld    bc,FDC_MSR
                in    a,(c)
                bit   7,a                      ; RQM
                jr    z,fsnd_wait
                bit   6,a                      ; DIO must be 0 to accept a byte
                jr    nz,fsnd_wait
                ld    a,e
                ld    bc,FDC_DATA
                out   (c),a
                pop   de
                ret

; fdc_recv: read a result byte into A (wait RQM=1, DIO=1).
fdc_recv
frcv_wait
                ld    bc,FDC_MSR
                in    a,(c)
                bit   7,a                      ; RQM
                jr    z,frcv_wait
                bit   6,a                      ; DIO=1 -> data available
                jr    z,frcv_wait
                ld    bc,FDC_DATA
                in    a,(c)
                ret

; ---------------------------------------------------------------------------
dir_base        defb  #C1
dir_track       defb  0
fdc_dst         defw  0
dirbuf          defs  2048
prog_end
                save  "build/FDCTEST.RAW",start,prog_end-start
                save  "FDCTEST",start,prog_end-start,DSK,"build/fdctest.dsk"
