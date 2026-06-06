; ---------------------------------------------------------------------------
; kernel/modules/gbfat.asm - FAT16/IDE write, as a paged kernel module.
;
; The resident kernel keeps the FAT16 *read* path; this is the *write* path,
; which is large and IDE-only, so it lives in a module loaded on demand into the
; free upper part of PAGE_DATA (above the font/icons) and CALLed at GBFAT_ORG.
; Self-contained: it mounts the volume, does its own sector I/O over the IDE
; ports, and has its own 512-byte sector buffer - so it never needs the resident
; kernel's data, only the inputs the resident stub leaves in low RAM (resident,
; still reachable while this code is paged into the #4000-#7FFF window):
;
;   GBFAT_LEN  (#1400, word)   bytes to write
;   GBFAT_NAME (#1402, 11)     8.3 name
;   GBFAT_RES  (#140D, byte)   result: 1 = saved, 0 = failed
;   GBFAT_DATA (#1800, <=8KB)  the data, copied out of the app's page by the stub
;
; Build: tools/build_fatmod.sh -> build/GBFAT.RAW, packaged on the disk as
; GBFAT.BIN (and copied onto the IDE volume).
; ---------------------------------------------------------------------------

GBFAT_ORG       equ   #5000
GBFAT_LEN       equ   #1400
GBFAT_NAME      equ   #1402
GBFAT_RES       equ   #140D
GBFAT_DATA      equ   #1800

FS_IDE_SCNT     equ   #FD0A
FS_IDE_LBAL     equ   #FD0B
FS_IDE_LBAM     equ   #FD0C
FS_IDE_LBAH     equ   #FD0D
FS_IDE_DEV      equ   #FD0E
FS_IDE_CMD      equ   #FD0F
FS_IDE_STAT     equ   #FD0F
FS_IDE_DATA     equ   #FD08

                org   GBFAT_ORG

; entry: run the save, store the result byte, return to the kernel.
                call  gbfat_save
                ld    a,1
                jr    c,gf_setres
                xor   a
gf_setres
                ld    (GBFAT_RES),a
                ret

; ---------------------------------------------------------------------------
; gbfat_save: write GBFAT_LEN bytes from GBFAT_DATA to GBFAT_NAME. CF set = saved.
gbfat_save
                call  gf_mount               ; geometry from the BPB
                ld    hl,(GBFAT_LEN)         ; sectors = ceil(len / 512)
                ld    de,511
                add   hl,de
                ld    b,9
gf_shs          srl   h
                rr    l
                djnz  gf_shs
                ld    (gf_secs),hl
                ld    a,(gf_spc)             ; clusters = ceil(secs / spc)
                dec   a
                ld    e,a
                ld    d,0
                ld    hl,(gf_secs)
                add   hl,de
                call  gf_div_spc
                ld    (gf_nclus),hl
                call  gf_find                ; entry / free slot
                ret   nc                      ; root directory full
                call  gf_free_old            ; overwrite -> release old chain
                ld    hl,0
                ld    (gf_first),hl
                ld    hl,(gf_nclus)
                ld    a,h
                or    l
                jr    z,gf_putdir            ; zero-length file
                call  gf_alloc_chain
                ret   nc                      ; disk full
                call  gf_write_data
gf_putdir
                call  gf_put_entry
                scf
                ret

; ---------------------------------------------------------------------------
; gf_mount: read the BPB and compute root_lba, root_secs, spc, fat_lba, data_lba.
gf_mount
                ld    hl,0
                call  gf_read_sector
                ld    hl,0                    ; root_lba = reserved + fats*spf
                ld    a,(gf_secbuf+#10)
                ld    b,a
                ld    de,(gf_secbuf+#16)      ; sectors per FAT
                ld    (gf_spf),de
gf_mfat
                add   hl,de
                djnz  gf_mfat
                ld    de,(gf_secbuf+#0E)
                add   hl,de
                ld    (gf_root_lba),hl
                ld    hl,(gf_secbuf+#11)      ; root entries / 16 = sectors
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
                jr    nz,gf_mrs
                inc   a
gf_mrs
                ld    (gf_root_secs),a
                ld    a,(gf_secbuf+#0D)
                ld    (gf_spc),a
                ld    hl,(gf_secbuf+#0E)
                ld    (gf_fat_lba),hl
                ld    hl,(gf_root_lba)
                ld    a,(gf_root_secs)
                ld    e,a
                ld    d,0
                add   hl,de
                ld    (gf_data_lba),hl
                ret

; gf_div_spc: HL /= gf_spc (power of two).
gf_div_spc
                ld    a,(gf_spc)
gf_dsp          srl   a
                ret   z
                srl   h
                rr    l
                jr    gf_dsp

; gf_mul_spc: HL *= gf_spc (power of two). Clobbers A,B.
gf_mul_spc
                ld    a,(gf_spc)
                ld    b,0
gf_log          srl   a
                jr    z,gf_ms_do
                inc   b
                jr    gf_log
gf_ms_do        inc   b
gf_ms_dec       dec   b
                ret   z
                add   hl,hl
                jr    gf_ms_dec

; gf_clus_lba: HL = cluster -> HL = first sector LBA.
gf_clus_lba
                dec   hl
                dec   hl
                call  gf_mul_spc
                ld    de,(gf_data_lba)
                add   hl,de
                ret

; gf_fat_get: HL = cluster -> HL = FAT[cluster].
gf_fat_get
                ld    (gf_fclo),hl
                ld    a,h
                ld    l,a
                ld    h,0
                ld    de,(gf_fat_lba)
                add   hl,de
                call  gf_read_sector
                ld    a,(gf_fclo)
                ld    l,a
                ld    h,0
                add   hl,hl
                ld    de,gf_secbuf
                add   hl,de
                ld    a,(hl)
                ld    e,a
                inc   hl
                ld    d,(hl)
                ex    de,hl
                ret

; gf_fat_set: HL = cluster, DE = value -> FAT[cluster] = value.
gf_fat_set
                ld    (gf_fval),de
                ld    (gf_fclo),hl
                ld    a,h
                ld    l,a
                ld    h,0
                ld    de,(gf_fat_lba)
                add   hl,de
                ld    (gf_flba),hl
                call  gf_read_sector
                ld    a,(gf_fclo)
                ld    l,a
                ld    h,0
                add   hl,hl
                ld    de,gf_secbuf
                add   hl,de
                ld    de,(gf_fval)
                ld    (hl),e
                inc   hl
                ld    (hl),d
                ld    hl,(gf_flba)
                jp    gf_write_sector

; gf_clus_valid: HL = cluster -> CF set if 2 <= cluster < 0xFFF8.
gf_clus_valid
                ld    a,h
                cp    #FF
                jr    nz,gf_cv_lo
                ld    a,l
                cp    #F8
                jr    nc,gf_cv_no
gf_cv_lo        ld    a,h
                or    a
                jr    nz,gf_cv_yes
                ld    a,l
                cp    2
                jr    c,gf_cv_no
gf_cv_yes       scf
                ret
gf_cv_no        or    a
                ret

; gf_free_old: walk the old chain (if overwriting) and zero each FAT entry.
gf_free_old
                ld    a,(gf_found)
                or    a
                ret   z
                ld    hl,(gf_old_clus)
gf_fo_loop
                call  gf_clus_valid
                ret   nc
                ld    (gf_fclus),hl
                call  gf_fat_get
                ld    (gf_fnext),hl
                ld    hl,(gf_fclus)
                ld    de,0
                call  gf_fat_set
                ld    hl,(gf_fnext)
                jr    gf_fo_loop

; gf_alloc_chain: allocate gf_nclus clusters, chain them, set gf_first.
gf_alloc_chain
                ld    hl,0
                ld    (gf_prev),hl
                ld    hl,(gf_nclus)
                ld    (gf_acnt),hl
gf_ac_loop
                ld    hl,(gf_acnt)
                ld    a,h
                or    l
                jr    z,gf_ac_ok
                call  gf_alloc_one
                ret   nc
                ld    (gf_fclus),hl
                ld    de,#FFFF
                call  gf_fat_set
                ld    hl,(gf_prev)
                ld    a,h
                or    l
                jr    nz,gf_ac_link
                ld    hl,(gf_fclus)
                ld    (gf_first),hl
                jr    gf_ac_step
gf_ac_link
                ld    hl,(gf_prev)
                ld    de,(gf_fclus)
                call  gf_fat_set
gf_ac_step
                ld    hl,(gf_fclus)
                ld    (gf_prev),hl
                ld    hl,(gf_acnt)
                dec   hl
                ld    (gf_acnt),hl
                jr    gf_ac_loop
gf_ac_ok        scf
                ret

; gf_alloc_one: scan the FAT for a free entry -> HL = cluster, CF; NC = full.
gf_alloc_one
                ld    hl,0
                ld    (gf_ascan),hl
gf_ao_sec
                ld    hl,(gf_ascan)
                ld    de,(gf_spf)
                or    a
                sbc   hl,de
                jr    nc,gf_ao_full
                ld    hl,(gf_fat_lba)
                ld    de,(gf_ascan)
                add   hl,de
                call  gf_read_sector
                ld    hl,gf_secbuf
                ld    c,0
                ld    b,0
gf_ao_ent
                ld    a,(gf_ascan)
                or    a
                jr    nz,gf_ao_chk
                ld    a,(gf_ascan+1)
                or    a
                jr    nz,gf_ao_chk
                ld    a,c
                cp    2
                jr    c,gf_ao_skip
gf_ao_chk
                ld    a,(hl)
                inc   hl
                or    (hl)
                dec   hl
                jr    z,gf_ao_found
gf_ao_skip
                inc   hl
                inc   hl
                inc   c
                djnz  gf_ao_ent
                ld    hl,(gf_ascan)
                inc   hl
                ld    (gf_ascan),hl
                jr    gf_ao_sec
gf_ao_found
                ld    a,(gf_ascan)
                ld    h,a
                ld    l,c
                scf
                ret
gf_ao_full
                or    a
                ret

; gf_write_data: write GBFAT_LEN bytes across the allocated chain.
gf_write_data
                ld    hl,GBFAT_DATA
                ld    (gf_dptr),hl
                ld    hl,(GBFAT_LEN)
                ld    (gf_drem),hl
                ld    hl,(gf_first)
                ld    (gf_fclus),hl
                xor   a
                ld    (gf_sic),a
gf_wd_loop
                ld    hl,(gf_secs)
                ld    a,h
                or    l
                ret   z
                call  gf_fill_sector
                ld    hl,(gf_fclus)
                call  gf_clus_lba
                ld    a,(gf_sic)
                ld    e,a
                ld    d,0
                add   hl,de
                call  gf_write_sector
                ld    hl,(gf_secs)
                dec   hl
                ld    (gf_secs),hl
                ld    a,(gf_sic)
                inc   a
                ld    b,a
                ld    a,(gf_spc)
                cp    b
                jr    nz,gf_wd_keep
                ld    hl,(gf_fclus)
                call  gf_fat_get
                ld    (gf_fclus),hl
                xor   a
                ld    (gf_sic),a
                jr    gf_wd_loop
gf_wd_keep
                ld    a,b
                ld    (gf_sic),a
                jr    gf_wd_loop

; gf_fill_sector: up to 512 bytes from gf_dptr into gf_secbuf, zero-padded.
gf_fill_sector
                ld    hl,gf_secbuf
                ld    de,512
gf_fs_loop
                ld    a,d
                or    e
                ret   z
                push  hl
                ld    hl,(gf_drem)
                ld    a,h
                or    l
                pop   hl
                jr    z,gf_fs_pad
                push  de
                ld    de,(gf_dptr)
                ld    a,(de)
                inc   de
                ld    (gf_dptr),de
                pop   de
                ld    (hl),a
                push  hl
                ld    hl,(gf_drem)
                dec   hl
                ld    (gf_drem),hl
                pop   hl
                inc   hl
                dec   de
                jr    gf_fs_loop
gf_fs_pad
                ld    (hl),0
                inc   hl
                dec   de
                jr    gf_fs_loop

; gf_put_entry: write the directory entry (name, attr, start cluster, size).
gf_put_entry
                ld    hl,(gf_dir_lba)
                call  gf_read_sector
                ld    hl,(gf_dir_off)
                ld    de,gf_secbuf
                add   hl,de
                ld    (gf_eptr),hl
                push  hl
                pop   de
                inc   de
                ld    (hl),0
                ld    bc,31
                ldir
                ld    hl,GBFAT_NAME
                ld    de,(gf_eptr)
                ld    bc,11
                ldir
                ld    a,#20
                ld    (de),a
                ld    hl,(gf_eptr)
                ld    de,#1A
                add   hl,de
                ld    de,(gf_first)
                ld    (hl),e
                inc   hl
                ld    (hl),d
                ld    hl,(gf_eptr)
                ld    de,#1C
                add   hl,de
                ld    de,(GBFAT_LEN)
                ld    (hl),e
                inc   hl
                ld    (hl),d
                inc   hl
                ld    (hl),0
                inc   hl
                ld    (hl),0
                ld    hl,(gf_dir_lba)
                jp    gf_write_sector

; gf_find: scan the root dir for GBFAT_NAME or a free slot.
gf_find
                xor   a
                ld    (gf_found),a
                ld    (gf_havefree),a
                ld    (gf_sec),a
gf_fd_sec
                ld    a,(gf_sec)
                ld    b,a
                ld    a,(gf_root_secs)
                cp    b
                jr    z,gf_fd_done
                jr    c,gf_fd_done
                ld    hl,(gf_root_lba)
                ld    a,(gf_sec)
                ld    e,a
                ld    d,0
                add   hl,de
                ld    (gf_cur_lba),hl
                call  gf_read_sector
                ld    ix,gf_secbuf
                ld    b,16
                ld    c,0
gf_fd_ent
                ld    a,(ix+0)
                or    a
                jr    z,gf_fd_end0
                cp    #E5
                jr    z,gf_fd_free
                push  bc
                call  gf_cmpname
                pop   bc
                jr    z,gf_fd_match
                jr    gf_fd_next
gf_fd_free
                call  gf_fd_remember
                jr    gf_fd_next
gf_fd_match
                ld    a,1
                ld    (gf_found),a
                ld    hl,(gf_cur_lba)
                ld    (gf_dir_lba),hl
                call  gf_fd_setoff
                ld    l,(ix+#1A)
                ld    h,(ix+#1B)
                ld    (gf_old_clus),hl
                scf
                ret
gf_fd_next
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                inc   c
                djnz  gf_fd_ent
                ld    hl,gf_sec
                inc   (hl)
                jr    gf_fd_sec
gf_fd_end0
                call  gf_fd_remember
gf_fd_done
                ld    a,(gf_havefree)
                or    a
                jr    z,gf_fd_full
                ld    hl,(gf_free_lba)
                ld    (gf_dir_lba),hl
                ld    hl,(gf_free_off)
                ld    (gf_dir_off),hl
                ld    hl,0
                ld    (gf_old_clus),hl
                scf
                ret
gf_fd_full
                or    a
                ret
gf_fd_remember
                ld    a,(gf_havefree)
                or    a
                ret   nz
                ld    a,1
                ld    (gf_havefree),a
                ld    hl,(gf_cur_lba)
                ld    (gf_free_lba),hl
                call  gf_off_c
                ld    (gf_free_off),hl
                ret
gf_fd_setoff
                call  gf_off_c
                ld    (gf_dir_off),hl
                ret
gf_off_c                                       ; HL = c * 32
                ld    a,c
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ret
gf_cmpname                                     ; Z if IX 11-byte name == GBFAT_NAME
                push  ix
                pop   hl
                ld    de,GBFAT_NAME
                ld    b,11
gf_cn
                ld    a,(de)
                cp    (hl)
                jr    nz,gf_cn_no
                inc   hl
                inc   de
                djnz  gf_cn
                xor   a
                ret
gf_cn_no        or    1
                ret

; ---------------------------------------------------------------------------
; gf_read_sector / gf_write_sector: 512 bytes, LBA in HL (16-bit), via gf_secbuf.
gf_read_sector
                push  hl
                ld    a,#E0
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
                ld    a,#20
                ld    bc,FS_IDE_CMD
                out   (c),a
gf_rs_poll
                ld    bc,FS_IDE_STAT
                in    a,(c)
                bit   3,a
                jr    z,gf_rs_poll
                ld    hl,gf_secbuf
                ld    de,512
                ld    bc,FS_IDE_DATA
gf_rs_rd
                in    a,(c)
                ld    (hl),a
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,gf_rs_rd
                ret

gf_write_sector
                push  hl
                ld    a,#E0
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
                ld    a,#30
                ld    bc,FS_IDE_CMD
                out   (c),a
gf_ws_drq
                ld    bc,FS_IDE_STAT
                in    a,(c)
                bit   3,a
                jr    z,gf_ws_drq
                ld    hl,gf_secbuf
                ld    de,512
                ld    bc,FS_IDE_DATA
gf_ws_wr
                ld    a,(hl)
                out   (c),a
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,gf_ws_wr
gf_ws_busy
                ld    bc,FS_IDE_STAT
                in    a,(c)
                bit   7,a
                jr    nz,gf_ws_busy
                ret

; --- state ---------------------------------------------------------------
gf_root_lba     defw  0
gf_root_secs    defb  0
gf_spc          defb  0
gf_fat_lba      defw  0
gf_data_lba     defw  0
gf_spf          defw  0
gf_secs         defw  0
gf_nclus        defw  0
gf_first        defw  0
gf_found        defb  0
gf_old_clus     defw  0
gf_havefree     defb  0
gf_dir_lba      defw  0
gf_dir_off      defw  0
gf_free_lba     defw  0
gf_free_off     defw  0
gf_sec          defb  0
gf_cur_lba      defw  0
gf_eptr         defw  0
gf_fclus        defw  0
gf_fnext        defw  0
gf_prev         defw  0
gf_acnt         defw  0
gf_ascan        defw  0
gf_fclo         defw  0
gf_fval         defw  0
gf_flba         defw  0
gf_sic          defb  0
gf_dptr         defw  0
gf_drem         defw  0
gf_secbuf       defs  512
gbfat_end

                save  "build/GBFAT.RAW",GBFAT_ORG,gbfat_end-GBFAT_ORG
