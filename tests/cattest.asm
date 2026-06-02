; cattest - enumerate the FAT16 root directory on the SymbiFace/Cyboard IDE and
; print the 8.3 filenames. Pure direct-IDE + FAT16 parse, no AMSDOS/UniDOS.
;
; port = &FD00 | reg (from 1984 ide.c):
;   &FD0A scnt  &FD0B lbaL  &FD0C lbaM  &FD0D lbaH  &FD0E dev  &FD0F cmd/status
;   &FD08 data (1 byte/IN)

SCR_SET_MODE    equ   #BC0E
TXT_OUTPUT      equ   #BB5A

IDE_SCNT        equ   #FD0A
IDE_LBAL        equ   #FD0B
IDE_LBAM        equ   #FD0C
IDE_LBAH        equ   #FD0D
IDE_DEV         equ   #FD0E
IDE_CMD         equ   #FD0F
IDE_STAT        equ   #FD0F
IDE_DATA        equ   #FD08

                org   #4000
start
                ld    a,1
                call  SCR_SET_MODE

                ld    hl,0                    ; read BPB (LBA 0)
                call  read_sector

                ld    hl,0                    ; root_lba = reserved + fats*spf
                ld    a,(secbuf+#10)          ; num_fats
                ld    b,a
                ld    de,(secbuf+#16)         ; sectors per FAT
mulfat
                add   hl,de
                djnz  mulfat
                ld    de,(secbuf+#0E)         ; reserved sectors
                add   hl,de
                ld    (root_lba),hl

                ld    hl,(root_lba)          ; read first root-dir sector
                call  read_sector

                ld    ix,secbuf
                ld    b,16                    ; 512/32 entries in this sector
ent_loop
                ld    a,(ix+0)
                or    a
                jr    z,done                  ; &00 = end of directory
                cp    #E5
                jr    z,next                  ; deleted
                ld    a,(ix+#0B)
                and   #0F
                cp    #0F
                jr    z,next                  ; LFN entry
                ld    a,(ix+#0B)
                and   #08
                jr    nz,next                 ; volume label
                call  print_entry
next
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  ent_loop
done
                jr    done

; print 8.3 name from (IX): 8 name + '.' + 3 ext, then CRLF. Preserves IX,BC.
print_entry
                push  bc
                push  ix
                push  ix
                pop   hl                      ; HL = entry
                ld    b,8
                call  putn
                ld    a,'.'
                call  putc
                push  ix
                pop   hl
                ld    de,8
                add   hl,de
                ld    b,3
                call  putn
                ld    a,13
                call  putc
                ld    a,10
                call  putc
                pop   ix
                pop   bc
                ret

; print B chars from (HL) (control -> '.')
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

; read 1 sector, LBA in HL (16-bit), into secbuf
read_sector
                push  hl
                ld    a,#E0
                ld    bc,IDE_DEV
                out   (c),a
                ld    a,1
                ld    bc,IDE_SCNT
                out   (c),a
                pop   hl
                ld    a,l
                ld    bc,IDE_LBAL
                out   (c),a
                ld    a,h
                ld    bc,IDE_LBAM
                out   (c),a
                xor   a
                ld    bc,IDE_LBAH
                out   (c),a
                ld    a,#20
                ld    bc,IDE_CMD
                out   (c),a
rs_poll
                ld    bc,IDE_STAT
                in    a,(c)
                bit   3,a
                jr    z,rs_poll
                ld    hl,secbuf
                ld    de,512
                ld    bc,IDE_DATA
rs_read
                in    a,(c)
                ld    (hl),a
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,rs_read
                ret

root_lba        defw  0
secbuf          defs  512
prog_end
                save  "build/CATTEST.RAW",start,prog_end-start
