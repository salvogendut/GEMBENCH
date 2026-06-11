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
;   FSV_TX_LEN  (#1400, word)   bytes to write
;   FSV_TX_NAME (#1402, 11)     8.3 name
;   FSV_TX_RES  (#140D, byte)   result: 1 = saved, 0 = failed
;   FSV_TX_UNIT (#140F, byte)   floppy unit (0 = A, 1 = B)
;   FSV_TX_DATA (#2200, <=7KB)  the data, copied out of the app's page by the stub
;
; Build: tools/build_floppymod.sh -> build/FLOPPYSV.RAW, packaged as FLOPPYSV.BIN.
; ---------------------------------------------------------------------------

FLOPPYSV_ORG    equ   #6000        ; = DATA_MODTOP (must match lib/gbapp.inc)
fsam_buf        equ   #1A00        ; shared floppy directory buffer (resident agrees)
fs_secbuf       equ   #1800        ; shared low-RAM sector buffer
fsam_wbuf       equ   fs_secbuf    ; the 512-byte sector being assembled
FSV_TX_LEN      equ   #1400
FSV_TX_NAME     equ   #1402
FSV_TX_RES      equ   #140D
FSV_TX_UNIT     equ   #140F
FSV_TX_DATA     equ   #2200
fs_req_name     equ   FSV_TX_NAME  ; the name to find/create (core's namematch uses it)

                org   FLOPPYSV_ORG
; entry: pick up the unit, run the save, store the result byte, return.
                ld    a,(FSV_TX_UNIT)
                ld    (fsam_unit),a
                call  flsv_save
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
                jr    nc,fsv_fail                      ; > 16 blocks -> single extent only
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
                jr    nc,fsv_fail                      ; directory full
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
fsv_have
                call  fsv_ensure_blocks               ; alloc/free 1KB blocks to fsv_nblk
                jr    nc,fsv_fail                      ; disk full
fsv_fits
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
                ld    a,(fsam_track)                  ; write the directory back
                call  fsam_seek
                ld    hl,fsam_buf
                ld    (fsam_src),hl
                ld    a,(fsam_base)
                ld    e,a
                ld    b,4
fsv_dirloop
                push  bc
                ld    a,(fsam_track)
                ld    d,a
                call  fsam_write_sector
                pop   bc
                inc   e
                djnz  fsv_dirloop
                call  fsam_motor_off
                scf
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
