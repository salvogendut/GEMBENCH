; ---------------------------------------------------------------------------
; lib/fs_ide_fat.asm - storage backend: FAT16 over the SYMBiFACE II / Cyboard
; IDE interface. Reads the root directory straight off the IDE controller, with
; no AMSDOS/UniDOS involvement. Selected by lib/fs.asm when an IDE is present.
;
; Backend entry points (the floppy backend exposes the matching fsam_* names so
; the dispatcher in lib/fs.asm can route to either):
;   fside_dir_first -> CF set = first entry ready in fs_ent_*, NC = empty
;   fside_dir_next  -> CF set = next entry ready,              NC = end of dir
; Per-entry output fields fs_ent_name/attr/size live in lib/fs.asm (shared).
;
; IDE port map (from 1984 src/ide.c; port = &FD00 | reg):
;   &FD0A scnt  &FD0B lbaL  &FD0C lbaM  &FD0D lbaH  &FD0E dev  &FD0F cmd/status
;   &FD08 data (1 byte per IN).  READ SECTORS = &20, DRQ = status bit 3.
; ---------------------------------------------------------------------------

FS_IDE_SCNT     equ   #FD0A
FS_IDE_LBAL     equ   #FD0B
FS_IDE_LBAM     equ   #FD0C
FS_IDE_LBAH     equ   #FD0D
FS_IDE_DEV      equ   #FD0E
FS_IDE_CMD      equ   #FD0F
FS_IDE_STAT     equ   #FD0F
FS_IDE_DATA     equ   #FD08

