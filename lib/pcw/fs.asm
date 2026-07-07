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
                ld    a,1                     ; the PCW boots from floppy A
                ld    (fs_cur_drive),a        ; (drive numbering: 0 = Disk C,
                ld    (fs_boot_drive),a       ;  1 = floppy A, 2 = floppy B)
                xor   a
                ld    (fsp_unit),a
                ; fall through: mount the disc in the selected unit

; fsp_mount: read the disc spec of the current unit and set the geometry.
fsp_mount
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
                scf
                ret

; fs_set_drive: A = drive (0 = Disk C: none here, treated as A; 1 = floppy A,
; 2 = floppy B). Switching physical units re-reads the new disc's spec.
fs_set_drive
                ld    (fs_cur_drive),a
                ld    c,0                     ; unit 0 = floppy A (and drive-0 fallback)
                cp    2
                jr    nz,fsd_have
                inc   c                        ; drive 2 = floppy B = unit 1
fsd_have
                ld    a,c
                ld    hl,fsp_unit
                cp    (hl)
                ret   z                        ; same unit: keep the mount
                ld    (hl),a
                call  pcwfdc_setunit
                dec   c                       ; switching to B: measure the
                call  z,pcwfdc_detect         ; mechanism's stepping first
                jp    fsp_mount               ; a different disc: fresh geometry

; fspc_probe_b: k_drive_poll backend -> A = drive bits (bit0 = floppy A,
; always - we booted from it; bit1 = a readable disc in floppy B). One read
; attempt, no retries: an empty drive must not stall the desktop for long.
fspc_probe_b
                ld    a,(fsp_unit)
                push  af
                ld    a,1
                call  pcwfdc_setunit
                xor   a
                ld    d,a
                ld    e,1
                ld    hl,fs_secbuf
                call  pcwfdc_read1
                pop   bc                       ; B = the mounted unit (from AF)
                push  af                       ; the probe result
                ld    a,b
                call  pcwfdc_setunit
                ld    hl,#FFFF                 ; the probe trashed the cache
                ld    (fsp_cslsn),hl
                pop   af
                ld    a,1
                jr    nc,fpb_done
                or    2
fpb_done
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
                ld    a,(FS_XFLAGS)           ; latch + clear the chunk-read flag
                and   1
                ld    (fslf_chunk),a
                xor   a
                ld    (FS_XFLAGS),a
                ld    (fslf_done),a
                ld    (fslf_skip),a
                ld    (fslf_skip+1),a
                ld    (fslf_skip+2),a
                ld    a,(fslf_chunk)
                or    a
                jr    z,flf_ck
                ld    hl,(FS_LOAD_OFS)        ; 24-bit skip-into-the-file offset
                ld    (fslf_skip),hl
                ld    a,(FS_LOAD_OFS+2)
                ld    (fslf_skip+2),a
flf_ck
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
                ld    a,(fslf_done)           ; chunk complete?
                or    a
                jp    nz,flf_done
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

; flf_copysec: HL = lsn of the sector holding n = min(512, ebyt) extent
; bytes. Honors the chunk-read skip (sectors wholly inside the skip are not
; even read); chunk mode stops cleanly when the buffer fills (fslf_done),
; plain mode refuses a file bigger than the buffer (NC).
flf_copysec
                push  hl                      ; n = min(512, ebyt); ebyt -= n
                ld    hl,(fslf_ebyt)
                ld    de,512
                or    a
                sbc   hl,de
                jr    nc,fcs_full
                ld    hl,(fslf_ebyt)
                ld    (fcs_n),hl
                ld    hl,0
                jr    fcs_have
fcs_full
                ld    de,512
                ld    (fcs_n),de
fcs_have
                ld    (fslf_ebyt),hl
                pop   hl
                ld    a,(fslf_skip+2)         ; skip >= n? (n <= 512, any high
                or    a                        ; byte means yes)
                jr    nz,fcs_skipsec
                ld    de,(fslf_skip)
                ld    a,d
                or    e
                jr    z,fcs_copy
                push  hl                       ; skip16 >= n -> whole-sector skip
                ex    de,hl
                ld    de,(fcs_n)
                or    a
                sbc   hl,de
                pop   hl
                jr    c,fcs_copy               ; skip < n: read + partial copy
