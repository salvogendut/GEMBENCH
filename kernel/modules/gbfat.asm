; ---------------------------------------------------------------------------
; kernel/modules/gbfat.asm - FAT32/IDE *write* path, as a paged kernel module.
;
; The resident kernel keeps the FAT32 read path; the write path is large and only
; needed on a save, so it lives here and is loaded on demand into the free upper
; part of PAGE_DATA (above the font/icons) and CALLed at GBFAT_ORG. It shares the
; FAT32 core (lib/fs_fat32_core.asm) with the resident reader - one source, two
; assemblies - and is self-contained otherwise: its own state + the shared low-RAM
; sector buffer (fs_secbuf), reading its inputs from the transfer area the
; resident stub fills (reachable while this code is paged into #4000-#7FFF):
;
;   GBFAT_LEN  (#1700, word)   bytes to write
;   GBFAT_NAME (#1702, 11)     8.3 name
;   GBFAT_RES  (#170D, byte)   result: 1 = saved, 0 = failed
;   GBFAT_DATA (#2200, <=6.5KiB) data copied out of the app's page by the stub
;
; Build: tools/build_fatmod.sh -> build/GBFAT.RAW, packaged on the disk as
; GBFAT.BIN (and copied onto the IDE volume).
; ---------------------------------------------------------------------------

GBFAT_ORG       equ   #6000        ; in PAGE_DATA, above the font+icon set (#88: the
                                   ; 15-icon set reached #534C and collided with #5000)
GBFAT_LEN       equ   #1700
GBFAT_NAME      equ   #1702
GBFAT_RES       equ   #170D
GBFAT_OP        equ   #170E        ; operation: 0 = save, 1 = delete (#62)
GBFAT_DIR       equ   #170F        ; directory cluster (4 bytes) to operate in
GBFAT_DATA      equ   #2200

FS_IDE_SCNT     equ   #FD0A
FS_IDE_LBAL     equ   #FD0B
FS_IDE_LBAM     equ   #FD0C
FS_IDE_LBAH     equ   #FD0D
FS_IDE_DEV      equ   #FD0E
FS_IDE_CMD      equ   #FD0F
FS_IDE_STAT     equ   #FD0F
FS_IDE_DATA     equ   #FD08

fs_secbuf       equ   #1800        ; shared low-RAM sector buffer (resident agrees)

                ifndef GBFAT_AS_INCLUDE       ; #152: the ROM build includes this body at
                org   GBFAT_ORG               ; #C000+ and supplies its own org/save; the paged
                endif                          ; module keeps org #6000 + the GBFAT.RAW save.

; entry: dispatch on GBFAT_OP (0 = save, 1 = delete), store the result, return.
gbfat_entry
                ld    a,(GBFAT_OP)
                or    a
                jr    nz,ge_delete
                call  gbfat_save
                jr    ge_res
ge_delete
                call  gbfat_delete
ge_res
                ld    a,1
                jr    c,gf_setres
                xor   a
gf_setres
                ld    (GBFAT_RES),a
                ret

; gbfat_delete: remove the file named GBFAT_NAME from the directory at cluster
; GBFAT_DIR - free its cluster chain and mark the directory entry deleted (0xE5).
; Refuses directories (only files). CF set = deleted.
gbfat_delete
                call  fs_mount                   ; geometry (also sets fs_dir_clus=root)
                ld    hl,GBFAT_DIR              ; operate in the requested directory
                ld    de,fs_dir_clus
                ld    bc,4
                ldir
                call  fs_dir_find_slot          ; locate GBFAT_NAME
                ret   nc                          ; directory walk failed
                ld    a,(sav_found)
                or    a
                jr    z,gd_fail                   ; name not present
                ld    hl,sav_ent_lba             ; check the entry's attribute: refuse
                call  lbatmp_from_var             ; directories (would orphan contents)
                call  fs_read_sector
                ld    hl,(sav_ent_off)
                ld    de,fs_secbuf+#0B           ; attr byte at offset 0x0B
                add   hl,de
                ld    a,(hl)
                and   #10
                jr    nz,gd_fail                  ; directory -> refuse
                ld    hl,sav_old_clus            ; free the file's cluster chain
                call  fs_free_chain               ; (this reuses fs_secbuf)
                ld    hl,sav_ent_lba             ; reload the dir sector and mark the
                call  lbatmp_from_var             ; entry deleted
                call  fs_read_sector
                ld    hl,(sav_ent_off)
                ld    de,fs_secbuf
                add   hl,de
                ld    (hl),#E5
                call  fs_write_sector
                scf
                ret
gd_fail
                or    a
                ret

; ---------------------------------------------------------------------------
; gbfat_save: write GBFAT_LEN bytes from GBFAT_DATA to a file named GBFAT_NAME on
; the FAT32 volume (create or overwrite in place). CF set = saved.
gbfat_save
                call  fs_mount                   ; geometry (also sets fs_dir_clus=root)
                ld    hl,GBFAT_DIR              ; operate in the requested directory, not
                ld    de,fs_dir_clus           ; root (#142: saves were landing in root)
                ld    bc,4
                ldir
                ld    a,(fs_clshift)          ; clbytes = 512<<clshift; nclus =
                add   a,9                      ; ceil(len/clbytes) = (len+clbytes-1)>>(9+clshift)
                ld    b,a
                ld    hl,(GBFAT_LEN)
                ld    de,1                      ; clbytes-1 = (1<<(9+clshift))-1
fes_m1          sla   e
                rl    d
                djnz  fes_m1
                dec   de
                add   hl,de
                ld    a,(fs_clshift)
                add   a,9
                ld    b,a
fes_m2          srl   h
                rr    l
                djnz  fes_m2
                ld    a,h                        ; nclus must be >=1 (even a 0-byte file)
                or    l
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
                ld    hl,GBFAT_DATA            ; source cursor + remaining bytes
                ld    (sav_src),hl
                ld    hl,(GBFAT_LEN)
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
                ld    a,(sav_have_prev)         ; link prev -> this (first: record start)
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
                push  hl                         ; *src -> sector (advance src, dec rem)
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
                ld    hl,lba_tmp                ; next sector LBA (24-bit)
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
                ld    hl,GBFAT_NAME            ; 11-byte name
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
                ld    de,(GBFAT_LEN)
                ld    (hl),e
                inc   hl
                ld    (hl),d
                inc   hl
                xor   a
                ld    (hl),a
                inc   hl
                ld    (hl),a
                jp    fs_write_sector

; fs_dir_find_slot: walk the root directory. If an entry named GBFAT_NAME exists,
; set sav_found=1 with its location (sav_ent_lba/off) and start cluster
; (sav_old_clus). Otherwise pick the first free slot. CF set = usable slot.
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
                ld    de,GBFAT_NAME
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
                call  dfs_store_lba               ; (clobbers HL/BC - recompute below)
                ld    hl,fs_secbuf+#1A            ; old start cluster: low word @0x1A
                ld    de,(sav_ent_off)
                add   hl,de
                ld    a,(hl)
                ld    (sav_old_clus),a
                inc   hl
                ld    a,(hl)
                ld    (sav_old_clus+1),a
                ld    hl,fs_secbuf+#14            ; high word @0x14
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

                include "../../lib/fs_fat32_core.asm"

; --- write-path state ---------------------------------------------------
; #152: in the ROM build (FS_STATE_LOWRAM) this scratch must live in low RAM (ROM is
; read-only) - equ'd off the core's FS_CORE_STATE_END so it packs right after the core
; state. The paged module keeps the original `defs` in its bank RAM (else branch).
                ifdef FS_STATE_LOWRAM
GBFAT_STATE     equ   FS_CORE_STATE_END        ; gbfat scratch follows the core state
alloc_clus      equ   GBFAT_STATE+0
alloc_seclba    equ   GBFAT_STATE+4
alloc_scan      equ   GBFAT_STATE+8
alloc_secs      equ   GBFAT_STATE+12
fat_set_clus    equ   GBFAT_STATE+14
fat_set_val     equ   GBFAT_STATE+18
fc_clus         equ   GBFAT_STATE+22
fc_cur          equ   GBFAT_STATE+26
sav_nclus       equ   GBFAT_STATE+30
sav_left        equ   GBFAT_STATE+32
sav_first_clus  equ   GBFAT_STATE+34
sav_prev_clus   equ   GBFAT_STATE+38
sav_have_prev   equ   GBFAT_STATE+42
sav_src         equ   GBFAT_STATE+43
sav_rem         equ   GBFAT_STATE+45
sav_found       equ   GBFAT_STATE+47
sav_free_ok     equ   GBFAT_STATE+48
sav_ent_lba     equ   GBFAT_STATE+49
sav_ent_off     equ   GBFAT_STATE+53
sav_old_clus    equ   GBFAT_STATE+55
swc_left        equ   GBFAT_STATE+59           ; ends at GBFAT_STATE+60
                else
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
                endif

                ifndef GBFAT_AS_INCLUDE
                save  "build/GBFAT.RAW",GBFAT_ORG,$-GBFAT_ORG
                endif