; ---------------------------------------------------------------------------
; fside_dir_first: mount the volume (read BPB, locate the root directory) and
; return the first valid entry.
fside_dir_first
                ld    hl,0                    ; BPB lives at LBA 0
                call  fs_read_sector

                ld    hl,0                    ; root_lba = reserved + fats*spf
                ld    a,(fs_secbuf+#10)       ; number of FATs
                ld    b,a
                ld    de,(fs_secbuf+#16)      ; sectors per FAT
ffr_mul
                add   hl,de
                djnz  ffr_mul
                ld    de,(fs_secbuf+#0E)      ; reserved sectors
                add   hl,de
                ld    (fs_root_lba),hl

                ld    hl,(fs_secbuf+#11)      ; root entry count / 16 = sectors
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                or    a
                jr    nz,ffr_secok
                inc   a                        ; at least one sector
ffr_secok
                ld    (fs_root_secs),a

                ld    a,(fs_secbuf+#0D)       ; geometry for file reads (BPB still
                ld    (fs_spc),a               ; in secbuf): sectors per cluster,
                ld    hl,(fs_secbuf+#0E)      ; FAT start (= reserved),
                ld    (fs_fat_lba),hl
                ld    hl,(fs_root_lba)        ; data start = root_lba + root_secs
                ld    a,(fs_root_secs)
                ld    e,a
                ld    d,0
                add   hl,de
                ld    (fs_data_lba),hl

                xor   a
                ld    (fs_cur_sec),a
                ld    (fs_ent_idx),a
                ld    hl,(fs_root_lba)        ; load the first root-dir sector
                call  fs_read_sector
                jp    fdn_loop                 ; scan for the first valid entry

; ---------------------------------------------------------------------------
; fside_dir_next: scan forward (across sectors) for the next valid 8.3 entry.
fside_dir_next
fdn_loop
                ld    a,(fs_ent_idx)
                cp    16                       ; 16 entries per 512-byte sector
                jr    c,fdn_have
                ld    a,(fs_cur_sec)           ; exhausted: step to next sector
                inc   a
                ld    (fs_cur_sec),a
                ld    b,a
                ld    a,(fs_root_secs)
                cp    b
                jp    z,fdn_end                ; past the last root-dir sector
                jp    c,fdn_end
                ld    hl,(fs_root_lba)
                ld    a,(fs_cur_sec)
                ld    e,a
                ld    d,0
                add   hl,de
                call  fs_read_sector
                xor   a
                ld    (fs_ent_idx),a
fdn_have
                ld    a,(fs_ent_idx)           ; entry ptr = secbuf + idx*32
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    de,fs_secbuf
                add   hl,de

                ld    a,(hl)
                or    a
                jp    z,fdn_end                ; &00 = end of directory
                cp    #E5
                jr    z,fdn_skip               ; deleted entry

                push  hl
                ld    de,#0B
                add   hl,de
                ld    a,(hl)                   ; attribute byte
                pop   hl
                ld    b,a
                and   #0F
                cp    #0F
                jr    z,fdn_skip               ; long-file-name fragment
                ld    a,b
                and   #08
                jr    nz,fdn_skip              ; volume label

                push  hl                       ; valid -> copy fields out
                ld    de,fs_ent_name
                ld    bc,11
                ldir
                pop   hl
                ld    a,b                       ; attr was saved in B
                ld    (fs_ent_attr),a
                push  hl
                ld    de,#1C
                add   hl,de
                ld    de,fs_ent_size
                ld    bc,4
                ldir
                pop   hl
                push  hl                       ; start cluster (word @ 0x1A)
                ld    de,#1A
                add   hl,de
                ld    a,(hl)
                ld    (fs_ent_clus),a
                inc   hl
                ld    a,(hl)
                ld    (fs_ent_clus+1),a
                pop   hl

                ld    a,(fs_ent_idx)
                inc   a
                ld    (fs_ent_idx),a
                scf
                ret
fdn_skip
                ld    a,(fs_ent_idx)
                inc   a
                ld    (fs_ent_idx),a
                jp    fdn_loop
fdn_end
                or    a                         ; CF clear = end of directory
                ret

; ---------------------------------------------------------------------------
; fside_load_file: load the file named in fs_req_name (11-byte 8.3) into the
; buffer at (fs_load_dst). CF set = loaded (fs_ent_size = byte size), NC = not
; found. Follows the FAT16 cluster chain. 16-bit LBA (files in the first 32MB).
fside_load_file
                call  fside_dir_first         ; also sets fs_spc/fat_lba/data_lba
flf_find
                jr    nc,flf_notfound         ; end of directory
                call  flf_cmpname             ; fs_ent_name == fs_req_name?
                jr    z,flf_found
                call  fside_dir_next
                jr    flf_find
flf_notfound
flf_toobig
                or    a
                ret
flf_found                                      ; fs_ent_clus + fs_ent_size set
                ld    hl,(fs_load_max)        ; size > caller's buffer? refuse
                ld    de,(fs_ent_size)
                or    a
                sbc   hl,de
                jr    c,flf_toobig
                ld    hl,(fs_ent_size)        ; sectors = ceil(size/512)
                ld    de,511
                add   hl,de
                ld    b,9
flf_sh          srl   h
                rr    l
                djnz  flf_sh
                ld    (flf_secs),hl
                ld    hl,(fs_ent_clus)
                ld    (flf_clus),hl
                xor   a
                ld    (flf_sic),a
flf_loop
                ld    hl,(flf_secs)
                ld    a,h
                or    l
                jr    z,flf_done
                ld    hl,(flf_clus)           ; LBA = data_lba+(clus-2)*spc+sic
                dec   hl
                dec   hl
                call  flf_mul_spc
                ld    de,(fs_data_lba)
                add   hl,de
                ld    a,(flf_sic)
                ld    e,a
                ld    d,0
                add   hl,de
                call  fs_read_sector
                ld    hl,fs_secbuf            ; copy sector to dst
                ld    de,(fs_load_dst)
                ld    bc,512
                ldir
                ld    (fs_load_dst),de
                ld    hl,(flf_secs)
                dec   hl
                ld    (flf_secs),hl
                ld    a,(flf_sic)             ; advance sector-in-cluster
                inc   a
                ld    b,a
                ld    a,(fs_spc)
                cp    b
                jr    nz,flf_keepsic
                call  flf_fat_next            ; cluster boundary -> next cluster
                xor   a
                ld    (flf_sic),a
                jr    flf_loop
flf_keepsic
                ld    a,b
                ld    (flf_sic),a
                jr    flf_loop
flf_done
                scf
                ret

flf_cmpname                                    ; fs_ent_name == fs_req_name? Z if so
                ld    hl,fs_ent_name
                ld    de,fs_req_name
                ld    b,11
flf_cn
                ld    a,(de)
                cp    (hl)
                ret   nz
                inc   hl
                inc   de
                djnz  flf_cn
                xor   a
                ret

flf_mul_spc                                    ; HL *= fs_spc (power of 2)
                ld    a,(fs_spc)
                ld    b,0
flf_log         srl   a
                jr    z,flf_doshift
                inc   b
                jr    flf_log
flf_doshift     inc   b
flf_dec         dec   b
                ret   z
                add   hl,hl
                jr    flf_dec

flf_fat_next                                   ; flf_clus -> next cluster (FAT16)
                ld    hl,(flf_clus)
                ld    a,h                       ; fat_sector = fat_lba + clus/256
                ld    l,a
                ld    h,0
                ld    de,(fs_fat_lba)
                add   hl,de
                call  fs_read_sector
                ld    a,(flf_clus)             ; within = (clus & 255) * 2
                ld    l,a
                ld    h,0
                add   hl,hl
                ld    de,fs_secbuf
                add   hl,de
                ld    a,(hl)
                ld    e,a
                inc   hl
                ld    a,(hl)
                ld    d,a
                ld    (flf_clus),de
                ret

; ---------------------------------------------------------------------------
; fs_read_sector: read one 512-byte sector, LBA in HL (16-bit), into fs_secbuf.
fs_read_sector
                push  hl
                ld    a,#E0                    ; LBA mode, master, LBA27-24 = 0
                ld    bc,FS_IDE_DEV
                out   (c),a
                ld    a,1
                ld    bc,FS_IDE_SCNT
                out   (c),a
                pop   hl
                ld    a,l
                ld    bc,FS_IDE_LBAL
                out   (c),a
                ld    a,h
                ld    bc,FS_IDE_LBAM
                out   (c),a
                xor   a
                ld    bc,FS_IDE_LBAH
                out   (c),a
                ld    a,#20                    ; READ SECTORS
                ld    bc,FS_IDE_CMD
                out   (c),a
frs_poll
                ld    bc,FS_IDE_STAT
                in    a,(c)
                bit   3,a                       ; wait for DRQ
                jr    z,frs_poll
                ld    hl,fs_secbuf
                ld    de,512
                ld    bc,FS_IDE_DATA
frs_read
                in    a,(c)
                ld    (hl),a
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,frs_read
                ret

; --- state (per-entry output fields fs_ent_* live in lib/fs.asm) ----------
fs_root_lba     defw  0
fs_root_secs    defb  0
fs_cur_sec      defb  0
fs_ent_idx      defb  0
fs_ent_clus     defw  0            ; current entry's start cluster
fs_spc          defb  0            ; sectors per cluster (file-read geometry)
fs_fat_lba      defw  0            ; FAT start LBA
fs_data_lba     defw  0            ; data region start LBA
flf_secs        defw  0            ; load: sectors remaining
flf_clus        defw  0            ; load: current cluster
flf_sic         defb  0            ; load: sector within the cluster
fs_secbuf       defs  512