fcs_skipsec
                push  hl                       ; whole sector inside the skip:
                ld    hl,(fslf_skip)           ; skip -= n, no I/O at all
                ld    de,(fcs_n)
                or    a
                sbc   hl,de
                ld    (fslf_skip),hl
                jr    nc,fcs_sknc
                ld    a,(fslf_skip+2)
                dec   a
                ld    (fslf_skip+2),a
fcs_sknc
                pop   hl
                scf
                ret
fcs_copy
                ld    de,(fslf_skip)           ; ofs = skip (0..511), then clear
                ld    (fcs_ofs),de
                xor   a
                ld    (fslf_skip),a
                ld    (fslf_skip+1),a
                call  fsp_rdsec
                ret   nc
                ld    hl,(fcs_n)               ; m = n - ofs
                ld    de,(fcs_ofs)
                or    a
                sbc   hl,de
                ld    (fcs_m),hl
                ld    a,(fslf_chunk)
                or    a
                jr    nz,fcs_capchunk
                ld    hl,(fslf_rem)            ; plain: m > rem = too big -> NC
                ld    de,(fcs_m)
                or    a
                sbc   hl,de
                jr    nc,fcs_go
                or    a
                ret
fcs_capchunk
                ld    hl,(fcs_m)               ; chunk: m = min(m, rem)
                ld    de,(fslf_rem)
                or    a
                sbc   hl,de
                jr    c,fcs_go
                ld    hl,(fslf_rem)
                ld    (fcs_m),hl
fcs_go
                ld    hl,(fcs_m)
                ld    a,h
                or    l
                jr    z,fcs_donechk
                ld    b,h
                ld    c,l
                ld    hl,(fslf_rem)            ; rem -= m, total += m
                or    a
                sbc   hl,bc
                ld    (fslf_rem),hl
                ld    hl,(fslf_total)
                add   hl,bc
                ld    (fslf_total),hl
                ld    hl,fs_secbuf             ; copy from buf + ofs
                ld    de,(fcs_ofs)
                add   hl,de
                ld    de,(fslf_dst)
                ldir
                ld    (fslf_dst),de
fcs_donechk
                ld    a,(fslf_chunk)           ; chunk buffer full -> clean stop
                or    a
                jr    z,fcs_ok
                ld    hl,(fslf_rem)
                ld    a,h
                or    l
                jr    nz,fcs_ok
                ld    a,1
                ld    (fslf_done),a
fcs_ok
                scf
                ret

; fs_load_cur_sys: system load from the CURRENT drive (flat fs: plain load).
fs_load_cur_sys
                jp    fs_load_file

