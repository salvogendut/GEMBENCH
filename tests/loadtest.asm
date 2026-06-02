; loadtest - read a named file's CONTENTS off the FAT16/IDE volume and print it.
; Validates the cluster-chain file read that lib/fs_ide_fat.asm will expose as
; fside_load_file (the foundation for GEOBENCH.CFG and disk-loaded icon sets).
;
; FAT16: BPB at LBA0 gives sec/clus (0x0D), reserved=FAT start (0x0E),
; num_fats (0x10), sec/fat (0x16), root_entries (0x11). root_lba = reserved +
; num_fats*spf; data_lba = root_lba + root_entries/16. A file's dir entry gives
; the start cluster (0x1A) and size (0x1C). cluster C -> LBA data_lba+(C-2)*spc;
; FAT16 next cluster = word at FAT[C]. 16-bit LBA (files live in the first 32MB).

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

                call  fat_geometry           ; BPB -> spc, fat_lba, root_lba, data_lba
                ld    hl,want_name
                call  find_file              ; -> CF set, file_clus + file_size
                jr    nc,notfound
                ld    hl,filebuf
                ld    (load_dst),hl
                call  read_file              ; chain -> filebuf

                ld    hl,(file_size)         ; print the last 40 bytes (in cluster 2)
                ld    de,40
                or    a
                sbc   hl,de
                ld    de,filebuf
                add   hl,de
                ex    de,hl                   ; DE = filebuf + size - 40
                ld    hl,40                   ; HL = byte count
print_loop
                ld    a,h
                or    l
                jr    z,done
                ld    a,(de)
                push  hl
                push  de
                call  putc
                pop   de
                pop   hl
                inc   de
                dec   hl
                jr    print_loop
notfound
                ld    hl,txt_nf
nf_loop         ld    a,(hl)
                or    a
                jr    z,done
                push  hl
                call  TXT_OUTPUT
                pop   hl
                inc   hl
                jr    nf_loop
done            jr    done

putc                                          ; print A (control -> '.')
                cp    32
                jr    nc,putc1
                cp    13
                jr    z,putc1
                cp    10
                jr    z,putc1
                ld    a,'.'
putc1           jp    TXT_OUTPUT

