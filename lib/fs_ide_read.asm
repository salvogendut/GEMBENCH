; ---------------------------------------------------------------------------
; lib/fs_ide_read.asm - the IDE FAT *read* backend (directory listing + file load),
; extracted from lib/fs_ide_fat.asm so it can run from GEOBENCH.ROM (#152). Uses the
; shared FAT core (lib/fs_fat32_core.asm: fs_mount, fs_dir_rewind/step, clus_first_lba,
; fs_fat_next, fs_read_sector, lba_add_a, copy4) which the includer provides. Included
; by the non-ROM resident (via fs_ide_fat.asm) and by the ROM (rom/geobench_rom.asm,
; after gbfat.asm pulls in the core). In the GB_ROM resident build these entry points
; are replaced by thin ROM-call stubs in fs_ide_fat.asm.
;
; Backend interface (see lib/fs.asm):
;   fside_dir_first -> CF set = first entry in fs_ent_*, NC = empty
;   fside_dir_next  -> CF set = next entry,               NC = end of dir
;   fside_load_file -> CF set = loaded (fs_ent_size set), NC = not found
; ---------------------------------------------------------------------------

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

                ld    a,b                       ; attr -> fs_ent_attr NOW, before the
                ld    (fs_ent_attr),a           ; name ldir below clobbers B (BC count)
                push  hl                       ; valid -> copy fields out
                ld    de,fs_ent_name
                ld    bc,11
                ldir
                pop   hl
                push  hl
                ld    de,#1C                    ; size (4 bytes @ 0x1C)
                add   hl,de
                ld    de,fs_ent_size
                call  copy4
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
                call  copy4
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
