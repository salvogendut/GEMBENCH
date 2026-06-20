; ---------------------------------------------------------------------------
; lib/fs_fat32_core.asm - shared FAT32 core (geometry, sector I/O, cluster math)
;
; INCLUDED by both the resident IDE backend (lib/fs_ide_fat.asm, for reads) and
; the paged FAT32 write module (kernel/modules/gbfat.asm, for writes), so the
; mount / sector / cluster-chain logic is written once. Each includer keeps its
; own copy of this code+state (separate assemblies), sharing only the IDE ports,
; the low-RAM sector buffer (fs_secbuf), and the transfer area.
;
; The includer MUST define before the include: the FS_IDE_* port equates and
; fs_secbuf (the 512-byte sector buffer address). Per-entry output fields
; fs_ent_name/attr/size and fs_req_name live in lib/fs.asm (resident only).
;
; FAT16_ONLY (#148): pass -DFAT16_ONLY=1 to omit the FAT32 read branches and
; assume a FAT16 volume - real CPC IDE/SD cards are FAT16 (#130). Smaller
; resident reader for the real-hardware GBIDE; the dev/test FAT32 images need a
; full build. The paged write module (gbfat.asm) never sets it (keeps FAT32).
; ---------------------------------------------------------------------------
                ifndef FAT16_ONLY
FAT16_ONLY      equ   0
                endif
; STORAGE_M4 (#174): when set, this build's fs_read_sector calls the M4 driver
; (lib/fs_m4.asm) instead of the in-RAM IDE ATA code. Defaulted here so the
; standalone gbfat.asm write-module assembly (no STORAGE_M4 on the command line)
; still parses the dispatch below.
                ifndef STORAGE_M4
STORAGE_M4      equ   0
                endif

; fs_mount: MBR/partition probe + FAT32 BPB -> fs_fat_lba, fs_data_lba, fs_spc,
; fs_clshift, fs_numfat, fs_dir_clus (root cluster). No directory scan.
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

                ld    hl,(fs_secbuf+#16)      ; #130: 16-bit sectors/FAT - nonzero => FAT16
       if FAT16_ONLY
                ld    (fatsz_tmp),hl          ; FAT16 assumed: this word is fatsz
                xor   a
                ld    (fatsz_tmp+2),a
                ld    (fatsz_tmp+3),a
                inc   a
                ld    (fs_is_fat16),a          ; = 1 (the runtime checks still read it)
       else
                ld    a,h
                or    l
                jr    z,fdf_fat32
                ld    (fatsz_tmp),hl          ; FAT16: fatsz = this word (zero-extended to 32)
                xor   a
                ld    (fatsz_tmp+2),a
                ld    (fatsz_tmp+3),a
                inc   a                        ; a = 1
                ld    (fs_is_fat16),a
                jr    fdf_havefatsz
fdf_fat32
                ld    hl,fs_secbuf+#24        ; FAT32: sectors per FAT (32-bit)
                ld    de,fatsz_tmp
                call  copy4
                xor   a
                ld    (fs_is_fat16),a
       endif
fdf_havefatsz
                ld    a,(fs_secbuf+#10)       ; acc += numFATs*fatsz -> FAT32 data start, or
                ld    (fs_numfat),a           ; FAT16 fixed-root-dir start (acc still = fat_lba)
                ld    b,a
fdf_dl          push  bc
                ld    hl,fatsz_tmp
                call  acc_add
                pop   bc
                djnz  fdf_dl

       if !FAT16_ONLY
                ld    a,(fs_is_fat16)
                or    a
                jr    nz,fdf_root16
                call  acc_store_data          ; FAT32: data starts right after the FATs
                ld    hl,fs_secbuf+#2C        ; root directory start cluster
                ld    de,fs_dir_clus
                call  copy4
                ret
       endif
fdf_root16                                     ; FAT16: the fixed root dir sits here; data follows
                ld    hl,acc                  ; fs_root_lba = fat_lba + numFATs*fatsz
                ld    de,fs_root_lba
                call  copy4
                ld    hl,(fs_secbuf+#11)      ; root entry count (16-bit)
                ld    de,15                    ; root_secs = (entries+15) >> 4
                add   hl,de                    ; (32 bytes/entry, 512/sector -> /16)
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                ld    (fs_root_secs),a
                ld    e,a                       ; data_lba = root_lba + root_secs
                ld    d,0
                call  acc_add16
                call  acc_store_data
                ld    hl,0                     ; #134: FAT16 root has no cluster - mark
                ld    (fs_dir_clus),hl         ; fs_dir_clus = 0 as the root sentinel; a
                ld    (fs_dir_clus+2),hl       ; subdirectory gets its (nonzero) start cluster
                ret

; fs_dir_rewind: position at the first sector of the root directory cluster.
fs_dir_rewind
                xor   a
                ld    (fs_dir_sic),a
                ld    (fs_ent_idx),a
                ld    a,(fs_is_fat16)         ; #130
                or    a
                jr    nz,fdr_fat16
fdr_cluster                                    ; FAT32, or a FAT16 subdirectory: cluster chain
                ld    hl,fs_dir_clus
                call  clus_first_lba
                call  save_dir_lba
                jp    fs_read_sector
fdr_fat16                                      ; FAT16: zero cluster = fixed root region; a
                ld    hl,fs_dir_clus          ; nonzero cluster is a subdirectory chain (#134)
                ld    a,(hl)
                inc   hl
                or    (hl)
                inc   hl
                or    (hl)
                inc   hl
                or    (hl)
                jr    nz,fdr_cluster
                ld    hl,fs_root_lba          ; FAT16 root: the fixed root dir region
                call  lbatmp_from_var
                call  save_dir_lba
                jp    fs_read_sector
save_dir_lba                                    ; remember the dir sector now in secbuf
                ld    hl,lba_tmp
                ld    de,fs_dir_cur_lba
                call  copy4
                ret

; fs_dir_step: advance to the next directory sector (within the cluster, else
; follow the FAT to the next cluster). CF set = sector loaded, NC = end of chain.
fs_dir_step
                ld    a,(fs_is_fat16)         ; #130
                or    a
                jr    z,fds_cluster
                ld    hl,fs_dir_clus          ; #134: FAT16 zero cluster = fixed root; a
                ld    a,(hl)                  ; nonzero cluster is a subdirectory chain
                inc   hl
                or    (hl)
                inc   hl
                or    (hl)
                inc   hl
                or    (hl)
                jr    z,fds_fat16
fds_cluster                                    ; FAT32, or a FAT16 subdirectory: cluster step
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
fds_addread                                    ; shared tail: lba_tmp += sic, then read it
                ld    a,(fs_dir_sic)
                call  lba_add_a
                call  save_dir_lba
                call  fs_read_sector
                scf
                ret
fds_end
                or    a
                ret
fds_fat16                                      ; #130 FAT16: walk the fixed root region in order
                ld    a,(fs_dir_sic)
                inc   a
                ld    (fs_dir_sic),a
                ld    b,a
                ld    a,(fs_root_secs)         ; sic >= root_secs -> end of root directory
                cp    b
                jr    z,fds_end
                jr    c,fds_end
                ld    hl,fs_root_lba
                call  lbatmp_from_var
                jr    fds_addread

; fs_fat_next: HL -> 4-byte cluster variable. Replace it with the next cluster
; in the FAT32 chain. CF set = valid next cluster, NC = end-of-chain (>=EOC).
fs_fat_next
                ld    (fn_ptr),hl
                call  acc_load                ; acc = cluster
                call  acc_shl                  ; *2 (FAT16 byte offset)
       if !FAT16_ONLY
                ld    a,(fs_is_fat16)         ; #130
                or    a
                jr    nz,ffn_within
                call  acc_shl                  ; *4 (FAT32 byte offset)
ffn_within
       endif
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
                ld    a,(hl)                   ; low two bytes (FAT16 and FAT32 share these)
                ld    (acc),a
                inc   hl
                ld    a,(hl)
                ld    (acc+1),a
       if FAT16_ONLY
                xor   a                         ; FAT16: the high two bytes are always 0
                ld    (acc+2),a
                ld    (acc+3),a
       else
                ld    a,(fs_is_fat16)         ; #130
                or    a
                jr    nz,ffn_eoc16
                inc   hl                        ; FAT32: two more bytes (28-bit entry)
                ld    a,(hl)
                ld    (acc+2),a
                inc   hl
                ld    a,(hl)
                and   #0F
                ld    (acc+3),a
                ld    a,(acc+3)                ; FAT32: end-of-chain if >= 0x0FFFFFF8
                cp    #0F
                jr    c,fn_valid
                ld    a,(acc+2)
                cp    #FF
                jr    c,fn_valid
       endif
ffn_eoc_lo                                      ; shared low-word EOC test (FAT16 joins here)
                ld    a,(acc+1)
                cp    #FF
                jr    c,fn_valid
                ld    a,(acc)
                cp    #F8
                jr    c,fn_valid
                or    a                         ; EOC -> NC
                ret
       if !FAT16_ONLY
ffn_eoc16                                       ; #130 FAT16: clear the high bytes -> a 16-bit
                xor   a                         ; value, then EOC if >= 0xFFF8 via the shared test
                ld    (acc+2),a
                ld    (acc+3),a
                jr    ffn_eoc_lo
       endif
fn_valid
                ld    hl,acc
                ld    de,(fn_ptr)
                call  copy4
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

; fs_read_sector: read one 512-byte sector at lba_tmp (24-bit LBA) into fs_secbuf.
; Both status waits are bounded (DE down to 0) so a drive left mid-operation by
; UniDOS/FatFS fails out instead of hanging forever.
fs_read_sector
                ifdef GB_ROM                  ; #152: this build's IDE driver lives in GEOBENCH.ROM
                ld    a,(gb_rom_num)          ; 0xFF = ROM not found -> fail (no in-RAM copy here)
                inc   a
                ret   z
                jp    gb_rom_call             ; reads lba_tmp -> fs_secbuf from the ROM copy
                else
                if STORAGE_M4                 ; #174: M4 build reads sectors via the M4 driver
                jp    fsm4_read_sector
                else
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
                endif                          ; STORAGE_M4 (#174: else = the in-RAM IDE ATA body)
                endif                          ; GB_ROM (in-RAM driver only in non-ROM builds, #152)

; fs_detect_part: fs_secbuf holds LBA 0. Set fs_part_lba (32-bit) to the first
; MBR partition's start LBA, or 0 for a superfloppy (FAT BPB directly at LBA 0).
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
                call  copy4
                ret
fdp_none
                jp    clear_part_lba

; copy4 (#134 reclaim): HL -> DE, 4 bytes. Shared by the FAT cluster/LBA/acc
; copies (was an inline ld bc,4 + ldir at ~26 sites).
copy4
                ld    bc,4
                ldir
                ret

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
                call  copy4
                ret
acc_load                                        ; HL -> 4-byte source; acc = (HL)
                ld    de,acc
                call  copy4
                ret
acc_to_lba                                      ; lba_tmp = acc
                ld    hl,acc
                ld    de,lba_tmp
                call  copy4
                ret
acc_store_fat                                   ; fs_fat_lba = acc
                ld    hl,acc
                ld    de,fs_fat_lba
                call  copy4
                ret
acc_store_data                                  ; fs_data_lba = acc
                ld    hl,acc
                ld    de,fs_data_lba
                call  copy4
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

; --- shared core state ---------------------------------------------------
; lba_tmp is a FIXED low-RAM addr (free gap #124A-#12FF) so GEOBENCH.ROM's copy of
; fs_read_sector reads the same bytes (#152); fat_eoc is a read-only constant (fine
; in ROM). The rest is WRITABLE scratch: in the GEOBENCH.ROM build (FS_STATE_LOWRAM)
; it must live in low RAM (ROM is read-only), so it is equ'd off FS_STATE_BASE; the
; resident/paged builds keep the original `defs` (this `else` branch is unchanged).
lba_tmp         equ   #1250
                ifndef FS_STATE_LOWRAM           ; FS_STATE_LOWRAM builds define the state at fixed
                                                 ; low RAM in lib/fs_fat_lowram.inc (#152)
fs_part_lba     defs  4            ; partition base LBA (0 = superfloppy)
fs_fat_lba      defs  4            ; absolute FAT start LBA
fs_data_lba     defs  4            ; absolute data region start LBA
fs_dir_clus     defs  4            ; current root-dir cluster
acc             defs  4            ; 32-bit work accumulator
fatsz_tmp       defs  4            ; sectors per FAT (geometry calc)
fs_dir_cur_lba  defs  4            ; LBA of the dir sector currently in secbuf
fn_ptr          defw  0            ; fs_fat_next: cluster-var pointer
fn_within       defw  0            ; fs_fat_next: FAT entry offset in sector
fs_spc          defb  0            ; sectors per cluster
fs_clshift      defb  0            ; log2(sectors per cluster)
fs_dir_sic      defb  0            ; dir: sector within current cluster
fs_ent_idx      defb  0            ; dir: entry index within current sector
fs_numfat       defb  0            ; number of FAT copies
fs_is_fat16     defb  0            ; #130: 1 = FAT16 volume (fixed root dir, 16-bit FAT), else FAT32
fs_root_lba     defs  4            ; #130 FAT16: absolute LBA of the fixed root directory
fs_root_secs    defb  0            ; #130 FAT16: root directory size in sectors
fat_eoc         defb  #FF,#FF,#FF,#0F  ; FAT32 end-of-chain marker
                endif
