; ---------------------------------------------------------------------------
; lib/fs_amsdos.asm - storage backend: the AMSDOS directory + file LOAD read
; straight off the floppy via the uPD765 FDC. No AMSDOS/UniDOS ROM involvement, so
; it works on any CPC with a disc drive regardless of which DOS ROM is fitted.
;
; This is the RESIDENT half: directory listing (fsam_dir_first/next), file load
; (fsam_load_file) and the presence probe (fsam_present), plus the shared low-level
; FDC primitives (lib/fs_amsdos_core.asm). The WRITE path is large and only needed
; on a save, so it lives in a paged module (kernel/modules/floppysv.asm); the
; resident fsam_save_file below is a thin stub that marshals + loads it (#135).
;
; Exposes the backend interface (see lib/fs.asm); fields fs_ent_name/attr/size
; live in lib/fs.asm and are shared with the IDE backend.
;   fsam_dir_first -> CF set = first entry ready, NC = empty
;   fsam_dir_next  -> CF set = next entry ready,  NC = end of directory
; ---------------------------------------------------------------------------

; #152: the READ backend (dir/load/present + the FDC core) lives in GEOBENCH.ROM
; (IN_GBROM) and the non-ROM resident build; the GB_ROM resident build (GB_ROM_STUBS)
; replaces it with thin ROM-call stubs (see the else branch after fsam_load_file).
                ifndef GB_ROM_STUBS
                include "fs_amsdos_core.asm"

; ---------------------------------------------------------------------------
; fsam_dir_first: read the whole directory into fsam_buf, then return entry 0.
fsam_dir_first
                call  fsam_motor_on            ; spin up + recalibrate to track 0
                call  fsam_read_dir            ; 4 dir sectors -> fsam_buf
                call  fsam_motor_off
                xor   a
                ld    (fsam_idx),a
                jr    fsam_scan

; fsam_dir_next: advance to the next valid entry.
fsam_dir_next
fsam_scan
                ld    a,(fsam_idx)
                cp    64
                jr    nc,fsam_end             ; past the last directory entry

                ld    l,a                       ; entry ptr = fsam_buf + idx*32
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    de,fsam_buf
                add   hl,de                     ; HL -> entry

                ld    a,(hl)
                cp    #E5
                jr    z,fsam_skip               ; deleted / empty slot
                push  hl
                ld    de,12
                add   hl,de
                ld    a,(hl)                     ; Ex (extent low)
                or    a
                pop   hl
                jr    nz,fsam_skip              ; only extent 0 = one row per file
                push  hl
                ld    de,14
                add   hl,de
                ld    a,(hl)                     ; S2 (extent high)
                or    a
                pop   hl
                jr    nz,fsam_skip
                push  hl
                ld    de,10
                add   hl,de
                ld    a,(hl)                     ; ext[1] bit7 = system attribute
                and   #80
                pop   hl
                jr    nz,fsam_skip              ; hide system files (as CAT does)

                ; valid entry -> fill the shared output fields.
                push  hl
                inc   hl                         ; -> filename (8) then ext (3)
                ld    de,fs_ent_name
                ld    b,11
fsam_cpy
                ld    a,(hl)
                and   #7F                        ; drop attribute bits
                ld    (de),a
                inc   hl
                inc   de
                djnz  fsam_cpy
                pop   hl

                xor   a                           ; AMSDOS is flat: no attr/dirs
                ld    (fs_ent_attr),a

                push  hl                          ; size = Rc * 128 (extent 0)
                ld    de,15
                add   hl,de
                ld    a,(hl)                       ; record count
                pop   hl
                ld    l,a
                ld    h,0
                add   hl,hl                        ; *2
                add   hl,hl                        ; *4
                add   hl,hl                        ; *8
                add   hl,hl                        ; *16
                add   hl,hl                        ; *32
                add   hl,hl                        ; *64
                add   hl,hl                        ; *128
                ld    (fs_ent_size),hl
                xor   a
                ld    (fs_ent_size+2),a
                ld    (fs_ent_size+3),a

                ld    a,(fsam_idx)
                inc   a
                ld    (fsam_idx),a
                scf
                ret
fsam_skip
                ld    a,(fsam_idx)
                inc   a
                ld    (fsam_idx),a
                jr    fsam_scan
fsam_end
                or    a                            ; CF clear = end of directory
                ret

; ---------------------------------------------------------------------------
; fsam_present: is there a readable disk in drive (fsam_unit)? Spins the motor,
; recalibrates and tries a READ ID; a normal result (ST0 IC bits 7-6 == 00)
; means a disk is in the drive. CF set = present.
fsam_present
                ld    bc,FSAM_MSR                     ; #130b: bounded FDC-presence probe FIRST, so a
                ld    d,0                             ; machine with no disc controller (e.g. a stock
fsp_probe                                            ; 464) reports "absent" instead of hanging. An
                in    a,(c)                           ; idle FDC's status reads #80 (RQM=1, DIO=0);
                and   #C0                             ; a missing controller floats high -> #C0 (#00).
                cp    #80
                jr    z,fsp_have
                dec   d                              ; ~256 reads is ample - a present FDC is ready
                jr    nz,fsp_probe                   ; at once; absence just needs to be bounded
                or    a                              ; no FDC within the bound -> absent (CF clear)
                ret
fsp_have
                call  fsam_motor_on                  ; motor + recalibrate the unit
                ld    a,#4A                          ; READ ID
                call  fsam_send
                ld    a,(fsam_unit)
                call  fsam_send
                call  fsam_recv                      ; ST0
                push  af                              ; save it (motor_off clobbers BC)
                call  fsam_recv                      ; ST1
                call  fsam_recv                      ; ST2
                call  fsam_recv                      ; C
                call  fsam_recv                      ; H
                call  fsam_recv                      ; R
                call  fsam_recv                      ; N
                call  fsam_motor_off
                pop   af                             ; ST0 IC bits 7-6 == 00 => OK
                and   #C0
                ret   nz                             ; abnormal -> CF clear (absent)
                scf
                ret

; ---------------------------------------------------------------------------
; fsam_load_file: load fs_req_name (8.3) from the floppy into (fs_load_dst).
; Single extent (Ex=0, <=16KB) only; strips a 128-byte AMSDOS header if present.
; CF set = loaded (fs_ent_size = byte size), NC = not found.
;
; AMSDOS DATA format: 1KB allocation blocks = 2 sectors. Block B's two 512-byte
; sectors are logical sectors L = B*2 and B*2+1; L -> track = L/9, physical
; sector = &C1 + (L mod 9).
fsam_load_file
                call  fsam_present                   ; missing target disk -> fail fast (NC),
                ret   nc                            ; let the caller's fallback handle it
                call  fsam_motor_on                  ; spin up + recalibrate
                call  fsam_read_dir                  ; directory -> fsam_buf

                ld    ix,fsam_buf                    ; find Ex=0 entry by name
                ld    b,64
fslf_scan
                ld    a,(ix+0)
                cp    #E5
                jr    z,fslf_next
                ld    a,(ix+12)                      ; first extent only
                or    a
                jr    nz,fslf_next
                push  bc
                call  fsam_namematch
                pop   bc
                jr    z,fslf_found
fslf_next
                push  bc
                ld    de,32
                add   ix,de
                pop   bc
                djnz  fslf_scan
fslf_toobig
                call  fsam_motor_off
                or    a                               ; not found / too big
                ret

fslf_found
                ld    hl,FS_XFLAGS
                bit   0,(hl)
                jr    z,fslf_whole                   ; bit0 clear -> normal whole-file load
                dec   (hl)                           ; clear bit0; avoid recursive module load
                call  fsam_motor_off                 ; close this read pass before the paged
                                                     ; chunk module reloads from the same disk.
                jp    fsam_load_chunk_mod            ; paged module handles chunked copy reads
fslf_whole
                push  ix                              ; copy 16 block numbers out
                pop   hl
                ld    de,16
                add   hl,de
                ld    de,fslf_blocks
                ld    bc,16
                ldir
                ld    a,(ix+15)                      ; on-disk bytes = Rc*128 > buffer?
                call  fslf_rc_bytes
                ld    de,(fs_load_max)
                ex    de,hl
                or    a
                sbc   hl,de                           ; max - Rc*128
                jr    c,fslf_toobig                   ; Rc*128 > max -> refuse
                ld    a,(ix+15)                      ; Rc records -> sectors = ceil(Rc/4)
                add   a,3
                rrca                                  ; /4 (Rc<=128 so bit7 clear after +3)
                rrca
                and   #3F
                ld    (fslf_secs),a

                ld    hl,(fs_load_dst)
                ld    (fsam_dst),hl                  ; fsam_read_sector advances this
                xor   a
                ld    (fslf_si),a
                ld    a,#FF
                ld    (fslf_curtrk),a                ; force a seek on the first sector
fslf_rd
                ld    a,(fslf_secs)
                or    a
                jr    z,fslf_done
                dec   a
                ld    (fslf_secs),a
                call  fslf_read_sector

                ld    a,(fslf_si)
                inc   a
                ld    (fslf_si),a
                jr    fslf_rd
fslf_done
                call  fsam_motor_off
                ; --- strip a 128-byte AMSDOS header if the checksum matches ---
                ld    hl,(fs_load_dst)
                ld    de,0                            ; sum of bytes [0..66]
                ld    b,67
fslf_sum
                ld    a,(hl)
                add   a,e
                ld    e,a
                jr    nc,fslf_nc
                inc   d
fslf_nc
                inc   hl
                djnz  fslf_sum
                ld    hl,(fs_load_dst)               ; compare to word at [67]
                ld    bc,67
                add   hl,bc
                ld    a,(hl)
                cp    e
                jr    nz,fslf_nohdr
                inc   hl
                ld    a,(hl)
                cp    d
                jr    nz,fslf_nohdr
                ld    hl,(fs_load_dst)               ; header: length = word @ [24]
                ld    bc,24
                add   hl,bc
                ld    c,(hl)
                inc   hl
                ld    b,(hl)
                ld    (fs_ent_size),bc
                ld    hl,0
                ld    (fs_ent_size+2),hl
                ld    hl,(fs_load_dst)               ; shift content down past header
                ld    de,128
                add   hl,de
                ld    de,(fs_load_dst)
                ld    bc,(fs_ent_size)
                ld    a,b
                or    c
                jr    z,fslf_ok                       ; zero-length -> nothing to move
                ldir
                jr    fslf_ok
fslf_nohdr
                ld    a,(ix+15)                      ; no header: size = Rc * 128
                call  fslf_rc_bytes
                ld    (fs_ent_size),hl
                ld    hl,0
                ld    (fs_ent_size+2),hl
fslf_ok
                scf
                ret

; fslf_read_sector: read fslf_si's sector from fslf_blocks into (fsam_dst).
fslf_read_sector
                ld    a,(fslf_si)                    ; block index = si / 2
                srl   a
                ld    e,a
                ld    d,0
                ld    hl,fslf_blocks
                add   hl,de
                ld    l,(hl)                          ; L = block*2 + (si & 1)
                ld    h,0
                add   hl,hl
                ld    a,(fslf_si)
                and   1
                or    l
                ld    l,a
                call  fsam_div9                       ; HL/9 -> B=track, A=remainder
                ld    c,a                             ; remainder
                ld    a,b                             ; track changed? seek
                ld    e,a                             ; keep track in E
                ld    a,(fslf_curtrk)
                cp    e
                jr    z,fslfr_noseek
                ld    a,e
                ld    (fslf_curtrk),a
                push  bc
                ld    a,e
                call  fsam_seek
                pop   bc
fslfr_noseek
                ld    a,(fslf_curtrk)
                ld    d,a                             ; D = track
                ld    a,#C1
                add   a,c
                ld    e,a                             ; E = physical sector
                jp    fsam_read_sector

; fslf_rc_bytes: A = record count -> HL = A * 128.
fslf_rc_bytes
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

                else                          ; #152 GB_ROM resident: thin ROM-call stubs
; fsam_dir_first/dir_next/present/load_file run from GEOBENCH.ROM (idx 2-5). The FDC
; core + the real code are in the ROM; here we page it in, call the slot, and marshal
; the I/O transfer area (#1270) <-> the resident fs_ent_*/fs_req_name/fs_load_*.
fsam_dir_first  ld    hl,#C00C               ; ROM idx2
                call  gb_rom_fsam_invoke
                jr    fsam_ent_out
fsam_dir_next   ld    hl,#C00F               ; ROM idx3
                call  gb_rom_fsam_invoke
                jr    fsam_ent_out
fsam_present    ld    hl,#C015               ; ROM idx5 (presence probe; no entry output)
                jp    gb_rom_fsam_invoke
fsam_load_file  ld    a,(FS_XFLAGS)
                and   1
                jp    nz,fsam_load_chunk_mod
                ld    hl,fs_req_name          ; marshal inputs into the transfer area
                ld    de,FSAM_IO_REQ
                ld    bc,11
                ldir
                ld    hl,(fs_load_dst)
                ld    (FSAM_IO_DST),hl
                ld    hl,(fs_load_max)
                ld    (FSAM_IO_MAX),hl
                ld    hl,#C012               ; ROM idx4
                call  gb_rom_fsam_invoke
                push  af                       ; preserve CF (loaded?)
                ld    hl,FSAM_IO_SIZE         ; copy the loaded size back out
                ld    de,fs_ent_size
                ld    bc,4
                ldir
                pop   af
                ret
; fsam_ent_out: copy the entry the ROM wrote to the transfer area (name+attr+size,
; 16 contiguous bytes) into the resident fs_ent_* fields. Preserves the dir CF.
fsam_ent_out    push  af
                ld    hl,FSAM_IO_NAME
                ld    de,fs_ent_name
                ld    bc,16
                ldir
                pop   af
                ret
; gb_rom_fsam_invoke moved to lib/fs_rom_seam.asm (shared by all backends, #152)
                endif                          ; GB_ROM_STUBS

                ifndef IN_GBROM              ; the WRITE stub is resident-only (not in the ROM)
; ---------------------------------------------------------------------------
; fsam_save_file: resident stub. The floppy WRITE path (block alloc + sector
; assembly + directory writeback) is large and only needed on a save, so it lives
; in a paged module (kernel/modules/floppysv.asm) loaded on demand - the gbfat
; pattern (#135). This stub stages the source out of the caller's app page into low
; RAM (the module can't reach another page mapped in the same #4000-#7FFF window),
; marshals name/len/unit into the transfer area, loads + CALLs the module.
;   FSV_TX_LEN/NAME/RES/UNIT  the marshalling slots (reuse the gbfat area - the IDE
;                             write + floppy write are never live at once)
;   FSV_TX_DATA (<=6.5 KiB)   the staged source data
FSV_TX_LEN      equ   #1700
FSV_TX_NAME     equ   #1702
FSV_TX_RES      equ   #170D
FSV_TX_UNIT     equ   #170F
FSV_TX_DATA     equ   #2200
                if PREEMPTIVE
FSV_TX_MAX      equ   #1A00        ; 6.5 KiB cap; #3C00..#3DFF is scheduler RAM
                else
                ifdef PLATFORM_CPC
FSV_TX_MAX      equ   #1A00        ; CPC v6 architecture state occupies #3C00..#3DFF
                else
FSV_TX_MAX      equ   #1C00
                endif
                endif

fsam_free_mod_op
                ld    (FSV_TX_LEN),hl
                jp    floppysv_run

fsam_load_chunk_mod
                xor   a
                ld    (FS_XFLAGS),a
                ld    hl,#FFFC
                call  fsamv_common
                ret   nc
                ld    hl,(FSV_TX_LEN)
                jp    fs_chunk_to_dst

; fsam_delete_file: ask FLOPPYSV.MOD to mark matching directory extents deleted
; and write the directory back. FSV_TX_LEN=#FFFF is the module operation marker.
fsam_delete_file
                ld    hl,#FFFF
                jr    fsamv_common

fsam_save_file
                ld    hl,(fs_save_len)        ; refuse > staging cap
                ld    de,FSV_TX_MAX+1
                or    a
                sbc   hl,de
                jr    c,fsamv_ok
                or    a                        ; too big -> NC
                ret
fsamv_ok
                ld    hl,(fs_save_src)        ; stage the data out of the caller's page
                ld    de,FSV_TX_DATA          ; into low RAM (caller's page mapped now)
                ld    bc,(fs_save_len)
                ld    a,b
                or    c
                jr    z,fsamv_nlen
                ldir
fsamv_nlen
                ld    hl,(fs_save_len)
fsamv_common
                ld    (FSV_TX_LEN),hl
                ld    hl,fs_req_name          ; name -> the transfer area
                ld    de,FSV_TX_NAME
                call  copy11
                ld    a,(fsam_unit)           ; which floppy unit (0=A,1=B)
                ld    (FSV_TX_UNIT),a
                ; fall through to load + run the module

; floppysv_run: page in PAGE_DATA, load FLOPPYSV.BIN to DATA_MODTOP via the read
; path (from the boot drive, where modules live), CALL it, restore the caller's
; page. CF set = FSV_TX_RES nonzero (saved).
floppysv_run
                ld    hl,floppysv_modname     ; #238: shared PAGE_DATA loader (was an inline copy)
                call  run_data_module
                ld    a,(FSV_TX_RES)
                rra
                ret   nc
                ld    hl,(FSV_TX_LEN)
                ret
floppysv_modname db    "FLOPPYSVMOD"          ; 8.3, space-padded
                endif                          ; IN_GBROM (write stub resident-only)

; --- resident state (load + listing; save state lives in the module) --------
; #152: fixed low RAM in the GEOBENCH.ROM build (FS_RDIO_LOWRAM, in fs_rom_lowram.inc),
; packed right after the core state; the resident/paged builds keep the original `defs`.
                ifndef FS_RDIO_LOWRAM
fslf_blocks     equ   #1490        ; #196: relocated to low RAM (was defs 16); the extent's
                                   ; 16 allocation block numbers, rebuilt per fs_load_file (scratch)
fslf_secs       defb  0            ; sectors left to read
fslf_si         defb  0            ; sector index within the file
fslf_curtrk     defb  0            ; track the head is currently on
fsam_idx        defb  0            ; directory-listing cursor
                endif
; fsam_buf (the 2KB whole-directory buffer) and fs_secbuf are fixed low-RAM equs in
; gbkern.asm (the module agrees on the addresses).
