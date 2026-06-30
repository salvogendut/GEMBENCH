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
;                              #FFFD free Albireo/CH376
;   FSV_TX_NAME (#1702, 11)     8.3 name
;   FSV_TX_RES  (#170D, byte)   result: 1 = saved, 0 = failed
;   FSV_TX_UNIT (#170F, byte)   floppy unit (0 = A, 1 = B)
;   FSV_TX_DATA (#2200, <=7KB)  the data, copied out of the app's page by the stub
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
FSV_TX_DATA     equ   #2200
fs_req_name     equ   FSV_TX_NAME  ; the name to find/create (core's namematch uses it)

ALB_CMD         equ   #FE81
ALB_DAT         equ   #FE80
ALBC_GETSTAT    equ   #22
ALBC_RDDATA0    equ   #27
ALBC_DISKQUERY  equ   #3F
ALB_INT_SUCCESS equ   #14

                org   FLOPPYSV_ORG
; entry: pick up the unit, run the requested operation, store the result byte, return.
; FSV_TX_LEN values:
;   #FFFF = delete FSV_TX_NAME
;   #FFFE = count free 1KB AMSDOS allocation blocks, returned in FSV_TX_LEN
;   #FFFD = query Albireo/CH376 free sectors, returned as KiB in FSV_TX_LEN
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
                or    a
                jr    flsv_done
flsv_save_entry
                call  flsv_save
                jr    flsv_done
flsv_del_entry  call  flsv_delete
                jr    flsv_done
flsv_free_entry call  flsv_free
                jr    flsv_done
flsv_alb_entry  call  flsv_alb_free
flsv_done
                ld    a,1
                jr    c,flsv_res
                xor   a
flsv_res
                ld    (FSV_TX_RES),a
                ret

; ---------------------------------------------------------------------------
; flsv_save: overwrite fs_req_name (must already exist, single extent) with
; fs_save_len bytes from FSV_TX_DATA. Writes a 128-byte AMSDOS header + the data
; into the file's existing allocation blocks, updates the record count, and writes
; the directory back. CF set = saved; NC = not found, or won't fit the current
; allocation (no block allocation / file creation yet).
flsv_save
                call  fsam_motor_on
                call  fsam_read_dir                  ; directory -> fsam_buf
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
                call  fsam_namematch
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
                call  fsam_namematch
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

alb_invoid
                push  af
                in    a,(c)
                pop   af
                dec   a
                jr    nz,alb_invoid
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
fsv_cand        defb  0            ; alloc: candidate block being tested
fsv_deleted     defb  0            ; delete: at least one extent was removed
fsv_freecnt     defw  0            ; free-space query: unused 1KB block count

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
