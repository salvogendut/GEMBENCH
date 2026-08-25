; ---------------------------------------------------------------------------
; kernel/modules/floppysv.asm - the AMSDOS/floppy WRITE path, as a paged kernel
; module (#135). The resident backend (lib/fs_amsdos.asm) keeps directory listing +
; file load; the write path (block allocation, sector assembly, directory
; writeback) is large and only needed on a save, so it lives here and is loaded on
; demand into DATA_MODTOP (the free upper part of PAGE_DATA, shared with the gbfat
; IDE-write module - the two are never live at once). It shares the low-level FDC
; primitives (lib/fs_amsdos_core.asm) with the resident reader - one source, two
; assemblies - and is self-contained otherwise: own state + the shared fixed-address
; low-RAM buffers, reading its inputs from the transfer area the resident stub fills:
;   FSV_TX_LEN  (#1700, word)   bytes to write, #FFFF delete, #FFFE free floppy,
;                              #FFFD free Albireo/CH376, #FFFC read chunk
;   FSV_TX_NAME (#1702, 11)     8.3 name
;   FSV_TX_RES  (#170D, byte)   result: 1 = saved, 0 = failed
;   FSV_TX_UNIT (#170F, byte)   floppy unit (0 = A, 1 = B)
;                              #FF = Albireo/CH376 append/write operation
;   FSV_TX_PATH (#1710, 64)     card path prefix for Albireo/CH376 operations
;   FSV_TX_DATA (#2200, <=6.5KiB) data copied out of the app's page by the stub
;
; Build: tools/build_floppymod.sh -> build/FLOPPYSV.RAW, packaged as FLOPPYSV.BIN.
; ---------------------------------------------------------------------------

FLOPPYSV_ORG    equ   #6000        ; = DATA_MODTOP (must match lib/gbapp.inc)
fsam_buf        equ   #1A00        ; shared floppy directory buffer (resident agrees)
fs_secbuf       equ   #1800        ; shared low-RAM sector buffer
fsam_wbuf       equ   fs_secbuf    ; the 512-byte sector being assembled
FSV_TX_LEN      equ   #1700
FSV_TX_NAME     equ   #1702
FSV_TX_RES      equ   #170D
FSV_TX_ERR      equ   #170E
FSV_TX_UNIT     equ   #170F
FSV_TX_PATH     equ   #1710
FSV_TX_DATA     equ   #2200
                ifndef PREEMPTIVE
PREEMPTIVE      equ   0
                endif
                if PREEMPTIVE
FSV_TX_MAX      equ   #1A00
                else
FSV_TX_MAX      equ   #1C00
                endif
FS_LOAD_OFS     equ   #144C        ; 24-bit read offset for #FFFC chunk-read op
FS_XFLAGS       equ   #144F        ; bit1 = append-write, bit2 = chunk-save marker
fs_ent_size     equ   #14E8
fs_load_max     equ   #14F9
fs_req_name     equ   FSV_TX_NAME  ; the name to find/create (core's namematch uses it)

ALB_CMD         equ   #FE81
ALB_DAT         equ   #FE80
ALBC_GETSTAT    equ   #22
ALBC_RDDATA0    equ   #27
ALBC_WRREQ      equ   #2D
ALBC_SETNAME    equ   #2F
ALBC_FILEOPEN   equ   #32
ALBC_FILEERASE  equ   #35
ALBC_FILECLOSE  equ   #36
ALBC_DIRINFO    equ   #37
ALBC_BYTELOC    equ   #39
ALBC_BYTEREAD   equ   #3A
ALBC_BYTERDGO   equ   #3B
ALBC_BYTEWRITE  equ   #3C
ALBC_BYTEWRGO   equ   #3D
ALBC_DISKQUERY  equ   #3F
ALB_INT_SUCCESS equ   #14
ALB_INT_DISKRD  equ   #1D
ALB_INT_DISKWR  equ   #1E

                org   FLOPPYSV_ORG
; entry: pick up the unit, run the requested operation, store the result byte, return.
; FSV_TX_LEN values:
;   #FFFF = delete FSV_TX_NAME
;   #FFFE = count free 1KB AMSDOS allocation blocks, returned in FSV_TX_LEN
;   #FFFD = query Albireo/CH376 free sectors, returned as KiB in FSV_TX_LEN
;   #FFFC = read chunk at FS_LOAD_OFS into FSV_TX_DATA, length in FSV_TX_LEN
;   #FFFB = read Albireo/CH376 chunk at FS_LOAD_OFS into FSV_TX_DATA
;   #FFFA = delete Albireo/CH376 file
;   other = save that many bytes from FSV_TX_DATA into FSV_TX_NAME
                ld    a,#10
                ld    (FSV_TX_ERR),a
                ld    a,(FSV_TX_UNIT)
                ld    (fsam_unit),a
                ld    hl,(FSV_TX_LEN)
                ld    a,h
                cp    #FF
                jr    nz,flsv_save_entry
                ld    a,l
                cp    #FF
                jr    z,flsv_del_entry
                cp    #FE
                jr    z,flsv_free_entry
                cp    #FD
                jr    z,flsv_alb_entry
                cp    #FC
                jr    z,flsv_read_entry
                cp    #FB
                jr    z,flsv_alb_read_entry
                cp    #FA
                jr    z,flsv_alb_del_entry
                or    a
                jr    flsv_done
flsv_save_entry
                ld    a,(FSV_TX_UNIT)
                cp    #FF
                jr    z,flsv_alb_write_entry
                ld    a,(FS_XFLAGS)
                and   2
                jr    z,flsv_save_full
                call  flsv_append
                jr    flsv_done
flsv_save_full  call  flsv_save
                jr    flsv_done
flsv_del_entry  call  flsv_delete
                jr    flsv_done
flsv_free_entry call  flsv_free
                jr    flsv_done
flsv_alb_entry  call  flsv_alb_free
                jr    flsv_done
flsv_read_entry call  flsv_read_chunk
                jr    flsv_done
flsv_alb_read_entry
                call  flsv_alb_read
                jr    flsv_done
flsv_alb_write_entry
                call  flsv_alb_append
                jr    flsv_done
flsv_alb_del_entry
                call  flsv_alb_delete
flsv_done
                ld    a,1
                jr    c,flsv_res
                xor   a
flsv_res
                ld    (FSV_TX_RES),a
                ret

; ---------------------------------------------------------------------------
; flsv_save: create/overwrite fs_req_name with the first copy chunk from
; FSV_TX_DATA. Writes a 128-byte AMSDOS header + data into a single CP/M extent;
; later chunks use flsv_append to grow additional extents.
flsv_save
                call  fsam_motor_on
                call  fsam_read_dir                  ; directory -> fsam_buf
                ld    a,1                            ; overwrite starts fresh: remove stale
                ld    (fsv_extcnt),a                 ; higher extents from an older copy
                call  fsv_delete_high_extents
                ld    hl,(FSV_TX_LEN)                ; Rc = ceil((128+len)/128)
                ld    de,128
                add   hl,de
                ld    de,127
                add   hl,de
                ld    a,h
                add   a,a
                ld    d,a
                ld    a,l
                rlca
                and   1
                add   a,d
                ld    (fsam_rc),a
                add   a,7                              ; nblk = ceil(Rc/8) 1KB blocks
                srl   a
                srl   a
                srl   a
                ld    (fsv_nblk),a
                cp    17
                jr    c,fsv_size_ok
                ld    a,#11
                jr    fsv_fail_a                       ; > 16 blocks -> single extent only
fsv_size_ok
                ld    ix,fsam_buf                    ; find the Ex=0 entry by name
                ld    b,64
fsv_scan
                ld    a,(ix+0)
                cp    #E5
                jr    z,fsv_next
                ld    a,(ix+12)
                or    a
                jr    nz,fsv_next
                push  bc
                call  fsam_namematch
                pop   bc
                jr    z,fsv_have                       ; existing file -> reuse the entry
fsv_next
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  fsv_scan
                call  fsv_find_free_entry             ; not found -> create in a free slot
                jr    c,fsv_new_entry
                ld    a,#12
                jr    fsv_fail_a                       ; directory full
fsv_new_entry
                push  ix                              ; init it: user 0, name, the rest 0
                pop   hl
                ld    (hl),0
                push  ix
                pop   de
                inc   de
                ld    bc,31
                ldir
                ld    hl,fs_req_name
                push  ix
                pop   de
                inc   de
                ld    bc,11
                ldir
                jr    fsv_have
fsv_fail
                call  fsam_motor_off
                or    a                               ; NC
                ret
fsv_fail_a
                ld    (FSV_TX_ERR),a
                jr    fsv_fail
fsv_have
                call  fsv_ensure_blocks               ; alloc/free 1KB blocks to fsv_nblk
                jr    c,fsv_fits
                ld    a,#13
                jr    fsv_fail_a                       ; disk full
fsv_fits
                xor   a
                ld    (FSV_TX_ERR),a
                ld    hl,fsam_wbuf                    ; build the 128-byte header
                ld    de,fsam_wbuf+1
                ld    bc,127
                ld    (hl),0
                ldir                                  ; zero 128 bytes
                ld    hl,fs_req_name                  ; name -> [1..11]
                ld    de,fsam_wbuf+1
                ld    bc,11
                ldir
                ld    a,2
                ld    (fsam_wbuf+18),a                ; type = binary
                ld    hl,(FSV_TX_LEN)
                ld    (fsam_wbuf+24),hl               ; logical length
                ld    (fsam_wbuf+64),hl               ; real length (low 16)
                ld    hl,fsam_wbuf                    ; checksum = sum [0..66]
                ld    de,0
                ld    b,67
fsv_sum
                ld    a,(hl)
                add   a,e
                ld    e,a
                jr    nc,fsv_snc
                inc   d
fsv_snc
                inc   hl
                djnz  fsv_sum
                ex    de,hl
                ld    (fsam_wbuf+67),hl
                ld    hl,FSV_TX_DATA                ; data stream
                ld    (fsv_dptr),hl
                ld    hl,(FSV_TX_LEN)
                ld    (fsv_drem),hl
                xor   a
                ld    (fsv_si),a
                ld    a,#FF
                ld    (fsv_curtrk),a                  ; force a seek
                ld    a,(fsam_rc)                     ; nsec = ceil(Rc/4)
                add   a,3
                rrca
                rrca
                and   #3F
                ld    (fsv_nsec),a
fsv_wr
                ld    a,(fsv_nsec)
                or    a
                jr    z,fsv_dir
                dec   a
                ld    (fsv_nsec),a
                ld    a,(fsv_si)                      ; assemble the sector
                or    a
                jr    nz,fsv_body
                ld    hl,fsam_wbuf+128                ; sector 0: header + data
                ld    bc,384
                call  fsv_filldata
                jr    fsv_emit
fsv_body
                ld    hl,fsam_wbuf
                ld    bc,512
                call  fsv_filldata
fsv_emit
                ld    a,(fsv_si)                      ; block = blocklist[si/2]
                srl   a
                ld    e,a
                ld    d,0
                push  ix
                pop   hl
                ld    bc,16
                add   hl,bc
                add   hl,de
                ld    l,(hl)
                ld    h,0
                add   hl,hl                            ; block*2
                ld    a,(fsv_si)
                and   1
                or    l
                ld    l,a                              ; L = block*2 + (si&1)
                call  fsam_div9                        ; HL/9 -> B=track, A=remainder
                ld    c,a
                ld    a,b
                ld    e,a                              ; E = track
                ld    a,(fsv_curtrk)
                cp    e
                jr    z,fsv_noseek
                ld    a,e
                ld    (fsv_curtrk),a
                push  bc
                ld    a,e
                call  fsam_seek
                pop   bc
fsv_noseek
                ld    a,(fsv_curtrk)
                ld    d,a                              ; D = track
                ld    a,#C1
                add   a,c
                ld    e,a                              ; E = physical sector
                ld    hl,fsam_wbuf
                ld    (fsam_src),hl
                call  fsam_write_sector
                ld    a,(fsv_si)
                inc   a
                ld    (fsv_si),a
                jr    fsv_wr
fsv_dir
                ld    a,(fsam_rc)                     ; commit the new record count
                ld    (ix+15),a
                xor   a
                ld    (ix+12),a                        ; Ex = 0 (single extent)
                call  fsv_write_dir
                call  fsam_motor_off
                scf
                ret

; flsv_delete: mark every directory extent matching fs_req_name as deleted and
; write the AMSDOS directory back. The implicit allocation table is the surviving
; directory entries, so clearing the extents frees the file's blocks.
flsv_delete
                call  fsam_motor_on
                call  fsam_read_dir
                xor   a
                ld    (fsv_deleted),a
                ld    ix,fsam_buf
                ld    b,64
fdl_scan
                ld    a,(ix+0)
                cp    #E5
                jr    z,fdl_next
                push  bc
                call  fsam_namematch
                pop   bc
                jr    nz,fdl_next
                ld    (ix+0),#E5
                ld    a,1
                ld    (fsv_deleted),a
fdl_next
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  fdl_scan
                ld    a,(fsv_deleted)
                or    a
                jr    z,fdl_fail
                call  fsv_write_dir
                call  fsam_motor_off
                scf
                ret
fdl_fail
                call  fsam_motor_off
                or    a
                ret

; flsv_read_chunk: read a logical payload slice from an existing headed AMSDOS
; file, spanning CP/M extents as needed. FS_LOAD_OFS is the logical offset after
; the AMSDOS header; returned bytes land in FSV_TX_DATA and the count is written
; back to FSV_TX_LEN.
flsv_read_chunk
                call  fsam_motor_on
                call  fsam_read_dir
                ld    ix,fsam_buf
                ld    b,64
frc_scan
                ld    a,(ix+0)
                cp    #E5
                jr    z,frc_next
                ld    a,(ix+12)
                or    a
                jr    nz,frc_next
                push  bc
                call  fsam_namematch
                pop   bc
                jr    z,frc_have
frc_next
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  frc_scan
                ld    a,#16
                jp    frc_fail_a
frc_have
                ld    a,(FS_LOAD_OFS+2)
                or    a
                jp    nz,frc_empty
                ld    a,#FF
                ld    (fsv_curtrk),a
                xor   a
                call  fsv_read_abs_sector_idx
                jp    nc,frc_bad_extent
                call  fsv_header_len
                jr    nc,frc_nohdr
                ld    (fsv_newlen),hl                 ; logical payload length
                ld    hl,128
                ld    (fsv_oldlen),hl                 ; physical header bias
                jr    frc_len_ok
frc_nohdr
                ld    a,(ix+15)
                call  fsv_rc_bytes
                ld    (fsv_newlen),hl
                ld    hl,0
                ld    (fsv_oldlen),hl
frc_len_ok
                ld    hl,(FS_LOAD_OFS)                ; EOF if offset >= length
                ld    de,(fsv_newlen)
                or    a
                sbc   hl,de
                jp    nc,frc_empty

                ld    hl,(fsv_newlen)                 ; take = min(max, len - offset)
                ld    de,(FS_LOAD_OFS)
                or    a
                sbc   hl,de
                ld    de,(fs_load_max)
                push  hl
                or    a
                sbc   hl,de
                pop   hl
                jr    c,frc_take_avail
                ex    de,hl
frc_take_avail
                ld    (FSV_TX_LEN),hl
                ld    (fsv_drem),hl
                ld    hl,(FS_LOAD_OFS)                ; physical = logical + bias
                ld    de,(fsv_oldlen)
                add   hl,de
                ld    (fsv_phys),hl
                ld    hl,FSV_TX_DATA
                ld    (fsv_dptr),hl
frc_loop
                ld    hl,(fsv_drem)
                ld    a,h
                or    l
                jr    z,frc_done
                ld    a,(fsv_phys+1)                  ; sector index = phys / 512
                srl   a
                call  fsv_read_abs_sector_idx
                jp    nc,frc_bad_extent
                ld    hl,(fsv_phys)                   ; sector offset = phys & 511
                ld    a,h
                and   1
                ld    h,a
                ld    (fsv_off),hl
                ld    de,512
                ex    de,hl
                or    a
                sbc   hl,de                           ; room = 512 - offset
                ld    de,(fsv_drem)
                push  hl
                or    a
                sbc   hl,de
                pop   hl
                jr    c,frc_take_room
                ex    de,hl
frc_take_room
                ld    (fsv_take),hl
                ld    hl,fsam_wbuf
                ld    de,(fsv_off)
                add   hl,de
                ld    de,(fsv_dptr)
                ld    bc,(fsv_take)
                ldir
                ld    (fsv_dptr),de
                ld    hl,(fsv_phys)
                ld    de,(fsv_take)
                add   hl,de
                ld    (fsv_phys),hl
                ld    hl,(fsv_drem)
                or    a
                sbc   hl,de
                ld    (fsv_drem),hl
                jr    frc_loop
frc_done
                ld    hl,(FSV_TX_LEN)
                ld    (fs_ent_size),hl
                ld    hl,0
                ld    (fs_ent_size+2),hl
                call  fsam_motor_off
                scf
                ret
frc_empty
                ld    hl,0
                ld    (FSV_TX_LEN),hl
                ld    (fs_ent_size),hl
                ld    (fs_ent_size+2),hl
                call  fsam_motor_off
                scf
                ret
frc_fail_a
                ld    (FSV_TX_ERR),a
                call  fsam_motor_off
                or    a
                ret
frc_bad_extent
                ld    a,#17
                jr    frc_fail_a

; flsv_append: append FSV_TX_LEN bytes from FSV_TX_DATA to an existing headed
; AMSDOS file, creating/updating CP/M extents as the file grows. This is the CPC
; side of file-manager chunked copy: the first chunk uses flsv_save/create, later
; chunks use this path.
flsv_append
                call  fsam_motor_on
                call  fsam_read_dir
                ld    ix,fsam_buf                    ; find the existing Ex=0 entry
                ld    b,64
fav_scan
                ld    a,(ix+0)
                cp    #E5
                jr    z,fav_next
                ld    a,(ix+12)
                or    a
                jr    nz,fav_next
                push  bc
                call  fsam_namematch
                pop   bc
                jr    z,fav_have
fav_next
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  fav_scan
                ld    a,#14
                jp    fav_fail_a                      ; append target missing
fav_have
                ld    a,#FF
                ld    (fsv_curtrk),a
                xor   a
                ld    hl,fsam_wbuf
                ld    (fsam_dst),hl
                call  fsv_read_sector_idx             ; sector 0 -> header buffer
                call  fsv_header_len                  ; HL = old logical length
                jp    nc,fav_fail_hdr
                ld    (fsv_oldlen),hl
                ld    de,(FSV_TX_LEN)
                add   hl,de
                jp    c,fav_fail_big
                ld    (fsv_newlen),hl

                ld    hl,(fsv_newlen)
                call  fsv_prepare_extents
                jp    nc,fav_fail_a

                ld    hl,(fsv_newlen)                  ; update header length fields
                ld    (fsam_wbuf+24),hl
                ld    (fsam_wbuf+64),hl
                call  fsv_store_header_sum
                xor   a
                call  fsv_write_abs_sector_idx         ; rewrite sector 0/header
                jp    nc,fav_fail_extent

                ld    hl,(fsv_oldlen)                  ; append starts at 128 + old length
                ld    de,128
                add   hl,de
                ld    (fsv_phys),hl
                ld    hl,FSV_TX_DATA
                ld    (fsv_dptr),hl
                ld    hl,(FSV_TX_LEN)
                ld    (fsv_drem),hl
fav_loop
                ld    hl,(fsv_drem)
                ld    a,h
                or    l
                jr    z,fav_commit
                ld    a,(fsv_phys+1)                   ; sector index = phys / 512
                srl   a
                ld    (fsv_si),a
                ld    hl,(fsv_phys)                    ; sector offset = phys & 511
                ld    a,h
                and   1
                ld    h,a
                ld    (fsv_off),hl
                ld    a,h
                or    l
                jr    nz,fav_read_partial              ; non-zero offset: preserve prefix
                call  fsv_clear_wbuf                   ; new sector: deterministic zero padding
                jr    fav_have_sector
fav_read_partial
                ld    hl,fsam_wbuf
                ld    (fsam_dst),hl
                ld    a,(fsv_si)
                call  fsv_read_abs_sector_idx
                jp    nc,fav_fail_extent
fav_have_sector
                ld    hl,(fsv_off)                     ; room = 512 - offset
                ld    de,512
                ex    de,hl
                or    a
                sbc   hl,de
                ld    de,(fsv_drem)
                push  hl
                or    a
                sbc   hl,de
                pop   hl
                jr    c,fav_take_room                  ; room < remaining
                ex    de,hl                            ; else take remaining
fav_take_room
                ld    (fsv_take),hl
                ld    hl,fsam_wbuf
                ld    de,(fsv_off)
                add   hl,de
                ld    bc,(fsv_take)
                call  fsv_filldata
                ld    a,(fsv_si)
                call  fsv_write_abs_sector_idx
                jp    nc,fav_fail_extent
                ld    hl,(fsv_phys)
                ld    de,(fsv_take)
                add   hl,de
                ld    (fsv_phys),hl
                jr    fav_loop
fav_commit
                call  fsv_write_dir
                call  fsam_motor_off
                scf
                ret
fav_fail_hdr
                ld    a,#15
                jr    fav_fail_a
fav_fail_big
                ld    a,#11
                jr    fav_fail_a
fav_fail_full
                ld    a,#13
                jr    fav_fail_a
fav_fail_extent
                ld    a,#17
fav_fail_a
                ld    (FSV_TX_ERR),a
                call  fsam_motor_off
                or    a
                ret

; flsv_free: count unused 1KB DATA-format allocation blocks. Blocks 0 and 1 are
; the directory, so usable data blocks are 2..179. The AMSDOS allocation map is
; implicit in every live directory extent's 16-byte block list.
flsv_free
                call  fsam_motor_on
                call  fsam_read_dir
                ld    hl,0
                ld    (fsv_freecnt),hl
                ld    a,2
ffr_try
                ld    (fsv_cand),a
                call  fsv_block_used                  ; Z = used, NZ = free
                jr    z,ffr_used
                ld    hl,(fsv_freecnt)
                inc   hl
                ld    (fsv_freecnt),hl
ffr_used
                ld    a,(fsv_cand)
                inc   a
                cp    180
                jr    c,ffr_try
                ld    hl,(fsv_freecnt)
                ld    (FSV_TX_LEN),hl
                call  fsam_motor_off
                scf
                ret

; flsv_alb_free: CH376 DISK_QUERY returns total sectors, free sectors, and FAT
; type. Convert free sectors to KiB (512-byte sectors / 2), saturating at #FFFF.
flsv_alb_free
                ld    a,ALBC_DISKQUERY
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jr    nz,afb_fail
                ld    a,ALBC_RDDATA0
                call  alb_sendcmd
                in    a,(c)                      ; payload length
                cp    9
                jr    c,afb_fail
                ld    a,4                         ; skip total_sectors[4]
                call  alb_invoid
                in    a,(c)                       ; free sector byte 0
                ld    l,a
                in    a,(c)                       ; free sector byte 1
                ld    e,a
                in    a,(c)                       ; free sector byte 2
                ld    d,a
                in    a,(c)                       ; free sector byte 3
                ld    h,a
                in    a,(c)                       ; fs_type (discard)
                ld    a,h
                or    a
                jr    nz,afb_sat
                ld    a,d
                cp    2
                jr    nc,afb_sat
                ld    a,l                         ; HL = free_sectors >> 1
                srl   a
                ld    l,a
                ld    a,e
                and   1
                jr    z,afb_low_ok
                set   7,l
afb_low_ok
                ld    a,e
                srl   a
                ld    h,a
                ld    a,d
                or    a
                jr    z,afb_ok
                set   7,h
afb_ok
                ld    (FSV_TX_LEN),hl
                scf
                ret
afb_sat
                ld    hl,#FFFF
                jr    afb_ok
afb_fail
                or    a
                ret

; flsv_alb_read: read up to fs_load_max bytes from an Albireo/CH376 file at
; FS_LOAD_OFS. This is the card-source half of File Manager chunked copy.
flsv_alb_read
                call  alb_open_tx
                jr    nc,far_fail
                call  alb_seek_load_ofs
                jr    nc,far_fail_close
                ld    hl,FSV_TX_DATA
                ld    (fsv_dptr),hl
                ld    hl,(fs_load_max)
                ld    (fsv_drem),hl
                ld    hl,0
                ld    (FSV_TX_LEN),hl
                ld    a,ALBC_BYTEREAD
                call  alb_sendcmd
                xor   a
                out   (c),a
                ld    a,#1C
                out   (c),a
                call  alb_waitint
far_loop
                push  af
                ld    a,ALBC_RDDATA0
                call  alb_sendcmd
                in    a,(c)
                or    a
                jr    z,far_done_pop
                ld    e,a
                ld    d,0
                ld    hl,(fsv_dptr)
                call  alb_inira
                ld    (fsv_dptr),hl
                ld    hl,(FSV_TX_LEN)
                add   hl,de
                ld    (FSV_TX_LEN),hl
                ld    hl,(fsv_drem)
                or    a
                sbc   hl,de
                ld    (fsv_drem),hl
                ld    a,h
                or    l
                jr    z,far_done_pop
                pop   af
                cp    ALB_INT_SUCCESS
                jr    z,far_done
                cp    ALB_INT_DISKRD
                jr    nz,far_fail_close
                ld    a,ALBC_BYTERDGO
                call  alb_sendcmd
                call  alb_waitint
                jr    far_loop
far_done_pop
                pop   af
far_done
                call  alb_close0
                ld    hl,(FSV_TX_LEN)
                ld    (fs_ent_size),hl
                scf
                ret
far_fail_close
                call  alb_close0
far_fail
                or    a
                ret

; flsv_alb_append: append staged chunk bytes to an existing Albireo/CH376 file.
; The first copy chunk uses the resident FILE_CREATE path; later chunks enter here.
flsv_alb_append
                call  alb_open_tx
                jr    nc,faa_fail
                call  alb_dir_size
                jr    nc,faa_fail_close
                call  alb_seek_size
                jr    nc,faa_fail_close
                ld    a,ALBC_BYTEWRITE
                call  alb_sendcmd
                ld    hl,(FSV_TX_LEN)
                ld    a,l
                out   (c),a
                ld    a,h
                out   (c),a
                ld    hl,FSV_TX_DATA
                ld    (fsv_dptr),hl
                call  alb_waitint
faa_loop
                cp    ALB_INT_SUCCESS
                jr    z,faa_close_ok
                cp    ALB_INT_DISKWR
                jr    nz,faa_fail_close
                ld    a,ALBC_WRREQ
                call  alb_sendcmd
                in    a,(c)
                or    a
                jr    z,faa_go
                ld    hl,(fsv_dptr)
                call  alb_outira
                ld    (fsv_dptr),hl
faa_go
                ld    a,ALBC_BYTEWRGO
                call  alb_sendcmd
                call  alb_waitint
                jr    faa_loop
faa_close_ok
                call  alb_close1
                scf
                ret
faa_fail_close
                call  alb_close0
faa_fail
                or    a
                ret

flsv_alb_delete
                call  alb_setname_tx
                ld    a,ALBC_FILEERASE
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jr    nz,fad_fail
                scf
                ret
fad_fail
                or    a
                ret

alb_open_tx
                call  alb_setname_tx
                ld    a,ALBC_FILEOPEN
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jr    z,aot_ok
                ld    a,(FSV_TX_PATH)
                or    a
                jr    z,aot_fail
                ld    a,ALBC_SETNAME
                call  alb_sendcmd
                call  alb_emit_path_tx
                xor   a
                out   (c),a
                ld    a,ALBC_FILEOPEN
                call  alb_sendcmd
                call  alb_waitint
                ld    a,ALBC_SETNAME
                call  alb_sendcmd
                call  alb_emit_83_tx
                xor   a
                out   (c),a
                ld    a,ALBC_FILEOPEN
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jr    z,aot_ok
aot_fail
                or    a
                ret
aot_ok
                scf
                ret

alb_setname_tx
                ld    a,ALBC_SETNAME
                call  alb_sendcmd
                call  alb_emit_path_tx
                ld    a,'/'
                out   (c),a
                call  alb_emit_83_tx
                xor   a
                out   (c),a
                ret

alb_emit_path_tx
                ld    hl,FSV_TX_PATH
aepx_loop
                ld    a,(hl)
                or    a
                ret   z
                inc   b
                outi
                jr    aepx_loop

alb_emit_83_tx
                ld    hl,FSV_TX_NAME
                ld    d,8
ae8x_nm
                ld    a,(hl)
                cp    ' '
                jr    z,ae8x_ext
                out   (c),a
                inc   hl
                dec   d
                jr    nz,ae8x_nm
ae8x_ext
                ld    hl,FSV_TX_NAME+8
                ld    a,(hl)
                cp    ' '
                ret   z
                ld    a,'.'
                out   (c),a
                ld    d,3
ae8x_e1
                ld    a,(hl)
                cp    ' '
                ret   z
                out   (c),a
                inc   hl
                dec   d
                jr    nz,ae8x_e1
                ret

alb_seek_load_ofs
                ld    a,ALBC_BYTELOC
                call  alb_sendcmd
                ld    a,(FS_LOAD_OFS)
                out   (c),a
                ld    a,(FS_LOAD_OFS+1)
                out   (c),a
                ld    a,(FS_LOAD_OFS+2)
                out   (c),a
                xor   a
                out   (c),a
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jr    nz,asl_fail
                scf
                ret
asl_fail
                or    a
                ret

alb_dir_size
                ld    a,ALBC_DIRINFO
                call  alb_sendcmd
                xor   a
                out   (c),a
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jr    nz,ads_fail
                ld    a,ALBC_RDDATA0
                call  alb_sendcmd
                in    a,(c)
                cp    32
                jr    nz,ads_fail
                ld    a,28
                call  alb_invoid
                ld    hl,fsv_phys
                ld    a,4
                call  alb_inira
                scf
                ret
ads_fail
                or    a
                ret

alb_seek_size
                ld    a,ALBC_BYTELOC
                call  alb_sendcmd
                ld    hl,fsv_phys
                ld    d,4
ass_loop
                ld    a,(hl)
                out   (c),a
                inc   hl
                dec   d
                jr    nz,ass_loop
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jr    nz,ass_fail
                scf
                ret
ass_fail
                or    a
                ret

alb_close0
                xor   a
                jr    alb_close
alb_close1
                ld    a,1
alb_close
                ld    e,a
                ld    a,ALBC_FILECLOSE
                call  alb_sendcmd
                out   (c),e
                call  alb_waitint
                ret

alb_sendcmd
                ld    bc,ALB_CMD
                out   (c),a
                dec   c
                ret

alb_waitint
                push  de
                ld    de,0
awi_loop
                ld    bc,ALB_CMD
                in    a,(c)
                rla
                jr    nc,awi_got
                dec   de
                ld    a,d
                or    e
                jr    nz,awi_loop
awi_got
                pop   de
                ld    a,ALBC_GETSTAT
                out   (c),a
                dec   c
                in    a,(c)
                ret

alb_inira
                ini
                inc   b
                dec   a
                jr    nz,alb_inira
                ret

alb_outira
                inc   b
                outi
                dec   a
                jr    nz,alb_outira
                ret

alb_invoid
                push  af
                in    a,(c)
                pop   af
                dec   a
                jr    nz,alb_invoid
                ret

; fsv_header_len: validate fsam_wbuf as an AMSDOS header. CF set and HL =
; logical length on success, NC if the checksum does not match.
fsv_header_len
                ld    hl,fsam_wbuf
                ld    de,0
                ld    b,67
fhl_sum
                ld    a,(hl)
                add   a,e
                ld    e,a
                jr    nc,fhl_nc
                inc   d
fhl_nc
                inc   hl
                djnz  fhl_sum
                ld    hl,fsam_wbuf+67
                ld    a,(hl)
                cp    e
                jr    nz,fhl_bad
                inc   hl
                ld    a,(hl)
                cp    d
                jr    nz,fhl_bad
                ld    hl,(fsam_wbuf+24)
                scf
                ret
fhl_bad
                or    a
                ret

; fsv_store_header_sum: recompute the AMSDOS header checksum in fsam_wbuf.
fsv_store_header_sum
                ld    hl,fsam_wbuf
                ld    de,0
                ld    b,67
fsh_sum
                ld    a,(hl)
                add   a,e
                ld    e,a
                jr    nc,fsh_nc
                inc   d
fsh_nc
                inc   hl
                djnz  fsh_sum
                ex    de,hl
                ld    (fsam_wbuf+67),hl
                ret

; fsv_entry_sector_de: fsv_si + IX block list -> D=track, E=sector id, seeking
; as needed. Shared by the append read/modify/write path.
fsv_entry_sector_de
                ld    a,(fsv_si)
                srl   a
                ld    e,a
                ld    d,0
                push  ix
                pop   hl
                ld    bc,16
                add   hl,bc
                add   hl,de
                ld    l,(hl)
                ld    h,0
                add   hl,hl
                ld    a,(fsv_si)
                and   1
                or    l
                ld    l,a
                call  fsam_div9
                ld    c,a
                ld    a,b
                ld    e,a
                ld    a,(fsv_curtrk)
                cp    e
                jr    z,fes_noseek
                ld    a,e
                ld    (fsv_curtrk),a
                push  bc
                ld    a,e
                call  fsam_seek
                pop   bc
fes_noseek
                ld    a,(fsv_curtrk)
                ld    d,a
                ld    a,#C1
                add   a,c
                ld    e,a
                ret

; A = sector index within the file extent.
fsv_read_sector_idx
                ld    (fsv_si),a
                call  fsv_entry_sector_de
                ld    hl,fsam_wbuf
                ld    (fsam_dst),hl
                jp    fsam_read_sector

; A = sector index within the file extent.
fsv_write_sector_idx
                ld    (fsv_si),a
                call  fsv_entry_sector_de
                ld    hl,fsam_wbuf
                ld    (fsam_src),hl
                jp    fsam_write_sector

; A = absolute sector index in the physical AMSDOS stream -> D=track, E=sector id.
; This path is used by chunk read/append across extents. Compute the CP/M block
; index directly, then select Extent = block/16 and block-list slot = block&15.
fsv_abs_sector_de
                ld    c,a
                and   1
                ld    (fsv_absbit),a
                ld    a,c
                srl   a
                ld    (fsv_absblk),a
                srl   a
                srl   a
                srl   a
                srl   a
                call  fsv_find_extent
                ret   nc
                ld    a,(fsv_absblk)
                and   #0F
                ld    e,a
                ld    d,0
                push  ix
                pop   hl
                ld    bc,16
                add   hl,bc
                add   hl,de
                ld    l,(hl)
                ld    h,0
                add   hl,hl
                ld    a,(fsv_absbit)
                or    l
                ld    l,a
                call  fsam_div9
                ld    c,a
                ld    a,b
                ld    e,a
                ld    a,(fsv_curtrk)
                cp    e
                jr    z,fas_noseek
                ld    a,e
                ld    (fsv_curtrk),a
                push  bc
                ld    a,e
                call  fsam_seek
                pop   bc
fas_noseek
                ld    a,(fsv_curtrk)
                ld    d,a
                ld    a,#C1
                add   a,c
                ld    e,a
                scf
                ret

fsv_read_abs_sector_idx
                call  fsv_abs_sector_de
                ret   nc
                ld    hl,fsam_wbuf
                ld    (fsam_dst),hl
                call  fsam_read_sector
                scf
                ret

fsv_write_abs_sector_idx
                call  fsv_abs_sector_de
                ret   nc
                ld    hl,fsam_wbuf
                ld    (fsam_src),hl
                call  fsam_write_sector
                scf
                ret

; fsv_prepare_extents: HL = new logical payload length. Build/update enough
; CP/M directory extents to hold the 128-byte AMSDOS header plus payload.
; Returns CF set on success; NC with A = FSV_TX_ERR code on failure.
fsv_prepare_extents
                ld    de,128
                add   hl,de
                jp    c,fpe_big
                ld    a,l                         ; total records = ceil(physical / 128)
                and   #7F
                ld    c,a
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,c
                or    a
                jr    z,fpe_recs_ok
                inc   hl
fpe_recs_ok
                ld    (fsv_recs),hl
                ld    de,127                      ; extent count = ceil(records / 128)
                add   hl,de
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
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
                jr    nz,fpe_ext_ok
                inc   a
fpe_ext_ok
                ld    (fsv_extcnt),a
                call  fsv_delete_high_extents
                xor   a
                ld    (fsv_extno),a
fpe_loop
                ld    a,(fsv_extno)
                ld    b,a
                ld    hl,(fsv_recs)
fpe_rem
                ld    a,b
                or    a
                jr    z,fpe_have_rem
                ld    de,128
                or    a
                sbc   hl,de
                dec   b
                jr    fpe_rem
fpe_have_rem
                ld    de,129
                push  hl
                or    a
                sbc   hl,de
                pop   hl
                jr    c,fpe_partial
                ld    a,128
                jr    fpe_have_rc
fpe_partial
                ld    a,l
fpe_have_rc
                ld    (fsam_rc),a
                ld    a,(fsv_extno)
                call  fsv_find_extent
                jr    c,fpe_have_ext
                ld    a,(fsv_extno)
                call  fsv_create_extent
                ret   nc
fpe_have_ext
                ld    a,(fsv_extno)
                ld    (ix+12),a
                xor   a
                ld    (ix+13),a
                ld    (ix+14),a
                ld    a,(fsam_rc)
                ld    (ix+15),a
                add   a,7
                srl   a
                srl   a
                srl   a
                ld    (fsv_nblk),a
                call  fsv_ensure_blocks
                jr    nc,fpe_full
                ld    a,(fsv_extno)
                inc   a
                ld    (fsv_extno),a
                ld    hl,fsv_extcnt
                cp    (hl)
                jr    c,fpe_loop
                scf
                ret
fpe_big
                ld    a,#11
                or    a
                ret
fpe_full
                ld    a,#13
                or    a
                ret

; A = extent number. CF set with IX -> matching live entry.
fsv_find_extent
                ld    (fsv_extno),a
                ld    ix,fsam_buf
                ld    b,64
ffe2_scan
                ld    a,(ix+0)
                cp    #E5
                jr    z,ffe2_next
                ld    a,(ix+14)
                or    a
                jr    nz,ffe2_next
                ld    a,(ix+12)
                ld    hl,fsv_extno
                cp    (hl)
                jr    nz,ffe2_next
                push  bc
                call  fsam_namematch
                pop   bc
                jr    z,ffe2_have
ffe2_next
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  ffe2_scan
                or    a
                ret
ffe2_have
                scf
                ret

; A = extent number. Create a zeroed directory entry with FSV_TX_NAME.
fsv_create_extent
                ld    (fsv_extno),a
                call  fsv_find_free_entry
                jr    nc,fce_noslot
                push  ix
                pop   hl
                ld    (hl),0
                push  ix
                pop   de
                inc   de
                ld    bc,31
                ldir
                ld    hl,fs_req_name
                push  ix
                pop   de
                inc   de
                ld    bc,11
                ldir
                ld    a,(fsv_extno)
                ld    (ix+12),a
                xor   a
                ld    (ix+13),a
                ld    (ix+14),a
                scf
                ret
fce_noslot
                ld    a,#12
                or    a
                ret

; Delete matching directory entries whose Ex is >= fsv_extcnt. Used when a file
; shrinks or a fresh first chunk overwrites an older multi-extent copy.
fsv_delete_high_extents
                ld    ix,fsam_buf
                ld    b,64
fdh_scan
                ld    a,(ix+0)
                cp    #E5
                jr    z,fdh_next
                push  bc
                call  fsam_namematch
                pop   bc
                jr    nz,fdh_next
                ld    a,(ix+12)
                ld    hl,fsv_extcnt
                cp    (hl)
                jr    c,fdh_next
                ld    (ix+0),#E5
fdh_next
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  fdh_scan
                ret

fsv_clear_wbuf
                ld    hl,fsam_wbuf
                ld    de,fsam_wbuf+1
                ld    bc,511
                ld    (hl),0
                ldir
                ret

; A = AMSDOS record count -> HL = bytes.
fsv_rc_bytes
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ret

; fsv_write_dir: write fsam_buf's four AMSDOS directory sectors back.
fsv_write_dir
                ld    a,(fsam_track)
                call  fsam_seek
                ld    hl,fsam_buf
                ld    (fsam_src),hl
                ld    a,(fsam_base)
                ld    e,a
                ld    b,4
fwd_loop
                push  bc
                ld    a,(fsam_track)
                ld    d,a
                call  fsam_write_sector
                pop   bc
                inc   e
                djnz  fwd_loop
                ret

; fsv_filldata: HL=dest, BC=count. Copy min(count, fsv_drem) bytes from (fsv_dptr)
; advancing it, then pad the rest with 0.
fsv_filldata
                ld    a,b
                or    c
                ret   z
                push  hl
                ld    hl,(fsv_drem)
                ld    a,h
                or    l
                pop   hl
                jr    z,fsv_fdpad
                push  bc
                ld    bc,(fsv_dptr)
                ld    a,(bc)
                inc   bc
                ld    (fsv_dptr),bc
                pop   bc
                ld    (hl),a
                inc   hl
                push  hl
                ld    hl,(fsv_drem)
                dec   hl
                ld    (fsv_drem),hl
                pop   hl
                dec   bc
                jr    fsv_filldata
fsv_fdpad
                ld    (hl),0
                inc   hl
                dec   bc
                jr    fsv_filldata

; fsv_find_free_entry: IX -> first &E5 (free) directory slot. CF set, or NC if the
; directory is full.
fsv_find_free_entry
                ld    ix,fsam_buf
                ld    b,64
ffe_loop
                ld    a,(ix+0)
                cp    #E5
                jr    z,ffe_found
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  ffe_loop
                or    a                               ; NC = directory full
                ret
ffe_found
                scf
                ret

; fsv_ensure_blocks: make the entry at IX own exactly fsv_nblk 1KB blocks. Blocks
; are packed at the front of the 16-byte block list. Grows by allocating free
; blocks, shrinks by zeroing the tail. CF set = ok, NC = disk full.
fsv_ensure_blocks
                push  ix                              ; count current blocks -> C
                pop   hl
                ld    de,16
                add   hl,de
                ld    b,16
                ld    c,0
eb_count
                ld    a,(hl)
                or    a
                jr    z,eb_counted                     ; first zero = end (packed front)
                inc   c
                inc   hl
                djnz  eb_count
eb_counted
                ld    a,(fsv_nblk)
                cp    c
                jr    z,eb_ok
                jr    nc,eb_grow                       ; need more blocks
                ld    a,(fsv_nblk)                    ; need fewer -> zero slots [nblk..15]
                ld    c,a
eb_trim
                ld    a,c
                cp    16
                jr    nc,eb_ok
                push  ix
                pop   hl
                ld    de,16
                add   hl,de
                ld    e,c
                ld    d,0
                add   hl,de
                ld    (hl),0
                inc   c
                jr    eb_trim
eb_grow
                ld    a,(fsv_nblk)
                cp    c
                jr    z,eb_ok
                call  fsv_alloc1                       ; -> A = free block, NC = disk full
                ret   nc
                push  ix
                pop   hl
                ld    de,16
                add   hl,de
                ld    e,c
                ld    d,0
                add   hl,de
                ld    (hl),a                           ; store the block at slot C
                inc   c
                jr    eb_grow
eb_ok
                scf
                ret

; fsv_alloc1: find a free 1KB block (2..179; 0/1 are the directory). A new block
; is one that no directory entry references - and because each allocation is
; written into the entry's block list before the next call, repeats are excluded.
; -> A = block, CF set; NC if the disk is full. Preserves BC and IX.
fsv_alloc1
                push  bc
                push  ix
                ld    a,2
fa1_try
                ld    (fsv_cand),a
                call  fsv_block_used                   ; Z if some entry uses it
                jr    nz,fa1_free
                ld    a,(fsv_cand)
                inc   a
                cp    180                              ; DATA format: blocks 0..179
                jr    c,fa1_try
                pop   ix
                pop   bc
                or    a                                ; NC = disk full
                ret
fa1_free
                pop   ix
                pop   bc
                ld    a,(fsv_cand)
                scf
                ret

; fsv_block_used: A = block number -> Z if any directory entry references it.
fsv_block_used
                ld    c,a                              ; C = target block
                ld    hl,fsam_buf
                ld    b,64
fbu_ent
                ld    a,(hl)
                cp    #E5
                jr    z,fbu_skip
                push  hl
                push  bc
                ld    de,16
                add   hl,de                            ; -> block list
                ld    b,16
fbu_blk
                ld    a,(hl)
                cp    c
                jr    z,fbu_hit
                inc   hl
                djnz  fbu_blk
                pop   bc
                pop   hl
fbu_skip
                push  bc
                ld    de,32
                add   hl,de
                pop   bc
                djnz  fbu_ent
                or    1                                ; NZ = free
                ret
fbu_hit
                pop   bc
                pop   hl
                xor   a                                ; Z = used
                ret

                include "../../lib/fs_amsdos_core.asm"

; --- module state (save only) ----------------------------------------------
fsam_src        defw  0            ; fsam_write_sector source pointer
fsam_rc         defb  0            ; record count being written
fsv_nsec        defb  0            ; sectors left to write
fsv_si          defb  0            ; sector index within the file
fsv_curtrk      defb  0            ; track the head is on
fsv_dptr        defw  0            ; pointer into the source data
fsv_drem        defw  0            ; source bytes left
fsv_nblk        defb  0            ; 1KB blocks the file needs
fsv_oldlen      defw  0            ; append: previous logical length
fsv_newlen      defw  0            ; append: new logical length
fsv_phys        defw  0            ; append: physical stream offset (header + data)
fsv_off         defw  0            ; append: offset within current 512-byte sector
fsv_take        defw  0            ; append: bytes to overlay in current sector
fsv_recs        defw  0            ; multi-extent: total CP/M records needed
fsv_extcnt      defb  0            ; multi-extent: number of directory extents needed
fsv_extno       defb  0            ; multi-extent: current Extent number
fsv_cand        defb  0            ; alloc: candidate block being tested
fsv_deleted     defb  0            ; delete: at least one extent was removed
fsv_freecnt     defw  0            ; free-space query: unused 1KB block count
fsv_absblk      defb  0            ; absolute sector helper: CP/M block index
fsv_absbit      defb  0            ; absolute sector helper: sector within 1KB block

; ---------------------------------------------------------------------------
; fsam_write_sector: D=track, E=sector id. Writes 512 bytes from (fsam_src) to
; the sector and advances fsam_src. Mirrors fsam_read_sector with WRITE DATA.
fsam_write_sector
                push  de
                ld    a,#45                          ; WRITE DATA, MFM
                call  fsam_cmd9                       ; issue the command + params
                ld    hl,(fsam_src)
                ld    de,512
fwr_exec
                ld    bc,FSAM_MSR
                in    a,(c)
                bit   7,a                            ; RQM?
                jr    z,fwr_exec
                bit   5,a                            ; still in execution phase?
                jr    z,fwr_result
                ld    a,(hl)
                ld    bc,FSAM_DATA
                out   (c),a
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,fwr_exec
fwr_result
                ld    (fsam_src),hl
                call  fsam_drain                      ; drain the 7 result bytes
                pop   de
                ret

                save  "build/FLOPPYSV.RAW",FLOPPYSV_ORG,$-FLOPPYSV_ORG
