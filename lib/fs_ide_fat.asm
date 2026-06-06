; ---------------------------------------------------------------------------
; lib/fs_ide_fat.asm - storage backend: FAT32 over the SYMBiFACE II / Cyboard
; IDE interface. Reads the volume straight off the IDE controller, with no
; AMSDOS/UniDOS involvement. Selected by lib/fs.asm when an IDE is present.
;
; The real-world target is a large FAT32 disk (e.g. a 1 GB CF card shared with
; UniDOS/SymbOS), so this backend speaks FAT32 with 32-bit cluster numbers and
; issues 24-bit LBA reads (files land high on a near-full disk, well past the
; 16-bit LBA range). An MBR partition table is honoured; a superfloppy (FAT BPB
; directly at LBA 0) is treated as partition base 0.
;
; Backend entry points (the floppy backend exposes the matching fsam_* names so
; the dispatcher in lib/fs.asm can route to either):
;   fside_dir_first -> CF set = first entry ready in fs_ent_*, NC = empty
;   fside_dir_next  -> CF set = next entry ready,              NC = end of dir
;   fside_load_file -> CF set = loaded (fs_ent_size bytes),    NC = not found
;   fside_save_file -> CF set = saved (create or overwrite),   NC = failed
; The save path allocates clusters, writes both FAT copies, and the directory
; entry directly over the IDE ports (FSInfo free-count is left untouched - it is
; advisory and FatFs/fsck tolerate drift).
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

; ---------------------------------------------------------------------------
; fside_dir_first: mount the volume (MBR/partition probe + FAT32 BPB) and return
; the first valid directory entry.
fside_dir_first
                call  fs_mount
                call  fs_dir_rewind           ; load the first root-dir sector
                jp    fdn_loop                 ; scan for the first valid entry

