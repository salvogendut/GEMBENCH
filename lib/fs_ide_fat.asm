; ---------------------------------------------------------------------------
; lib/fs_ide_fat.asm - storage backend: FAT32 over the SYMBiFACE II / Cyboard
; IDE interface. Reads the volume straight off the IDE controller. Selected by
; lib/fs.asm when an IDE is present.
;
; This file is the RESIDENT half: the FAT32 *read* path (directory walk + file
; load) plus the shared core (lib/fs_fat32_core.asm). The *write* path is large
; and only needed on a save, so it lives in a paged module (kernel/modules/
; gbfat.asm) loaded on demand; fside_save_file is a thin stub that marshals the
; inputs into low RAM and calls it.
;
; Backend entry points (the floppy backend exposes matching fsam_* names so the
; dispatcher in lib/fs.asm can route to either):
;   fside_dir_first -> CF set = first entry ready in fs_ent_*, NC = empty
;   fside_dir_next  -> CF set = next entry ready,              NC = end of dir
;   fside_load_file -> CF set = loaded (fs_ent_size bytes),    NC = not found
;   fside_save_file -> CF set = saved (create or overwrite),   NC = failed
; Per-entry output fields fs_ent_name/attr/size live in lib/fs.asm (shared).
;
; IDE port map (from 1984 src/ide.c; port = &FD00 | reg):
;   &FD0A scnt  &FD0B lbaL  &FD0C lbaM  &FD0D lbaH  &FD0E dev  &FD0F cmd/status
;   &FD08 data (1 byte per IN).  READ SECTORS = &20, status: 7=BSY 3=DRQ 0=ERR.
; ---------------------------------------------------------------------------

FS_IDE_SCNT     equ   #FD0A
FS_IDE_LBAL     equ   #FD0B
FS_IDE_LBAM     equ   #FD0C
FS_IDE_LBAH     equ   #FD0D
FS_IDE_DEV      equ   #FD0E
FS_IDE_CMD      equ   #FD0F
FS_IDE_STAT     equ   #FD0F
FS_IDE_DATA     equ   #FD08

