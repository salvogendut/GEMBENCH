; ---------------------------------------------------------------------------
; lib/fs_ide_fat.asm - storage backend: FAT16 over the SYMBiFACE II / Cyboard
; IDE interface. Reads the root directory straight off the IDE controller, with
; no AMSDOS/UniDOS involvement.
;
; Backend-agnostic interface (a floppy/AMSDOS backend would expose the same
; names so the desktop never knows which storage it is talking to):
;   fs_dir_first -> CF set = first entry ready in fs_ent_*, NC = directory empty
;   fs_dir_next  -> CF set = next entry ready,              NC = end of directory
; Per-entry fields filled by each call:
;   fs_ent_name  11 bytes  (8.3, space padded, exactly as stored on disc)
;   fs_ent_attr   1 byte   (FAT attribute byte)
;   fs_ent_size   4 bytes  (little-endian file size)
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
; fs_dir_first: mount the volume (read BPB, locate the root directory) and
; return the first valid entry.
fs_dir_first
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

                xor   a
                ld    (fs_cur_sec),a
                ld    (fs_ent_idx),a
                ld    hl,(fs_root_lba)        ; load the first root-dir sector
                call  fs_read_sector
                jp    fdn_loop                 ; scan for the first valid entry

; ---------------------------------------------------------------------------
; fs_dir_next: scan forward (across sectors) for the next valid 8.3 entry.
fs_dir_next
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

; --- state / output ------------------------------------------------------
fs_root_lba     defw  0
fs_root_secs    defb  0
fs_cur_sec      defb  0
fs_ent_idx      defb  0
fs_ent_name     defs  11
fs_ent_attr     defb  0
fs_ent_size     defs  4
fs_secbuf       defs  512