; fs_mount: MBR/partition probe + FAT32 BPB -> fs_fat_lba, fs_data_lba, fs_spc,
; fs_clshift, fs_dir_clus (root cluster). No directory scan.
fs_mount
                call  clear_part_lba          ; probe the MBR at ABSOLUTE LBA 0
                call  clear_lba_tmp
                call  fs_read_sector
                call  fs_detect_part          ; -> fs_part_lba (0 = superfloppy)

                ld    hl,fs_part_lba          ; read the FAT32 BPB at the volume base
                call  lbatmp_from_var
                call  fs_read_sector

                ld    a,(fs_secbuf+#0D)       ; sectors per cluster + its log2
                ld    (fs_spc),a
                ld    b,0
fdf_log         srl   a
                jr    z,fdf_logd
                inc   b
                jr    fdf_log
fdf_logd        ld    a,b
                ld    (fs_clshift),a

                ld    hl,fs_part_lba          ; fat_lba = part_base + reserved sectors
                call  acc_load
                ld    de,(fs_secbuf+#0E)
                call  acc_add16
                call  acc_store_fat

                ld    hl,fs_secbuf+#24        ; sectors per FAT (FAT32, 32-bit)
                ld    de,fatsz_tmp
                ld    bc,4
                ldir
                ld    a,(fs_secbuf+#10)       ; data_lba = fat_lba + numFATs*fatsz
                ld    (fs_numfat),a
                ld    b,a                       ; (acc still holds fat_lba)
fdf_dl          push  bc
                ld    hl,fatsz_tmp
                call  acc_add
                pop   bc
                djnz  fdf_dl
                call  acc_store_data

                ld    hl,fs_secbuf+#2C        ; root directory start cluster
                ld    de,fs_dir_clus
                ld    bc,4
                ldir
                ret

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

; fs_dir_rewind: position at the first sector of the root directory cluster.
fs_dir_rewind
                xor   a
                ld    (fs_dir_sic),a
                ld    (fs_ent_idx),a
                ld    hl,fs_dir_clus
                call  clus_first_lba
                call  save_dir_lba
                jp    fs_read_sector
save_dir_lba                                    ; remember the dir sector now in secbuf
                ld    hl,lba_tmp
                ld    de,fs_dir_cur_lba
                ld    bc,4
                ldir
                ret

; fs_dir_step: advance to the next directory sector (within the cluster, else
; follow the FAT to the next cluster). CF set = sector loaded, NC = end of chain.
fs_dir_step
                ld    a,(fs_dir_sic)
                inc   a
                ld    b,a
                ld    a,(fs_spc)
                cp    b
                jr    z,fds_nextclus
                jr    c,fds_nextclus
                ld    a,b                       ; still inside the cluster
                ld    (fs_dir_sic),a
                jr    fds_load
fds_nextclus
                ld    hl,fs_dir_clus
                call  fs_fat_next
                jr    nc,fds_end
                xor   a
                ld    (fs_dir_sic),a
fds_load
                ld    hl,fs_dir_clus
                call  clus_first_lba
                ld    a,(fs_dir_sic)
                call  lba_add_a
                call  save_dir_lba
                call  fs_read_sector
                scf
                ret
fds_end
                or    a
                ret

; ---------------------------------------------------------------------------
; fside_save_file: write fs_save_len bytes from (fs_save_src) to a file named
; fs_req_name on the FAT32 volume (create or overwrite in place). The source page
; stays mapped (k_fssave), so the data is read directly. CF set = saved.
; Bounds: <= 32 KB (sane for the editor) to keep the cluster loop simple.
fside_save_file
                ld    hl,(fs_save_len)        ; refuse absurdly large saves
                ld    de,#8000
                or    a
                sbc   hl,de
                jp    nc,fes_fail
                call  fs_mount

                ld    a,(fs_clshift)          ; clbytes = 512<<clshift; nclus =
                add   a,9                      ; ceil(len/clbytes) = (len+clbytes-1)>>(9+clshift)
                ld    b,a                       ; B = shift count (9..)
                ld    hl,(fs_save_len)
                ld    de,1                      ; clbytes-1 = (1<<(9+clshift))-1
fes_m1          sla   e
                rl    d
                djnz  fes_m1
                dec   de                        ; DE = clbytes-1
                add   hl,de                     ; HL = len + clbytes-1
                ld    a,(fs_clshift)
                add   a,9
                ld    b,a
fes_m2          srl   h
                rr    l
                djnz  fes_m2
                ld    a,h                        ; nclus must be >=1 (even a 0-byte file
                or    l                          ; gets one cluster)
                jr    nz,fes_nc_ok
                ld    hl,1
fes_nc_ok       ld    (sav_nclus),hl

                call  fs_dir_find_slot          ; locate existing entry or a free slot
                jp    nc,fes_fail               ; directory full

                ld    a,(sav_found)             ; overwrite? free the old cluster chain
                or    a
                jr    z,fes_alloc
                ld    hl,sav_old_clus
                call  fs_free_chain
fes_alloc
                ld    hl,(fs_save_src)          ; source cursor + remaining bytes
                ld    (sav_src),hl
                ld    hl,(fs_save_len)
                ld    (sav_rem),hl
                xor   a                          ; sav_prev_clus = 0 (no previous link)
                ld    (sav_prev_clus),a
                ld    (sav_prev_clus+1),a
                ld    (sav_prev_clus+2),a
                ld    (sav_prev_clus+3),a
                ld    (sav_have_prev),a
                ld    hl,(sav_nclus)
                ld    (sav_left),hl
fes_loop
                ld    hl,(sav_left)
                ld    a,h
                or    l
                jr    z,fes_dirent
                call  fs_alloc_cluster          ; alloc_clus = a free cluster (now EOC)
                jp    nc,fes_fail               ; disk full
                ld    a,(sav_have_prev)         ; link prev -> this (first time: record start)
                or    a
                jr    nz,fes_link
                ld    hl,alloc_clus             ; first cluster = file start
                ld    de,sav_first_clus
                ld    bc,4
                ldir
                jr    fes_setprev
fes_link
                ld    hl,sav_prev_clus          ; fat_set(prev, alloc_clus)
                ld    de,fat_set_clus
                ld    bc,4
                ldir
                ld    hl,alloc_clus
                ld    de,fat_set_val
                ld    bc,4
                ldir
                call  fs_fat_set
fes_setprev
                ld    hl,alloc_clus             ; prev = this
                ld    de,sav_prev_clus
                ld    bc,4
                ldir
                ld    a,1
                ld    (sav_have_prev),a
                call  sav_write_cluster_data    ; write spc sectors from the source
                ld    hl,(sav_left)
                dec   hl
                ld    (sav_left),hl
                jr    fes_loop
fes_dirent
                call  sav_write_dirent          ; commit the directory entry
                scf
                ret
fes_fail
                or    a
                ret

; sav_write_cluster_data: write fs_spc sectors of cluster alloc_clus, pulling from
; (sav_src)/sav_rem, zero-padding the tail.
sav_write_cluster_data
                ld    hl,alloc_clus
                call  clus_first_lba            ; lba_tmp = first sector of the cluster
                ld    a,(fs_spc)
                ld    (swc_left),a
swc_loop
                ld    hl,fs_secbuf              ; build one sector: up to 512 src bytes
                ld    de,512
swc_fill
                ld    a,d                        ; 512 bytes per sector
                or    e
                jr    z,swc_full
                push  de
                ld    de,(sav_rem)              ; any source bytes left?
                ld    a,d
                or    e
                pop   de
                jr    z,swc_pad
                ld    a,(sav_src)               ; *src -> sector (advance src, dec rem)
                push  hl
                ld    hl,(sav_src)
                ld    a,(hl)
                inc   hl
                ld    (sav_src),hl
                pop   hl
                ld    (hl),a
                ld    bc,(sav_rem)
                dec   bc
                ld    (sav_rem),bc
                jr    swc_next
swc_pad
                xor   a
                ld    (hl),a
swc_next
                inc   hl
                dec   de
                jr    swc_fill
swc_full
                call  fs_write_sector           ; flush the sector
                ld    hl,lba_tmp                ; next sector LBA
                inc   (hl)
                jr    nz,swc_noc
                inc   hl
                inc   (hl)
                jr    nz,swc_noc
                inc   hl
                inc   (hl)
swc_noc
                ld    a,(swc_left)
                dec   a
                ld    (swc_left),a
                jr    nz,swc_loop
                ret

; sav_write_dirent: write the 8.3 entry (name, archive attr, start cluster, size)
; into the directory sector recorded by fs_dir_find_slot, then flush it.
sav_write_dirent
                ld    hl,sav_ent_lba            ; reload the directory sector
                call  lbatmp_from_var
                call  fs_read_sector
                ld    hl,(sav_ent_off)          ; entry = secbuf + offset
                ld    de,fs_secbuf
                add   hl,de
                push  hl
                ex    de,hl                      ; DE -> entry
                ld    hl,fs_req_name            ; 11-byte name
                ld    bc,11
                ldir
                ld    a,#20                      ; attribute = archive
                ld    (de),a
                pop   hl                         ; HL -> entry base
                ld    de,#14                      ; cluster high word @ 0x14
                add   hl,de
                ld    a,(sav_first_clus+2)
                ld    (hl),a
                inc   hl
                ld    a,(sav_first_clus+3)
                ld    (hl),a
                ld    hl,(sav_ent_off)           ; cluster low word @ 0x1A
                ld    de,fs_secbuf+#1A
                add   hl,de
                ld    a,(sav_first_clus)
                ld    (hl),a
                inc   hl
                ld    a,(sav_first_clus+1)
                ld    (hl),a
                ld    hl,(sav_ent_off)           ; size (4 bytes) @ 0x1C
                ld    de,fs_secbuf+#1C
                add   hl,de
                ld    de,(fs_save_len)
                ld    (hl),e
                inc   hl
                ld    (hl),d
                inc   hl
                xor   a
                ld    (hl),a
                inc   hl
                ld    (hl),a
                jp    fs_write_sector

; fs_dir_find_slot: walk the root directory. If an entry named fs_req_name exists,
; set sav_found=1 with its location (sav_ent_lba/off) and start cluster
; (sav_old_clus). Otherwise pick the first free slot (deleted or the 0x00 end) and
; leave sav_found=0. CF set = a usable slot was found, NC = directory full.
fs_dir_find_slot
                xor   a
                ld    (sav_found),a
                ld    (sav_free_ok),a
                call  fs_dir_rewind
dfs_sec
                ld    b,0
dfs_ent
                ld    a,b                        ; entry ptr = secbuf + idx*32
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                push  hl                          ; HL = offset within sector
                ld    de,fs_secbuf
                add   hl,de                       ; HL -> entry
                ld    a,(hl)
                or    a
                jr    z,dfs_endmark               ; 0x00 = end of directory
                cp    #E5
                jr    z,dfs_free                  ; deleted -> free slot candidate
                push  hl
                ld    de,#0B
                add   hl,de
                ld    a,(hl)
                pop   hl
                and   #0F
                cp    #0F
                jr    z,dfs_cont                  ; LFN fragment -> not a candidate
                push  hl                          ; compare 11-byte name
                ld    de,fs_req_name
                ld    c,11
dfs_cmp
                ld    a,(de)
                cp    (hl)
                jr    nz,dfs_nomatch
                inc   hl
                inc   de
                dec   c
                jr    nz,dfs_cmp
                pop   hl                          ; MATCH -> existing entry
                ld    a,1
                ld    (sav_found),a
                pop   de                          ; DE = offset within sector
                ld    (sav_ent_off),de
                call  dfs_store_lba
                ld    bc,#1A                      ; old start cluster: low @0x1A hi @0x14
                add   hl,bc
                ld    a,(hl)
                ld    (sav_old_clus),a
                inc   hl
                ld    a,(hl)
                ld    (sav_old_clus+1),a
                ld    hl,fs_secbuf+#14
                ld    de,(sav_ent_off)
                add   hl,de
                ld    a,(hl)
                ld    (sav_old_clus+2),a
                inc   hl
                ld    a,(hl)
                ld    (sav_old_clus+3),a
                scf
                ret
dfs_nomatch
                pop   hl
                jr    dfs_cont
dfs_free
                ld    a,(sav_free_ok)            ; remember the first free slot only
                or    a
                jr    nz,dfs_cont
                ld    a,1
                ld    (sav_free_ok),a
                pop   hl                          ; HL = offset
                ld    (sav_ent_off),hl
                push  hl
                call  dfs_store_lba
                jr    dfs_cont
dfs_endmark
                ld    a,(sav_free_ok)            ; 0x00 end: use it if no slot yet
                or    a
                jr    nz,dfs_use_free
                pop   hl                          ; HL = offset
                ld    (sav_ent_off),hl
                call  dfs_store_lba
                jr    dfs_use_free2
dfs_use_free
                pop   hl
dfs_use_free2
                xor   a                            ; new entry, no existing match
                ld    (sav_found),a
                scf
                ret
dfs_cont
                pop   hl
                inc   b
                ld    a,b
                cp    16
                jp    c,dfs_ent
                call  fs_dir_step
                jp    c,dfs_sec
                ld    a,(sav_free_ok)             ; chain ended: use a recorded free slot
                or    a
                jr    z,dfs_full
                xor   a
                ld    (sav_found),a
                scf
                ret
dfs_full
                or    a
                ret
dfs_store_lba                                      ; sav_ent_lba = fs_dir_cur_lba
                ld    hl,fs_dir_cur_lba
                ld    de,sav_ent_lba
                ld    bc,4
                ldir
                ret

; fs_free_chain: HL -> 4-byte start cluster. Set every cluster in the chain to 0
; (free) in the FAT. Stops at EOC or a reserved (<2) cluster.
fs_free_chain
                ld    de,fc_clus
                ld    bc,4
                ldir
fc_loop
                ld    a,(fc_clus+1)
                or    a
                jr    nz,fc_go
                ld    a,(fc_clus+2)
                or    a
                jr    nz,fc_go
                ld    a,(fc_clus+3)
                or    a
                jr    nz,fc_go
                ld    a,(fc_clus)
                cp    2
                ret   c                            ; cluster 0/1 -> stop
fc_go
                ld    hl,fc_clus                   ; cur = fc_clus
                ld    de,fc_cur
                ld    bc,4
                ldir
                ld    hl,fc_clus                   ; fc_clus = next (CF) / NC = was EOC
                call  fs_fat_next
                push  af
                ld    hl,fc_cur                    ; free cur: fat_set(cur, 0)
                ld    de,fat_set_clus
                ld    bc,4
                ldir
                call  clear_fat_set_val
                call  fs_fat_set
                pop   af
                jr    nc,fc_done
                jr    fc_loop
fc_done
                ret

; fs_alloc_cluster: scan the FAT for the first free cluster (>=2), mark it EOC, and
; leave it in alloc_clus. CF set = allocated, NC = disk full.
fs_alloc_cluster
                ld    hl,fs_fat_lba              ; FAT sector cursor + cluster counter
                ld    de,alloc_seclba
                ld    bc,4
                ldir
                xor   a
                ld    (alloc_scan),a
                ld    (alloc_scan+1),a
                ld    (alloc_scan+2),a
                ld    (alloc_scan+3),a
                ld    hl,(fatsz_tmp)             ; sectors to scan (fatsz fits 16-bit)
                ld    (alloc_secs),hl
fac_sec
                ld    hl,(alloc_secs)
                ld    a,h
                or    l
                jp    z,fac_full
                ld    hl,alloc_seclba
                call  lbatmp_from_var
                call  fs_read_sector
                ld    ix,fs_secbuf
                ld    b,128                       ; 128 entries per FAT sector
fac_ent
                ld    a,(alloc_scan+1)            ; cluster >= 2? (skip reserved 0/1)
                or    a
                jr    nz,fac_chk
                ld    a,(alloc_scan+2)
                or    a
                jr    nz,fac_chk
                ld    a,(alloc_scan+3)
                or    a
                jr    nz,fac_chk
                ld    a,(alloc_scan)
                cp    2
                jr    c,fac_next
fac_chk
                ld    a,(ix+0)                    ; entry free? (low 28 bits all zero)
                or    (ix+1)
                or    (ix+2)
                ld    c,a
                ld    a,(ix+3)
                and   #0F
                or    c
                jr    nz,fac_next
                ld    hl,alloc_scan              ; FREE -> alloc_clus = cluster
                ld    de,alloc_clus
                ld    bc,4
                ldir
                ld    de,fat_set_clus            ; mark EOC so the chain terminates and
                ld    bc,4                        ; the next alloc skips it
                ld    hl,alloc_clus
                ldir
                ld    hl,fat_eoc
                ld    de,fat_set_val
                ld    bc,4
                ldir
                call  fs_fat_set
                scf
                ret
fac_next
                ld    hl,alloc_scan              ; cluster counter++
                inc   (hl)
                jr    nz,fac_n2
                inc   hl
                inc   (hl)
                jr    nz,fac_n2
                inc   hl
                inc   (hl)
                jr    nz,fac_n2
                inc   hl
                inc   (hl)
fac_n2
                ld    de,4                         ; next entry
                add   ix,de
                djnz  fac_ent
                ld    hl,alloc_seclba             ; next FAT sector
                inc   (hl)
                jr    nz,fac_s2
                inc   hl
                inc   (hl)
                jr    nz,fac_s2
                inc   hl
                inc   (hl)
fac_s2
                ld    hl,(alloc_secs)
                dec   hl
                ld    (alloc_secs),hl
                jp    fac_sec
fac_full
                or    a
                ret

; fs_fat_set: write fat_set_val (32-bit, low 28 bits) into the FAT entry for
; cluster fat_set_clus, in every FAT copy. Preserves each entry's top nibble.
fs_fat_set
                ld    hl,fat_set_clus
                call  acc_load
                call  acc_shl
                call  acc_shl                    ; acc = cluster*4 (byte offset)
                ld    a,(acc)
                ld    (fn_within),a
                ld    a,(acc+1)
                and   1
                ld    (fn_within+1),a
                call  acc_shr8
                call  acc_shr1                   ; acc = offset>>9 (sector within a FAT)
                ld    hl,fs_fat_lba
                call  acc_add                    ; acc = FAT copy 0 sector LBA
                ld    a,(fs_numfat)
                ld    b,a
ffs_copy
                push  bc
                call  acc_to_lba
                call  fs_read_sector
                ld    hl,(fn_within)
                ld    de,fs_secbuf
                add   hl,de
                ld    a,(fat_set_val)
                ld    (hl),a
                inc   hl
                ld    a,(fat_set_val+1)
                ld    (hl),a
                inc   hl
                ld    a,(fat_set_val+2)
                ld    (hl),a
                inc   hl
                ld    a,(hl)                      ; preserve the reserved top nibble
                and   #F0
                ld    c,a
                ld    a,(fat_set_val+3)
                and   #0F
                or    c
                ld    (hl),a
                call  fs_write_sector
                ld    hl,fatsz_tmp               ; advance to the next FAT copy
                call  acc_add
                pop   bc
                djnz  ffs_copy
                ret
clear_fat_set_val
                xor   a
                ld    (fat_set_val),a
                ld    (fat_set_val+1),a
                ld    (fat_set_val+2),a
                ld    (fat_set_val+3),a
                ret

; fs_write_sector: write fs_secbuf to the sector at lba_tmp (24-bit LBA). Bounded
; status waits, mirroring fs_read_sector.
fs_write_sector
                ld    de,0
fxw_bsy
                ld    bc,FS_IDE_STAT
                in    a,(c)
                bit   7,a
                jr    z,fxw_bsyok
                dec   de
                ld    a,d
                or    e
                jr    nz,fxw_bsy
                ret
fxw_bsyok
                ld    a,(lba_tmp+3)
                and   #0F
                or    #E0
                ld    bc,FS_IDE_DEV
                out   (c),a
                ld    a,1
                ld    bc,FS_IDE_SCNT
                out   (c),a
                ld    a,(lba_tmp)
                ld    bc,FS_IDE_LBAL
                out   (c),a
                ld    a,(lba_tmp+1)
                ld    bc,FS_IDE_LBAM
                out   (c),a
                ld    a,(lba_tmp+2)
                ld    bc,FS_IDE_LBAH
                out   (c),a
                ld    a,#30                       ; WRITE SECTORS
                ld    bc,FS_IDE_CMD
                out   (c),a
                ld    de,0
fxw_drqw
                ld    bc,FS_IDE_STAT
                in    a,(c)
                bit   0,a
                jr    nz,fxw_done
                bit   3,a
                jr    nz,fxw_go
                dec   de
                ld    a,d
                or    e
                jr    nz,fxw_drqw
                ret
fxw_go
                ld    hl,fs_secbuf
                ld    de,512
                ld    bc,FS_IDE_DATA
fxw_wr
                ld    a,(hl)
                out   (c),a
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,fxw_wr
                ld    de,0                         ; wait for the write to complete
fxw_busy
                ld    bc,FS_IDE_STAT
                in    a,(c)
                bit   7,a
                jr    z,fxw_done
                dec   de
                ld    a,d
                or    e
                jr    nz,fxw_busy
fxw_done
                ret

; ---------------------------------------------------------------------------
; fside_load_file: load the file named in fs_req_name (11-byte 8.3) into the
; buffer at (fs_load_dst). CF set = loaded (fs_ent_size set), NC = not found.
; Follows the FAT32 cluster chain with 24-bit LBA reads.
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
; fs_fat_next: HL -> 4-byte cluster variable. Replace it with the next cluster
; in the FAT32 chain. CF set = valid next cluster, NC = end-of-chain (>=EOC).
fs_fat_next
                ld    (fn_ptr),hl
                call  acc_load                ; acc = cluster
                call  acc_shl                  ; *4 -> FAT byte offset
                call  acc_shl
                ld    a,(acc)                  ; within = offset & 0x1FF
                ld    (fn_within),a
                ld    a,(acc+1)
                and   1
                ld    (fn_within+1),a
                call  acc_shr8                 ; acc = offset >> 9 (FAT sector index)
                call  acc_shr1
                ld    hl,fs_fat_lba
                call  acc_add                  ; acc = absolute FAT sector LBA
                call  acc_to_lba
                call  fs_read_sector
                ld    hl,(fn_within)           ; entry = secbuf + within
                ld    de,fs_secbuf
                add   hl,de
                ld    a,(hl)
                ld    (acc),a
                inc   hl
                ld    a,(hl)
                ld    (acc+1),a
                inc   hl
                ld    a,(hl)
                ld    (acc+2),a
                inc   hl
                ld    a,(hl)
                and   #0F                       ; FAT32 entries are 28-bit
                ld    (acc+3),a
                ld    a,(acc+3)                ; end-of-chain if >= 0x0FFFFFF8
                cp    #0F
                jr    c,fn_valid
                ld    a,(acc+2)
                cp    #FF
                jr    c,fn_valid
                ld    a,(acc+1)
                cp    #FF
                jr    c,fn_valid
                ld    a,(acc)
                cp    #F8
                jr    c,fn_valid
                or    a                         ; EOC -> NC
                ret
fn_valid
                ld    hl,acc
                ld    de,(fn_ptr)
                ld    bc,4
                ldir
                scf
                ret

; clus_first_lba: HL -> 4-byte cluster var. lba_tmp = data_lba + (clus-2)<<clshift
; (the first sector of the cluster; the caller adds the sector-in-cluster).
clus_first_lba
                call  acc_load
                call  acc_sub2
                ld    a,(fs_clshift)
                or    a
                jr    z,cfl_done
                ld    b,a
cfl_shl         push  bc
                call  acc_shl
                pop   bc
                djnz  cfl_shl
cfl_done
                ld    hl,fs_data_lba
                call  acc_add
                jp    acc_to_lba

; ---------------------------------------------------------------------------
; fs_read_sector: read one 512-byte sector at lba_tmp (24-bit LBA) into
; fs_secbuf. Both status waits are bounded (DE down to 0) so a drive left
; mid-operation by UniDOS/FatFS fails out instead of hanging forever; callers
; fall back to defaults on an unfilled buffer.
fs_read_sector
                ld    de,0                     ; wait BSY=0 before commanding
frs_bsy
                ld    bc,FS_IDE_STAT
                in    a,(c)
                bit   7,a
                jr    z,frs_bsyok
                dec   de
                ld    a,d
                or    e
                jr    nz,frs_bsy
                ret                             ; timeout: buffer untouched
frs_bsyok
                ld    a,(lba_tmp+3)            ; LBA 27-24 in the device register
                and   #0F
                or    #E0                       ; LBA mode, master
                ld    bc,FS_IDE_DEV
                out   (c),a
                ld    a,1
                ld    bc,FS_IDE_SCNT
                out   (c),a
                ld    a,(lba_tmp)
                ld    bc,FS_IDE_LBAL
                out   (c),a
                ld    a,(lba_tmp+1)
                ld    bc,FS_IDE_LBAM
                out   (c),a
                ld    a,(lba_tmp+2)
                ld    bc,FS_IDE_LBAH
                out   (c),a
                ld    a,#20                     ; READ SECTORS
                ld    bc,FS_IDE_CMD
                out   (c),a
                ld    de,0                       ; wait DRQ, bail on ERR/timeout
frs_poll
                ld    bc,FS_IDE_STAT
                in    a,(c)
                bit   0,a
                jr    nz,frs_fail
                bit   3,a
                jr    nz,frs_drq
                dec   de
                ld    a,d
                or    e
                jr    nz,frs_poll
frs_fail
                ret                             ; error/timeout: buffer untouched
frs_drq
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

; fs_detect_part: fs_secbuf holds LBA 0. Set fs_part_lba (32-bit) to the first
; MBR partition's start LBA, or 0 for a superfloppy (FAT BPB directly at LBA 0).
; A FAT boot sector starts with a jump (0xEB); an MBR does not, ends 55 AA, and
; has a non-zero partition type at offset 446+4.
fs_detect_part
                ld    a,(fs_secbuf)
                cp    #EB
                jr    z,fdp_none
                ld    a,(fs_secbuf+#1FE)
                cp    #55
                jr    nz,fdp_none
                ld    a,(fs_secbuf+#1FF)
                cp    #AA
                jr    nz,fdp_none
                ld    a,(fs_secbuf+#1C2)       ; partition 0 type; 0 = unused
                or    a
                jr    z,fdp_none
                ld    hl,fs_secbuf+#1C6        ; partition 0 start LBA (4 bytes)
                ld    de,fs_part_lba
                ld    bc,4
                ldir
                ret
fdp_none
                jp    clear_part_lba

; --- 32-bit helpers (operate on the 4-byte little-endian accumulator acc) ----
clear_part_lba
                xor   a
                ld    (fs_part_lba),a
                ld    (fs_part_lba+1),a
                ld    (fs_part_lba+2),a
                ld    (fs_part_lba+3),a
                ret
clear_lba_tmp
                xor   a
                ld    (lba_tmp),a
                ld    (lba_tmp+1),a
                ld    (lba_tmp+2),a
                ld    (lba_tmp+3),a
                ret
lbatmp_from_var                                ; HL -> 4-byte source; lba_tmp = (HL)
                ld    de,lba_tmp
                ld    bc,4
                ldir
                ret
acc_load                                        ; HL -> 4-byte source; acc = (HL)
                ld    de,acc
                ld    bc,4
                ldir
                ret
acc_to_lba                                      ; lba_tmp = acc
                ld    hl,acc
                ld    de,lba_tmp
                ld    bc,4
                ldir
                ret
acc_store_fat                                   ; fs_fat_lba = acc
                ld    hl,acc
                ld    de,fs_fat_lba
                ld    bc,4
                ldir
                ret
acc_store_data                                  ; fs_data_lba = acc
                ld    hl,acc
                ld    de,fs_data_lba
                ld    bc,4
                ldir
                ret
acc_add                                         ; acc += (HL)  [HL -> 4-byte LE]
                ld    de,acc
                or    a
                ld    b,4
acc_add_l
                ld    a,(de)
                adc   a,(hl)
                ld    (de),a
                inc   de
                inc   hl
                djnz  acc_add_l
                ret
acc_add16                                       ; acc += DE (16-bit)
                ld    hl,acc
                ld    a,(hl)
                add   a,e
                ld    (hl),a
                inc   hl
                ld    a,(hl)
                adc   a,d
                ld    (hl),a
                inc   hl
                ld    a,(hl)
                adc   a,0
                ld    (hl),a
                inc   hl
                ld    a,(hl)
                adc   a,0
                ld    (hl),a
                ret
acc_sub2                                        ; acc -= 2
                ld    hl,acc
                ld    a,(hl)
                sub   2
                ld    (hl),a
                ret   nc
asd_b
                inc   hl
                ld    a,(hl)
                sub   1
                ld    (hl),a
                ret   nc
                jr    asd_b
acc_shl                                         ; acc <<= 1
                ld    hl,acc
                or    a
                rl    (hl)
                inc   hl
                rl    (hl)
                inc   hl
                rl    (hl)
                inc   hl
                rl    (hl)
                ret
acc_shr8                                        ; acc >>= 8 (byte shuffle)
                ld    hl,acc+1
                ld    de,acc
                ld    bc,3
                ldir
                xor   a
                ld    (acc+3),a
                ret
acc_shr1                                        ; acc >>= 1 (logical, 32-bit)
                ld    hl,acc+3
                or    a
                srl   (hl)
                dec   hl
                rr    (hl)
                dec   hl
                rr    (hl)
                dec   hl
                rr    (hl)
                ret
lba_add_a                                       ; lba_tmp += A (8-bit, carry up)
                ld    hl,lba_tmp
                add   a,(hl)
                ld    (hl),a
                ret   nc
laa_c
                inc   hl
                inc   (hl)
                ret   nz
                jr    laa_c

; --- state (per-entry output fields fs_ent_* live in lib/fs.asm) ----------
fs_part_lba     defs  4            ; partition base LBA (0 = superfloppy)
fs_fat_lba      defs  4            ; absolute FAT start LBA
fs_data_lba     defs  4            ; absolute data region start LBA
fs_dir_clus     defs  4            ; current root-dir cluster
flf_clus        defs  4            ; current file cluster
fs_ent_clus     defs  4            ; selected entry's start cluster
acc             defs  4            ; 32-bit work accumulator
lba_tmp         defs  4            ; LBA staged for fs_read_sector
fatsz_tmp       defs  4            ; sectors per FAT (geometry calc)
fn_ptr          defw  0            ; fs_fat_next: cluster-var pointer
fn_within       defw  0            ; fs_fat_next: FAT entry offset in sector
fs_spc          defb  0            ; sectors per cluster
fs_clshift      defb  0            ; log2(sectors per cluster)
fs_dir_sic      defb  0            ; dir: sector within current cluster
flf_sic         defb  0            ; load: sector within current cluster
fs_ent_idx      defb  0            ; dir: entry index within current sector
flf_secs        defw  0            ; load: sectors remaining
fs_numfat       defb  0            ; number of FAT copies
fs_dir_cur_lba  defs  4            ; LBA of the dir sector currently in secbuf
fat_eoc         defb  #FF,#FF,#FF,#0F  ; FAT32 end-of-chain marker
; --- write path scratch ---
alloc_clus      defs  4            ; fs_alloc_cluster result
alloc_seclba    defs  4            ; FAT scan: current sector LBA
alloc_scan      defs  4            ; FAT scan: current cluster number
alloc_secs      defw  0            ; FAT scan: sectors remaining
fat_set_clus    defs  4            ; fs_fat_set: target cluster
fat_set_val     defs  4            ; fs_fat_set: value to store
fc_clus         defs  4            ; fs_free_chain: walk cursor
fc_cur          defs  4            ; fs_free_chain: cluster being freed
sav_nclus       defw  0            ; save: clusters needed
sav_left        defw  0            ; save: clusters remaining to write
sav_first_clus  defs  4            ; save: file start cluster
sav_prev_clus   defs  4            ; save: previous cluster (for linking)
sav_have_prev   defb  0            ; save: a previous cluster exists
sav_src         defw  0            ; save: source data cursor
sav_rem         defw  0            ; save: source bytes remaining
sav_found       defb  0            ; dir slot: 1 = existing entry, 0 = new
sav_free_ok     defb  0            ; dir slot: a free slot was recorded
sav_ent_lba     defs  4            ; dir slot: entry's sector LBA
sav_ent_off     defw  0            ; dir slot: entry offset within the sector
sav_old_clus    defs  4            ; dir slot: existing entry's start cluster
swc_left        defb  0            ; sector-write loop counter
; fs_secbuf (the 512-byte sector buffer) is defined after kern_end in gbkern.asm
; so it is excluded from the loaded GBKERN.BIN image - scratch RAM filled at run
; time. The fside_save_file paged-module path (GBFAT) is retired until FAT32
; write lands; the equates below remain for the build's module packaging.
GBFAT_LEN       equ   #1400
GBFAT_NAME      equ   #1402
GBFAT_RES       equ   #140D
GBFAT_DATA      equ   #1800
GBFAT_LOAD      equ   #5000