; fs_load_sys: like fs_load_file but from the BOOT drive (where the OS apps
; and modules live) regardless of the active browse drive, with a browse-
; drive retry - the exact CPC contract (lib/fs.asm #65/#110/#250). Without
; this, opening Disk B tried to load FILEMGR.APP from COMPANION.DSK: one
; LED flash and no window (#331 bug report).
fs_load_sys
                ld    a,(fs_cur_drive)         ; save the active browse drive
                ld    (fls_browse),a
                ld    a,(fs_boot_drive)
                call  fs_set_drive             ; boot drive (remounts if needed)
                call  fs_load_file
                push  af
                ld    a,(fls_browse)
                call  fs_set_drive             ; restore the browse drive
                pop   af
                ret   c                        ; loaded from boot -> done
                jp    fs_load_file             ; else retry on the browse drive

; --- write ops (#331 Phase 5b) --------------------------------------------------

; fs_delete_file: free every extent entry of fs_req_name (user 0). CF = deleted.
fs_delete_file
                ld    hl,#FFFF
                ld    (fsp_cslsn),hl
                xor   a
                ld    (fscs_e),a
                ld    (fsdl_hit),a
fdl_loop
                ld    a,(fscs_e)
                ld    hl,fsp_drm
                cp    (hl)
                jr    nc,fdl_done
                inc   a
                ld    (fscs_e),a
                dec   a
                call  fsp_getent
                jr    nc,fdl_fail
                ld    a,(hl)
                or    a                        ; only user-0 files are ours
                jr    nz,fdl_loop
                ld    de,fs_req_name
                call  fsp_name_match
                jr    nz,fdl_loop
                ld    (hl),#E5                 ; free this extent's entry
                ld    hl,(fsp_cslsn)           ; the dir sector back to disc
                call  fsp_wrsec
                jr    nc,fdl_fail
                ld    a,1
                ld    (fsdl_hit),a
                jr    fdl_loop
fdl_done
                ld    a,(fsdl_hit)
                or    a
                jr    z,fdl_fail
                scf
                ret
fdl_fail
                or    a
                ret

; fs_save_file: write fs_save_len bytes from (fs_save_src) to fs_req_name.
; FS_XFLAGS bit1 = append to the existing file (else create/truncate). CF ok.
; CP/M sizes are 128-byte records: the final record is #1A-padded, so sizes
; round up to the next record (the shared contract already treats fs sizes
; as advisory - loaders read the content's own headers).
fs_save_file
                ld    hl,#FFFF
                ld    (fsp_cslsn),hl
                ld    a,(FS_XFLAGS)
                and   2                        ; bit1 = append; latch + clear
                ld    (fsv_app),a
                xor   a
                ld    (FS_XFLAGS),a
                ld    hl,(fs_save_src)
                ld    (fsv_src),hl
                ld    hl,(fs_save_len)
                ld    (fsv_rem),hl
                ld    a,#FF
                ld    (fsv_slot),a
                ld    a,(fsv_app)
                or    a
                jp    nz,fsv_append
                call  fs_delete_file           ; create/truncate: drop any old file
                call  fsw_bitmap
                xor   a
                ld    (fsv_ext),a
fsv_newext
                xor   a                        ; fresh extent: rc = 0, no blocks
                ld    (fsv_rc),a
                ld    hl,fsv_al
                ld    de,fsv_al+1
                ld    bc,15
                ld    (hl),a
                ldir
fsv_recloop
                ld    hl,(fsv_rem)
                ld    a,h
                or    l
                jp    z,fsv_flush              ; all data written -> final entry
                ld    a,(fsv_rc)
                cp    128
                jr    c,fsv_haveroom
                call  fsv_flush                ; extent full: entry out, next one
                ret   nc
                ld    a,(fsv_ext)
                inc   a
                ld    (fsv_ext),a
                jr    fsv_newext
fsv_haveroom
                call  fsv_putrec               ; one 128-byte record
                ret   nc
                jr    fsv_recloop

fsv_append
                call  fsw_bitmap
                xor   a                        ; find the LAST extent of the file
                ld    (fsv_ext),a
                ld    (fscs_e),a
                ld    (fsdl_hit),a
fap_scan
                ld    a,(fscs_e)
                ld    hl,fsp_drm
                cp    (hl)
                jr    nc,fap_scanned
                inc   a
                ld    (fscs_e),a
                dec   a
                call  fsp_getent
                jr    nc,fap_scanned
                ld    a,(hl)
                or    a
                jr    nz,fap_scan
                ld    de,fs_req_name
                call  fsp_name_match
                jr    nz,fap_scan
                push  hl                       ; EX >= best so far? take it
                ld    de,12
                add   hl,de
                ld    a,(hl)
                and   #1F
                ld    b,a
                ld    a,(fsdl_hit)             ; first hit always wins
                or    a
                jr    z,fap_take
                ld    a,b
                ld    hl,fsv_ext
                cp    (hl)
                jr    c,fap_skip
fap_take
                ld    a,1
                ld    (fsdl_hit),a
                ld    a,b
                ld    (fsv_ext),a
                ld    a,(fscs_e)
                dec   a
                ld    (fsv_slot),a
fap_skip
                pop   hl
                jr    fap_scan
fap_scanned
                ld    a,(fsdl_hit)
                or    a
                jr    nz,fap_found
                xor   a                        ; no such file: append = create
                ld    (fsv_ext),a
                ld    a,#FF
                ld    (fsv_slot),a
                jp    fsv_newext
fap_found
                ld    a,(fsv_slot)             ; reload rc + ALs from that entry
                call  fsp_getent
                jr    nc,fsv_fail
                push  hl
                ld    de,15
                add   hl,de
                ld    a,(hl)
                ld    (fsv_rc),a
                pop   hl
                ld    de,16
                add   hl,de
                ld    de,fsv_al
                ld    bc,16
                ldir
                jp    fsv_recloop
fsv_fail
                or    a
                ret

; fsv_putrec: write the record at index fsv_rc from (fsv_src): allocate its
; block if needed, read-modify-write the sector, #1A-pad a short tail. CF ok.
fsv_putrec
                ld    a,(fsv_rc)               ; block index within extent = rc/8
                srl   a
                srl   a
                srl   a
                ld    e,a
                ld    d,0
                ld    hl,fsv_al
                add   hl,de
                ld    a,(hl)
                or    a
                jr    nz,fpr_haveblk
                push  hl
                call  fsw_alloc                ; claim a free block
                pop   hl
                ret   nc                       ; disc full
                ld    (hl),a
fpr_haveblk
                ld    l,a                      ; lsn = block*2 (+1 for records 4-7)
                ld    h,0
                add   hl,hl
                ld    a,(fsv_rc)
                and   4
                jr    z,fpr_s0
                inc   hl
fpr_s0
                push  hl                       ; RMW: a fresh block reads whatever
                call  fsp_rdsec                ; the format left - harmless, the
                pop   hl                       ; record overwrites its 128 bytes
                jr    c,fpr_havebuf
                push  hl                       ; unreadable (shouldn't happen on a
                ld    hl,fs_secbuf             ; formatted disc): zero the buffer
                ld    de,fs_secbuf+1           ; and claim the cache slot
                ld    bc,511
                ld    (hl),0
                ldir
                pop   hl
                ld    (fsp_cslsn),hl
fpr_havebuf
                push  hl                       ; keep the lsn for the write-back
                ld    a,(fsv_rc)               ; soff = (rc & 3) * 128
                and   3
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    de,fs_secbuf
                add   hl,de
                ex    de,hl                    ; DE = record home in the buffer
                ld    hl,(fsv_rem)             ; BC = n = min(128, rem)
                ld    bc,128
                or    a
                sbc   hl,bc
                jr    nc,fpr_lenok
                ld    hl,(fsv_rem)
                ld    b,h
                ld    c,l
                ld    hl,0
fpr_lenok
                ld    (fsv_rem),hl
                push  bc
                ld    hl,(fsv_src)             ; the record's data
                ldir
                ld    (fsv_src),hl
                pop   bc
                ld    a,128                    ; #1A-pad a short final record
                sub   c
                jr    z,fpr_wr
                ld    b,a
fpr_padl
                ld    a,#1A
                ld    (de),a
                inc   de
                djnz  fpr_padl
fpr_wr
                pop   hl                       ; the sector back to disc
                call  fsp_wrsec
                ret   nc
                ld    a,(fsv_rc)
                inc   a
                ld    (fsv_rc),a
                scf
                ret

; fsv_flush: write this extent's directory entry - update slot fsv_slot when
; set (append's first flush), else claim a free (#E5) slot. CF ok.
fsv_flush
                ld    a,(fsv_slot)
                cp    #FF
                jr    nz,ffl_fill
                xor   a                        ; find a free directory slot
                ld    (fscs_e),a
ffl_scan
                ld    a,(fscs_e)
                ld    hl,fsp_drm
                cp    (hl)
                jr    nc,ffl_full
                inc   a
                ld    (fscs_e),a
                dec   a
                ld    c,a
                call  fsp_getent
                ret   nc
                ld    a,(hl)
                cp    #E5
                jr    nz,ffl_scan
                ld    a,c
ffl_fill
                call  fsp_getent
                ret   nc
                ld    (hl),0                   ; user 0
                inc   hl
                ex    de,hl
                ld    hl,fs_req_name           ; +1..11 name
                ld    bc,11
                ldir
                ld    a,(fsv_ext)              ; +12 EX
                ld    (de),a
                inc   de
                xor   a                        ; +13 S1, +14 S2
                ld    (de),a
                inc   de
                ld    (de),a
                inc   de
                ld    a,(fsv_rc)               ; +15 RC
                ld    (de),a
                inc   de
                ld    hl,fsv_al                ; +16..31 AL
                ld    bc,16
                ldir
                ld    hl,(fsp_cslsn)           ; the dir sector back to disc
                call  fsp_wrsec
                ret   nc
                ld    a,#FF                    ; the slot is consumed
                ld    (fsv_slot),a
                scf
                ret
ffl_full
                or    a
                ret

; --- block allocation ------------------------------------------------------------

; fsw_bitmap: build the used-block bitmap from the directory (every user's
; files count - foreign blocks must not be clobbered).
fsw_bitmap
                ld    hl,fsw_bmap
                ld    de,fsw_bmap+1
                ld    bc,21
                ld    (hl),0
                ldir
                ld    a,(fsp_dirblks)          ; the directory's own blocks
                ld    b,a
                ld    c,0
fwb_dir
                push  bc
                ld    a,c
                call  fsw_setbit
                pop   bc
                inc   c
                djnz  fwb_dir
                xor   a
                ld    (fscs_e),a
fwb_loop
                ld    a,(fscs_e)
                ld    hl,fsp_drm
                cp    (hl)
                ret   nc
                inc   a
                ld    (fscs_e),a
                dec   a
                call  fsp_getent
                ret   nc
                ld    a,(hl)
                cp    #E5
                jr    z,fwb_loop
                ld    de,16
                add   hl,de
                ld    b,16
fwb_als
                ld    a,(hl)
                or    a
                jr    z,fwb_next
                push  hl
                push  bc
                call  fsw_setbit
                pop   bc
                pop   hl
fwb_next
                inc   hl
                djnz  fwb_als
                jr    fwb_loop

; fsw_setbit: A = block number -> mark used. Clobbers A,BC,DE,HL.
fsw_setbit
                call  fsw_bitpos
                or    (hl)
                ld    (hl),a
                ret

; fsw_bitpos: A = block -> HL = bitmap byte, A = its bit mask.
fsw_bitpos
                ld    c,a
                srl   a
                srl   a
                srl   a
                ld    e,a
                ld    d,0
                ld    hl,fsw_bmap
                add   hl,de
                ld    a,c
                and   7
                ld    b,a
                ld    a,1
                inc   b
fbp_sh
                dec   b
                ret   z
                add   a,a
                jr    fbp_sh

; fsw_alloc: find + claim a free block -> A. CF ok, NC = disc full.
fsw_alloc
                ld    a,(fsp_nblocks)          ; <= 175, fits a byte
                ld    b,a
                ld    c,0
fwa_loop
                ld    a,c
                push  bc
                call  fsw_bitpos
                and   (hl)
                pop   bc
                jr    z,fwa_take
                inc   c
                djnz  fwa_loop
                or    a
                ret
fwa_take
                ld    a,c
                push  bc
                call  fsw_setbit
                pop   bc
                ld    a,c
                scf
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
                call  fsp_lsn2ts
                ld    hl,fs_secbuf
                call  pcwfdc_read
                ret   c
                ld    hl,#FFFF                ; failed: nothing cached
                ld    (fsp_cslsn),hl
                or    a
                ret

; fsp_wrsec: write fs_secbuf to data-area lsn HL (the cache stays valid -
; the buffer now matches the disc). CF ok.
fsp_wrsec
                ld    (fsp_cslsn),hl
                call  fsp_lsn2ts
                ld    hl,fs_secbuf
                call  pcwfdc_write
                ret   c
                ld    hl,#FFFF
                ld    (fsp_cslsn),hl
                or    a
                ret

; fsp_lsn2ts: HL = data-area lsn -> D = track (OFF + lsn/9), E = sector
; (1 + lsn%9). Clobbers A, BC, HL.
fsp_lsn2ts
                ld    a,(fsp_offtrk)
                ld    d,a
fl2_div
                ld    a,h
                or    a
                jr    nz,fl2_sub
                ld    a,l
                cp    9
                jr    c,fl2_have
fl2_sub
                ld    bc,9
                or    a
                sbc   hl,bc
                inc   d
                jr    fl2_div
fl2_have
                ld    a,l
                inc   a
                ld    e,a
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
fsp_unit        db    0
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
fsdl_hit        db    0
fslf_chunk      db    0
fslf_done       db    0
fslf_skip       ds    3
fcs_n           dw    0
fcs_m           dw    0
fcs_ofs         dw    0
fsv_src         dw    0
fsv_rem         dw    0
fsv_rc          db    0
fsv_ext         db    0
fsv_app         db    0
fsv_slot        db    0
fsv_al          ds    16
fsw_bmap        ds    22
fslf_blocks     equ   #1490        ; 16-byte extent AL copy (documented low-RAM home)
fs_dir_clus     ds    4            ; dummy: k_copy_begin/end context swap expects it

FS_LOAD_OFS     equ   #144C        ; chunked-copy cells (#144): the kernel writes
FS_XFLAGS       equ   #144F        ; them; this backend honors them in Phase 5
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