; Paged FAT32 write module (kernel/modules/gbfat.asm). The resident stub marshals
; the save into this low-RAM transfer area (reachable while the module is paged
; into the #4000-#7FFF window), loads the module to GBFAT_LOAD, and CALLs it.
GBFAT_LEN       equ   #1400        ; bytes to write (word)
GBFAT_NAME      equ   #1402        ; 8.3 name (11 bytes)
GBFAT_RES       equ   #140D        ; result: 1 = saved, 0 = failed
GBFAT_DATA      equ   #2200        ; staged data (<= GBFAT_MAX bytes)
GBFAT_MAX       equ   #1C00        ; 7 KB staging cap (fits #2200..#3DFF in low RAM)
GBFAT_LOAD      equ   #5000        ; module load address (above the font/icons)

                include "fs_fat32_core.asm"

; ---------------------------------------------------------------------------
; fside_dir_first: return the first valid entry of the CURRENT directory. The
; volume is mounted once (fs_mount sets fs_dir_clus = root); re-listing afterwards
; rewinds whatever directory fs_dir_clus points at (so gb_chdir/gb_back persist
; across re-lists instead of snapping back to root). See issue #54.
fside_dir_first
                ld    a,(fs_mounted)
                or    a
                jr    nz,fsdf_rewind
                call  fs_mount               ; first time: BPB + root cluster
                ld    a,1
                ld    (fs_mounted),a
fsdf_rewind
                call  fs_dir_rewind           ; rewind the current directory
                jp    fdn_loop                 ; scan for the first valid entry

; ---------------------------------------------------------------------------
; fside_dir_next: scan forward for the next valid 8.3 entry, walking the root
; directory's cluster chain across sectors.
fside_dir_next
fdn_loop
                ld    a,(fs_ent_idx)
                cp    16                       ; 16 entries per 512-byte sector
                jr    c,fdn_have
                call  fs_dir_step              ; advance to the next dir sector
                jp    nc,fdn_end               ; end of directory chain
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
                jr    nz,fdn_skip              ; volume label / directory-as-label
                ld    a,(hl)                   ; hide '.' and '..' (dir self / parent)
                cp    '.'
                jr    z,fdn_skip

                push  hl                       ; valid -> copy fields out
                ld    de,fs_ent_name
                ld    bc,11
                ldir
                pop   hl
                ld    a,b                       ; attr saved in B
                ld    (fs_ent_attr),a
                push  hl
                ld    de,#1C                    ; size (4 bytes @ 0x1C)
                add   hl,de
                ld    de,fs_ent_size
                ld    bc,4
                ldir
                pop   hl
                push  hl                       ; cluster: low word @0x1A
                ld    de,#1A
                add   hl,de
                ld    a,(hl)
                ld    (fs_ent_clus),a
                inc   hl
                ld    a,(hl)
                ld    (fs_ent_clus+1),a
                pop   hl
                push  hl                       ; cluster: high word @0x14
                ld    de,#14
                add   hl,de
                ld    a,(hl)
                ld    (fs_ent_clus+2),a
                inc   hl
                ld    a,(hl)
                ld    (fs_ent_clus+3),a
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
; buffer at (fs_load_dst). CF set = loaded (fs_ent_size set), NC = not found.
fside_load_file
                call  fside_dir_first
flf_find
                jr    nc,flf_notfound
                call  flf_cmpname
                jr    z,flf_found
                call  fside_dir_next
                jr    flf_find
flf_notfound
                or    a
                ret
flf_found
                ld    hl,(fs_load_max)        ; size > caller's buffer? refuse
                ld    de,(fs_ent_size)
                or    a
                sbc   hl,de
                jr    c,flf_notfound
                ld    hl,(fs_ent_size)        ; sectors = ceil(size/512)
                ld    de,511
                add   hl,de
                ld    b,9
flf_sh          srl   h
                rr    l
                djnz  flf_sh
                ld    (flf_secs),hl
                ld    hl,fs_ent_clus          ; flf_clus = start cluster (32-bit)
                ld    de,flf_clus
                ld    bc,4
                ldir
                xor   a
                ld    (flf_sic),a
flf_loop
                ld    hl,(flf_secs)
                ld    a,h
                or    l
                jr    z,flf_done
                ld    hl,flf_clus             ; LBA = cluster base + sector-in-cluster
                call  clus_first_lba
                ld    a,(flf_sic)
                call  lba_add_a
                call  fs_read_sector
                ld    hl,fs_secbuf            ; copy the sector to the destination
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
                ld    hl,flf_clus             ; cluster boundary -> next cluster
                call  fs_fat_next
                jr    nc,flf_done             ; chain ended early -> stop
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

; ---------------------------------------------------------------------------
; fside_save_file: stub. Marshal the name/data/len into the low-RAM transfer area
; (the caller's page is still mapped, so the data is read directly here), then
; page in PAGE_DATA, load the GBFAT.BIN write module to GBFAT_LOAD via the read
; path, and CALL it. CF set = saved. Files larger than GBFAT_MAX are refused.
fside_save_file
                ld    hl,(fs_save_len)        ; refuse > GBFAT_MAX (staging buffer)
                ld    de,GBFAT_MAX
                or    a
                sbc   hl,de
                jr    nc,fsvm_fail
                ld    hl,(fs_save_src)        ; copy the data out of the caller's page
                ld    de,GBFAT_DATA           ; into low RAM (caller's page mapped now)
                ld    bc,(fs_save_len)
                ld    a,b
                or    c
                jr    z,fsvm_nlen
                ldir
fsvm_nlen
                ld    hl,fs_req_name          ; name + length -> the transfer area
                ld    de,GBFAT_NAME
                ld    bc,11
                ldir
                ld    hl,(fs_save_len)
                ld    (GBFAT_LEN),hl
                ld    a,(bank_cur)            ; page in PAGE_DATA, load + run the module
                push  af
                ld    a,PAGE_DATA
                call  bank_set
                ld    hl,gbfat_modname        ; fs_req_name = "GBFAT   BIN"
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    hl,#2000
                ld    (fs_load_max),hl
                ld    hl,GBFAT_LOAD
                ld    (fs_load_dst),hl
                call  fs_load_file           ; load GBFAT.BIN -> #5000 (above icons)
                jr    nc,fsvm_unload           ; module missing -> fail
                call  GBFAT_LOAD             ; run it (reads low RAM, writes the IDE)
fsvm_unload
                pop   af
                call  bank_set
                ld    a,(GBFAT_RES)         ; result byte -> CF
                or    a
                ret   z
                scf
                ret
fsvm_fail
                or    a
                ret
gbfat_modname   db    "GBFAT   BIN"          ; 8.3, space-padded

; --- read-path state (shared core state lives in fs_fat32_core.asm) -------
fs_mounted      defb  0            ; 0 until the volume is mounted once (#54)
fs_dir_sp       defb  0            ; directory stack depth (chdir/back)
fs_dir_stack    defs  16           ; 4 parent clusters (4 bytes each)
flf_clus        defs  4            ; load: current file cluster
fs_ent_clus     defs  4            ; selected entry's start cluster
flf_sic         defb  0            ; load: sector within current cluster
flf_secs        defw  0            ; load: sectors remaining