; ---------------------------------------------------------------------------
; fat_geometry: parse the BPB at LBA0 into spc / fat_lba / root_lba / data_lba.
fat_geometry
                ld    hl,0
                call  read_sector
                ld    a,(secbuf+#0D)
                ld    (spc),a
                ld    hl,(secbuf+#0E)         ; reserved = FAT start
                ld    (fat_lba),hl
                ld    a,(secbuf+#10)          ; root_lba = reserved + fats*spf
                ld    b,a
                ld    de,(secbuf+#16)
                ld    hl,(secbuf+#0E)
fg_mul          add   hl,de
                djnz  fg_mul
                ld    (root_lba),hl
                ld    hl,(secbuf+#11)         ; root_secs = root_entries/16
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                ld    (root_secs),a
                ld    e,a                      ; data_lba = root_lba + root_secs
                ld    d,0
                ld    hl,(root_lba)
                add   hl,de
                ld    (data_lba),hl
                ret

; ---------------------------------------------------------------------------
; find_file: HL -> 11-byte name. Scans the root dir; on match sets file_clus +
; file_size and returns CF set, else NC.
find_file
                ld    (want_ptr),hl
                ld    a,(root_secs)
                ld    (ff_secsleft),a
                ld    hl,(root_lba)
                ld    (ff_lba),hl
ff_nextsec
                ld    a,(ff_secsleft)
                or    a
                jr    z,ff_none
                ld    hl,(ff_lba)
                call  read_sector
                ld    ix,secbuf
                ld    b,16                     ; 16 entries / sector
ff_ent
                ld    a,(ix+0)
                or    a
                jr    z,ff_none               ; 0x00 = end of directory
                cp    #E5
                jr    z,ff_skip
                ld    a,(ix+#0B)
                and   #0F
                cp    #0F
                jr    z,ff_skip               ; LFN
                ld    a,(ix+#0B)
                and   #08
                jr    nz,ff_skip              ; volume label
                call  ff_match                ; compare 11 bytes
                jr    z,ff_found
ff_skip
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  ff_ent
                ld    hl,(ff_lba)             ; next sector
                inc   hl
                ld    (ff_lba),hl
                ld    a,(ff_secsleft)
                dec   a
                ld    (ff_secsleft),a
                jr    ff_nextsec
ff_found
                ld    a,(ix+#1A)             ; start cluster
                ld    (file_clus),a
                ld    a,(ix+#1B)
                ld    (file_clus+1),a
                ld    a,(ix+#1C)             ; size (low 16 used)
                ld    (file_size),a
                ld    a,(ix+#1D)
                ld    (file_size+1),a
                scf
                ret
ff_none
                or    a
                ret

ff_match                                      ; IX entry vs (want_ptr); Z if equal
                ld    hl,(want_ptr)
                push  ix
                pop   de                       ; DE = entry
                ld    b,11
ffm_loop
                ld    a,(de)
                cp    (hl)
                jr    nz,ffm_no
                inc   hl
                inc   de
                djnz  ffm_loop
                xor   a                        ; Z
                ret
ffm_no
                or    1                        ; NZ
                ret

; ---------------------------------------------------------------------------
; read_file: follow file_clus's chain, copying file_size bytes' worth of
; sectors to (load_dst).
read_file
                ld    hl,(file_size)         ; sectors = ceil(size/512)
                ld    de,511
                add   hl,de
                ld    b,9
rf_sh           srl   h
                rr    l
                djnz  rf_sh
                ld    (rf_secs),hl
                ld    hl,(file_clus)
                ld    (rf_clus),hl
                xor   a
                ld    (rf_sic),a
rf_loop
                ld    hl,(rf_secs)
                ld    a,h
                or    l
                ret   z                         ; all sectors read
                ld    hl,(rf_clus)            ; LBA = data_lba+(clus-2)*spc+sic
                dec   hl
                dec   hl
                call  mul_spc
                ld    de,(data_lba)
                add   hl,de
                ld    a,(rf_sic)
                ld    e,a
                ld    d,0
                add   hl,de
                call  read_sector
                ld    hl,secbuf              ; copy sector to dst
                ld    de,(load_dst)
                ld    bc,512
                ldir
                ld    (load_dst),de
                ld    hl,(rf_secs)
                dec   hl
                ld    (rf_secs),hl
                ld    a,(rf_sic)             ; advance sector-in-cluster
                inc   a
                ld    b,a                      ; B = new sector-in-cluster
                ld    a,(spc)
                cp    b
                jr    nz,rf_keepsic
                call  fat_next                ; cluster boundary -> next cluster
                xor   a                        ; sic back to 0
                ld    (rf_sic),a
                jr    rf_loop
rf_keepsic
                ld    a,b                      ; still inside the cluster
                ld    (rf_sic),a
                jr    rf_loop

mul_spc                                       ; HL *= spc (power of 2)
                ld    a,(spc)
                ld    b,0
ms_log          srl   a
                jr    z,ms_shift
                inc   b
                jr    ms_log
ms_shift
                inc   b
ms_dec          dec   b
                ret   z
                add   hl,hl
                jr    ms_dec

fat_next                                      ; rf_clus -> next cluster (FAT16)
                ld    hl,(rf_clus)
                ld    a,h                       ; fat_sector = fat_lba + clus/256
                ld    l,a
                ld    h,0
                ld    de,(fat_lba)
                add   hl,de
                call  read_sector
                ld    a,(rf_clus)             ; within = (clus & 255)*2
                ld    l,a
                ld    h,0
                add   hl,hl
                ld    de,secbuf
                add   hl,de
                ld    a,(hl)
                ld    e,a
                inc   hl
                ld    a,(hl)
                ld    d,a
                ld    (rf_clus),de
                ret

; ---------------------------------------------------------------------------
; read_sector: read one 512-byte sector, LBA in HL (16-bit), into secbuf.
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
rs_poll         ld    bc,IDE_STAT
                in    a,(c)
                bit   3,a
                jr    z,rs_poll
                ld    hl,secbuf
                ld    de,512
                ld    bc,IDE_DATA
rs_read         in    a,(c)
                ld    (hl),a
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,rs_read
                ret

want_name       db    "BIG     TXT"
txt_nf          db    "NOT FOUND",0

spc             db    0
fat_lba         dw    0
root_lba        dw    0
root_secs       db    0
data_lba        dw    0
want_ptr        dw    0
file_clus       dw    0
file_size       dw    0
load_dst        dw    0
ff_lba          dw    0
ff_secsleft     db    0
rf_secs         dw    0
rf_clus         dw    0
rf_sic          db    0
secbuf          defs  512
filebuf         defs  6144
prog_end
                save  "LOADTEST",start,prog_end-start,DSK,"build/loadtest.dsk"
                save  "build/LOADTEST.RAW",start,prog_end-start
