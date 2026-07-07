; ---------------------------------------------------------------------------
; lib/pcw/fs.asm - CP/M 2.2 filesystem backend for the PCW target (#331).
;
; GEOBENCH boots standalone on the PCW (no CP/M is shipped or loaded), but
; its discs carry a standard CP/M 2.2 filesystem so the media stays fully
; interoperable. This backend reads it directly over lib/pcw/fdc.asm.
;
; Exposes the shared interface (same as lib/fs.asm / lib/msx/fs.asm):
; fs_init / fs_set_drive / fs_dir_first / fs_dir_next / fs_load_file /
; fs_load_cur_sys / fs_load_sys / fs_save_file / fs_delete_file /
; fs_free_kib / fs_sysdir_enter / fs_sysdir_leave / fs_sys_resolve, and the
; same fs_ent_* / fs_req_name / fs_load_* low-RAM cells.
;
; Filesystem shape (CF2 180K, from the disc spec at T0/R1):
;   - data area starts at track OFF (spec[5]); 1K blocks (BSH=3, spec[6]);
;     spec[7] directory blocks at block 0 (32 entries each)
;   - dir entry: +0 user (0 = ours, #E5 = free), +1..11 name/ext (attribute
;     bits in the high bits - masked), +12 EX extent#, +14 S2, +15 RC
;     (128-byte records in this extent; #80 = full 16K), +16..31 AL[16]
;     8-bit block numbers (a CF2 has 175 blocks, so 1-byte ALs)
;   - a file > 16K has one entry per extent, same name, EX = 0,1,2...
;     size = maxEX*16384 + RC(maxEX)*128 (128-byte granularity - loaders
;     read the content's own headers for exact geometry)
;
; CP/M is FLAT: no directories. fs_sysdir_enter/leave are no-ops and system
; files live in the root (the "ship content flat" model). M1 scope is
; read-only: save/delete return NC (the write path is Phase 5).
;
; Sector cache: one sector in fs_secbuf (#1800), invalidated at every public
; entry point - fs_secbuf is aliased by other users (the drag ghost's
; save-under), so nothing may trust it across calls.
; ---------------------------------------------------------------------------

fs_init
                call  pcwfdc_init
                ld    hl,#FFFF
                ld    (fsp_cslsn),hl
                xor   a                       ; read the disc spec: T0/R1 raw
                ld    d,a
                ld    e,1
                ld    hl,fs_secbuf
                call  pcwfdc_read
                jr    c,fsi_spec
                ld    a,3                     ; unreadable spec: assume plain CF2
                ld    (fsp_offtrk),a          ; (OFF is raised by mkpcwdsk to cover
                ld    a,2                     ; the kernel image, so a real GEOBENCH
                ld    (fsp_dirblks),a         ; disc always has a readable spec)
                jr    fsi_geom
fsi_spec
                ld    a,(fs_secbuf+5)         ; OFF: reserved tracks
                ld    (fsp_offtrk),a
                ld    a,(fs_secbuf+7)         ; directory blocks
                ld    (fsp_dirblks),a
fsi_geom
                ld    hl,#FFFF                ; the spec read cached T0/R1, which is
                ld    (fsp_cslsn),hl          ; NOT a data-area lsn - invalidate
                ld    a,(fsp_dirblks)         ; drm = dirblks * 32 entries
                add   a,a
                add   a,a
                add   a,a
                add   a,a
                add   a,a
                ld    (fsp_drm),a
                ld    a,(fsp_offtrk)          ; total blocks = (40 - OFF) * 9 / 2
                ld    b,a
                ld    a,40
                sub   b
                ld    l,a
                ld    h,0
                ld    e,a
                ld    d,0
                add   hl,hl                   ; *2
                add   hl,hl                   ; *4
                add   hl,hl                   ; *8
                add   hl,de                   ; *9
                srl   h
                rr    l                       ; /2 -> 1K blocks
                ld    (fsp_nblocks),hl
                xor   a
                ld    (fs_cur_drive),a
                ld    (fs_boot_drive),a
                scf
                ret

fs_set_drive
                ld    (fs_cur_drive),a        ; single drive for now (B: is Phase 6)
                ret

fs_sys_resolve
                ret
fs_sysdir_enter
                ret                            ; CP/M is flat: system files at root
fs_sysdir_leave
                ret

; --- directory enumeration ---------------------------------------------------
; fs_dir_first / fs_dir_next -> CF set = entry ready in fs_ent_*, NC = done.
; Reports each FILE once (extent 0 entries only); size spans all extents.
fs_dir_first
                xor   a
                ld    (fsd_idx),a
fs_dir_next
                ld    hl,#FFFF
                ld    (fsp_cslsn),hl
fdn_loop
                ld    a,(fsd_idx)
                ld    hl,fsp_drm
                cp    (hl)
                jr    c,fdn_have
                or    a                       ; past the end: done
                ret
fdn_have
                inc   a
                ld    (fsd_idx),a
                dec   a
                call  fsp_getent
                ret   nc                      ; read error: end the walk
                ld    a,(hl)                  ; +0 user: 0 = ours
                or    a
                jr    nz,fdn_loop
                push  hl
                ld    de,12                   ; +12 EX and +14 S2 must be 0
                add   hl,de
                ld    a,(hl)
                and   #1F
                inc   hl
                inc   hl
                or    (hl)
                pop   hl
                jr    nz,fdn_loop
                push  hl                      ; name -> fs_ent_name (strip attr bits)
                inc   hl
                ld    de,fs_ent_name
                ld    b,11
fdn_name
                ld    a,(hl)
                and   #7F
                ld    (de),a
                inc   hl
                inc   de
                djnz  fdn_name
                pop   hl
                push  hl                      ; attr: t1' (RO) -> FAT-ish bit 0
                ld    de,9
                add   hl,de
                ld    a,(hl)
                rlca
                and   1
                ld    (fs_ent_attr),a
                pop   hl
                call  fsp_calcsize            ; all-extent size -> fs_ent_size
                scf
                ret

; fsp_calcsize: size of the file named fs_ent_name -> fs_ent_size (dword).
; Scans the whole directory for the highest extent. Clobbers everything.
fsp_calcsize
                xor   a
                ld    (fscs_max),a            ; max EX seen
                ld    (fscs_rc),a             ; its RC
                ld    (fscs_e),a
fscs_loop
                ld    a,(fscs_e)
                ld    hl,fsp_drm
                cp    (hl)
                jr    nc,fscs_done
                inc   a
                ld    (fscs_e),a
                dec   a
                call  fsp_getent
                jr    nc,fscs_done
                ld    a,(hl)
                or    a
                jr    nz,fscs_loop
                ld    de,fs_ent_name
                call  fsp_name_match
                jr    nz,fscs_loop
                push  hl                      ; EX >= max seen so far?
                ld    de,12
                add   hl,de
                ld    a,(hl)
                and   #1F
                ld    c,a
                ld    a,(fscs_max)
                cp    c
                jr    z,fscs_take             ; EX == max: take it (fresh RC)
                jr    nc,fscs_skip
fscs_take
                ld    a,c
                ld    (fscs_max),a
                inc   hl
                inc   hl
                inc   hl                       ; +15 RC
                ld    a,(hl)
                ld    (fscs_rc),a
fscs_skip
                pop   hl
                jr    fscs_loop
fscs_done
                ld    hl,0                    ; size = max*16384 + rc*128
                ld    b,0                     ; B = bits 16-23
                ld    a,(fscs_max)
                or    a
                jr    z,fscs_rcpart
                ld    de,16384
fscs_exadd
                add   hl,de
                jr    nc,fscs_exnc
                inc   b
fscs_exnc
                dec   a
                jr    nz,fscs_exadd
fscs_rcpart
                ld    a,(fscs_rc)             ; DE = RC * 128
                srl   a
                ld    d,a
                ld    a,(fscs_rc)
                rrca
                and   #80
                ld    e,a
                add   hl,de
                jr    nc,fscs_rcnc
                inc   b
fscs_rcnc
                ld    (fs_ent_size),hl
                ld    a,b
                ld    (fs_ent_size+2),a
                xor   a
                ld    (fs_ent_size+3),a
                ret

; --- load ---------------------------------------------------------------------
; fs_load_file: load fs_req_name into (fs_load_dst), capped at (fs_load_max).
; CF set = loaded, fs_ent_size = byte count (128-byte granular). NC = missing
; or too big for the buffer (the CPC contract).
fs_load_file
                ld    hl,#FFFF
                ld    (fsp_cslsn),hl
                xor   a
                ld    (fslf_ext),a
                ld    hl,0
                ld    (fslf_total),hl
                ld    hl,(fs_load_dst)
                ld    (fslf_dst),hl
                ld    hl,(fs_load_max)
                ld    (fslf_rem),hl
flf_extloop
                xor   a                       ; scan for (fs_req_name, EX=fslf_ext)
                ld    (fscs_e),a
flf_scan
                ld    a,(fscs_e)
                ld    hl,fsp_drm
                cp    (hl)
                jp    nc,flf_noent
                inc   a
                ld    (fscs_e),a
                dec   a
                call  fsp_getent
                jp    nc,flf_noent
                ld    a,(hl)
                or    a
                jr    nz,flf_scan
                push  hl
                ld    de,12
                add   hl,de
                ld    a,(hl)
                and   #1F
                ld    c,a
                ld    a,(fslf_ext)
                cp    c
                pop   hl
                jr    nz,flf_scan
                ld    de,fs_req_name
                call  fsp_name_match
                jr    nz,flf_scan
                ; --- extent found: copy RC + AL[16] out of the sector buffer
                ; (the data reads below reuse fs_secbuf)
                push  hl
                ld    de,15
                add   hl,de
                ld    a,(hl)
                ld    (fslf_rc),a
                pop   hl
                ld    de,16
                add   hl,de
                ld    de,fslf_blocks
                ld    bc,16
                ldir
                ld    a,(fslf_rc)             ; extent bytes = RC * 128
                srl   a
                ld    h,a
                ld    a,(fslf_rc)
                rrca
                and   #80
                ld    l,a
                ld    (fslf_ebyt),hl
                xor   a
                ld    (fslf_ai),a
flf_blk
                ld    hl,(fslf_ebyt)          ; extent exhausted?
                ld    a,h
                or    l
                jr    z,flf_extdone
                ld    a,(fslf_ai)
                cp    16
                jr    nc,flf_extdone
                ld    hl,fslf_blocks
                ld    e,a
                ld    d,0
                add   hl,de
                inc   a
                ld    (fslf_ai),a
                ld    a,(hl)                  ; A = block number (0 = hole/end)
                or    a
                jr    z,flf_extdone
                ld    l,a                     ; first sector of the block: lsn = AL*2
                ld    h,0
                add   hl,hl
                call  flf_copysec
                jr    nc,flf_fail
                ld    hl,(fslf_ebyt)          ; second sector, if the extent goes on
                ld    a,h
                or    l
                jr    z,flf_blk
                ld    a,(fslf_ai)             ; lsn = AL*2 + 1 (AL was consumed: -1)
                dec   a
                ld    hl,fslf_blocks
                ld    e,a
                ld    d,0
                add   hl,de
                ld    a,(hl)
                ld    l,a
                ld    h,0
                add   hl,hl
                inc   hl
                call  flf_copysec
                jr    nc,flf_fail
                jr    flf_blk
flf_extdone
                ld    a,(fslf_rc)             ; RC < #80 = final extent
                cp    #80
                jr    c,flf_done
                ld    a,(fslf_ext)            ; else continue with the next one
                inc   a
                ld    (fslf_ext),a
                jp    flf_extloop
flf_noent
                ld    a,(fslf_ext)            ; extent 0 missing = no such file;
                or    a                       ; a later extent missing = done
                jr    nz,flf_done
flf_fail
                or    a
                ret
flf_done
                ld    hl,(fslf_total)
                ld    (fs_ent_size),hl
                xor   a
                ld    (fs_ent_size+2),a
                ld    (fs_ent_size+3),a
                scf
                ret

; flf_copysec: HL = lsn -> copy min(512, extent bytes left) to the running
; destination. NC = read error or the buffer cap was hit (too big).
flf_copysec
                call  fsp_rdsec
                ret   nc
                ld    hl,(fslf_ebyt)          ; BC = n = min(512, ebyt)
                ld    de,512
                or    a
                sbc   hl,de
                jr    nc,flf_full
                ld    hl,(fslf_ebyt)          ; short tail
                ld    b,h
                ld    c,l
                ld    hl,0
                jr    flf_havelen
flf_full
                ld    bc,512                  ; HL already = ebyt - 512
flf_havelen
                ld    (fslf_ebyt),hl
                ld    hl,(fslf_rem)           ; buffer cap: rem -= n; over = too big
                or    a
                sbc   hl,bc
                jr    nc,flf_capok
                or    a                       ; NC = fail (buffer overrun refused)
                ret
flf_capok
                ld    (fslf_rem),hl
                ld    hl,(fslf_total)
                add   hl,bc
                ld    (fslf_total),hl
                ld    hl,fs_secbuf
                ld    de,(fslf_dst)
                ldir
                ld    (fslf_dst),de
                scf
                ret

; fs_load_cur_sys / fs_load_sys: flat filesystem - plain loads.
fs_load_cur_sys
fs_load_sys
                jp    fs_load_file

; --- write ops: Phase 5 -------------------------------------------------------
fs_save_file
fs_delete_file
                or    a
                ret

; fs_free_kib: HL = free KiB (1K blocks), CF set. Free = total - dir - used.
fs_free_kib
                ld    hl,#FFFF
                ld    (fsp_cslsn),hl
                ld    hl,0
                ld    (fsff_used),hl
                xor   a
                ld    (fscs_e),a
fff_loop
                ld    a,(fscs_e)
                ld    hl,fsp_drm
                cp    (hl)
                jr    nc,fff_done
                inc   a
                ld    (fscs_e),a
                dec   a
                call  fsp_getent
                jr    nc,fff_done
                ld    a,(hl)
                or    a
                jr    nz,fff_loop
                ld    de,16                   ; count this entry's non-zero ALs
                add   hl,de
                ld    b,16
fff_als
                ld    a,(hl)
                or    a
                jr    z,fff_alnext
                push  hl
                ld    hl,(fsff_used)
                inc   hl
                ld    (fsff_used),hl
                pop   hl
fff_alnext
                inc   hl
                djnz  fff_als
                jr    fff_loop
fff_done
                ld    hl,(fsp_nblocks)
                ld    de,(fsff_used)
                or    a
                sbc   hl,de
                ld    a,(fsp_dirblks)
                ld    e,a
                ld    d,0
                or    a
                sbc   hl,de
                jr    nc,fff_ok
                ld    hl,0
fff_ok
                scf
                ret

; --- helpers -------------------------------------------------------------------

; fsp_rdsec: HL = data-area lsn -> the sector in fs_secbuf (cached). CF ok.
fsp_rdsec
                ld    de,(fsp_cslsn)
                or    a
                sbc   hl,de
                add   hl,de
                jr    nz,frs_load
                scf
                ret
frs_load
                ld    (fsp_cslsn),hl
                ld    a,(fsp_offtrk)          ; track = OFF + lsn/9, sec = 1 + lsn%9
                ld    d,a
frs_div
                ld    a,h
                or    a
                jr    nz,frs_sub
                ld    a,l
                cp    9
                jr    c,frs_have
frs_sub
                ld    bc,9
                or    a
                sbc   hl,bc
                inc   d
                jr    frs_div
frs_have
                ld    a,l
                inc   a
                ld    e,a
                ld    hl,fs_secbuf
                call  pcwfdc_read
                ret   c
                ld    hl,#FFFF                ; failed: nothing cached
                ld    (fsp_cslsn),hl
                or    a
                ret

; fsp_getent: A = directory entry index -> HL = its 32 bytes in fs_secbuf.
; CF ok. (Directory lsn = index/16, offset = (index & 15) * 32.)
fsp_getent
                ld    c,a
                srl   a
                srl   a
                srl   a
                srl   a
                ld    l,a
                ld    h,0
                push  bc
                call  fsp_rdsec
                pop   bc
                ret   nc
                ld    a,c
                and   15
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl                   ; * 32
                ld    de,fs_secbuf
                add   hl,de
                scf
                ret

; fsp_name_match: HL = dir entry, DE = 11-byte name -> Z = match.
; Preserves HL. Attribute high bits are stripped from the entry side.
fsp_name_match
                push  hl
                push  de
                inc   hl                      ; entry name at +1
                ld    b,11
fnm_loop
                ld    a,(de)
                ld    c,a
                ld    a,(hl)
                and   #7F
                cp    c
                jr    nz,fnm_out
                inc   hl
                inc   de
                djnz  fnm_loop
                xor   a                       ; Z = match
fnm_out
                pop   de
                pop   hl
                ret

; --- state ----------------------------------------------------------------------
fsp_offtrk      db    1
fsp_dirblks     db    2
fsp_drm         db    64
fsp_nblocks     dw    175
fsp_cslsn       dw    #FFFF
fsd_idx         db    0
fscs_e          db    0
fscs_max        db    0
fscs_rc         db    0
fslf_ext        db    0
fslf_rc         db    0
fslf_ai         db    0
fslf_ebyt       dw    0
fslf_rem        dw    0
fslf_dst        dw    0
fslf_total      dw    0
fsff_used       dw    0
fslf_blocks     equ   #1490        ; 16-byte extent AL copy (documented low-RAM home)
fs_dir_clus     ds    4            ; dummy: k_copy_begin/end context swap expects it

fls_browse      equ   #1337
fs_cur_drive    equ   #1335
fs_boot_drive   equ   #1336
fs_ent_name     equ   #14DC
fs_ent_attr     equ   #14E7
fs_ent_size     equ   #14E8
fs_req_name     equ   #14EC
fs_load_dst     equ   #14F7
fs_load_max     equ   #14F9
fs_save_src     equ   #14FB
fs_save_len     equ   #14FD
