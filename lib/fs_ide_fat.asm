; ---------------------------------------------------------------------------
; lib/fs_ide_fat.asm - storage backend: FAT32 over the SYMBiFACE II / Cyboard
; IDE interface. Reads the volume straight off the IDE controller. Selected by
; lib/fs.asm when an IDE is present.
;
; This file is the RESIDENT half: the FAT32 *read* path (directory walk + file
; load) plus the shared core (lib/fs_fat32_core.asm). The *write* path is large
; and only needed on a save, so it lives in a paged module (kernel/modules/
; gbfat.asm) loaded on demand; fside_save_file is a thin stub that marshals the
; inputs into low RAM and calls it.
;
; Backend entry points (the floppy backend exposes matching fsam_* names so the
; dispatcher in lib/fs.asm can route to either):
;   fside_dir_first -> CF set = first entry ready in fs_ent_*, NC = empty
;   fside_dir_next  -> CF set = next entry ready,              NC = end of dir
;   fside_load_file -> CF set = loaded (fs_ent_size bytes),    NC = not found
;   fside_save_file -> CF set = saved (create or overwrite),   NC = failed
; Per-entry output fields fs_ent_name/attr/size live in lib/fs.asm (shared).
;
; IDE port map (from 1984 src/ide.c; port = &FD00 | reg):
;   &FD0A scnt  &FD0B lbaL  &FD0C lbaM  &FD0D lbaH  &FD0E dev  &FD0F cmd/status
;   &FD08 data (1 byte per IN).  READ SECTORS = &20, status: 7=BSY 3=DRQ 0=ERR.
; ---------------------------------------------------------------------------

FS_IDE_SCNT     equ   #FD0A
FS_IDE_LBAL     equ   #FD0B
FS_IDE_LBAM     equ   #FD0C
FS_IDE_LBAH     equ   #FD0D
FS_IDE_DEV      equ   #FD0E
FS_IDE_CMD      equ   #FD0F
FS_IDE_STAT     equ   #FD0F
FS_IDE_DATA     equ   #FD08

; Paged FAT32 write module (kernel/modules/gbfat.asm). The resident stub marshals
; the save into this low-RAM transfer area (reachable while the module is paged
; into the #4000-#7FFF window), loads the module to GBFAT_LOAD, and CALLs it.
GBFAT_LEN       equ   #1400        ; bytes to write (word)
GBFAT_NAME      equ   #1402        ; 8.3 name (11 bytes)
GBFAT_RES       equ   #140D        ; result: 1 = saved, 0 = failed
GBFAT_OP        equ   #140E        ; operation: 0 = save, 1 = delete (#62)
GBFAT_DIR       equ   #140F        ; directory cluster (4 bytes) to operate in
GBFAT_DATA      equ   #2200        ; staged data (<= GBFAT_MAX bytes)
GBFAT_MAX       equ   #1C00        ; 7 KB staging cap (fits #2200..#3DFF in low RAM)
GBFAT_LOAD      equ   DATA_MODTOP  ; module load address, above the font+icon set in
                                   ; PAGE_DATA (must match GBFAT_ORG in gbfat.asm; #88)

                ifndef GB_ROM_STUBS          ; #152: the GB_ROM resident build uses the ROM's core
                include "fs_fat32_core.asm"  ; (via gbfat.asm) + the #1C00 state in fs_fat_lowram.inc
                endif

                ifndef GB_ROM_STUBS          ; non-ROM resident: the real read backend
                include "fs_ide_read.asm"
                else                          ; #152 GB_ROM resident: fside_* run from GEOBENCH.ROM
; (idx 6-8). Page the ROM in, call the slot, and marshal the I/O transfer area (#1270)
; <-> the resident fs_ent_*/fs_req_name/fs_load_*. gb_rom_fsam_invoke is in fs_amsdos.asm.
fside_dir_first ld    hl,#C018               ; ROM idx6
                call  gb_rom_fsam_invoke
                jr    fside_ent_out
fside_dir_next  ld    hl,#C01B               ; ROM idx7
                call  gb_rom_fsam_invoke
                jr    fside_ent_out
fside_load_file ld    hl,fs_req_name          ; marshal inputs into the transfer area
                ld    de,FSAM_IO_REQ
                ld    bc,11
                ldir
                ld    hl,(fs_load_dst)
                ld    (FSAM_IO_DST),hl
                ld    hl,(fs_load_max)
                ld    (FSAM_IO_MAX),hl
                ld    hl,#C01E               ; ROM idx8 (writes the file into (fs_load_dst))
                call  gb_rom_fsam_invoke
                push  af                       ; preserve CF (loaded?)
                ld    hl,FSAM_IO_SIZE         ; copy the loaded size back out
                ld    de,fs_ent_size
                ld    bc,4
                ldir
                pop   af
                ret
; fside_ent_out: copy the entry the ROM wrote (name+attr+size, 16 contiguous; then the
; start cluster) out of the transfer area into the resident fs_ent_*. Preserves the CF.
fside_ent_out   push  af
                ld    hl,FSAM_IO_NAME
                ld    de,fs_ent_name
                ld    bc,16
                ldir
                ld    hl,FSAM_IO_CLUS
                ld    de,fs_ent_clus
                ld    bc,4
                ldir
                pop   af
                ret
flf_cmpname                                    ; resident copy - fs_sys_resolve uses it (the ROM
                ld    hl,fs_ent_name           ; has its own copy for the ROM's fside_load_file)
                ld    de,fs_req_name
                ld    b,11
flf_cn          ld    a,(de)
                cp    (hl)
                ret   nz
                inc   hl
                inc   de
                djnz  flf_cn
                xor   a
                ret
copy4                                          ; resident copy - fs_sys_resolve/fs_sysdir_* use it
                ld    bc,4                      ; (lived in fs_fat32_core, now ROM-only)
                ldir
                ret
                endif

; ---------------------------------------------------------------------------
; fs_sys_resolve (#134): point fs_sys_clus at the /GEOBENCH folder so system files
; load from there. Run once at boot after the mount, while fs_dir_clus is the root.
; If there's no GEOBENCH subdir (flat card), fs_sys_clus stays the root.
fs_sys_resolve
                ld    hl,fs_dir_clus            ; default: system dir = root (flat layout)
                ld    de,fs_sys_clus
                call  copy4
                ld    hl,sys_dirname            ; look for a "GEOBENCH" directory in the root
                ld    de,fs_req_name
                ld    bc,11
                ldir
                call  fside_dir_first
fsr_loop        jr    nc,fsr_done
                ld    a,(fs_ent_attr)
                and   #10                        ; directory entry?
                jr    z,fsr_next
                call  flf_cmpname                ; named GEOBENCH?
                jr    nz,fsr_next
                ld    hl,fs_ent_clus            ; yes -> system dir = its start cluster
                ld    de,fs_sys_clus
                call  copy4
                ret
fsr_next        call  fside_dir_next
                jr    fsr_loop
fsr_done        ret
sys_dirname     db    "GEOBENCH   "

; fs_sysdir_enter / fs_sysdir_leave (#134): briefly make the FAT dir the /GEOBENCH
; system dir for one system load, then restore the File Manager's browse dir.
fs_sysdir_enter
                ld    hl,fs_dir_clus
                ld    de,fs_dir_save
                call  copy4
                ld    hl,fs_sys_clus
                ld    de,fs_dir_clus
                call  copy4
                ret
fs_sysdir_leave
                ld    hl,fs_dir_save
                ld    de,fs_dir_clus
                call  copy4
                ret

; ---------------------------------------------------------------------------
; fside_save_file: stub. Marshal the name/data/len into the low-RAM transfer area
; (the caller's page is still mapped, so the data is read directly here), then
; page in PAGE_DATA, load the GBFAT.BIN write module to GBFAT_LOAD via the read
; path, and CALL it. CF set = saved. Files larger than GBFAT_MAX are refused.
fside_save_file
                ld    hl,(fs_save_len)        ; refuse > GBFAT_MAX (staging buffer)
                ld    de,GBFAT_MAX
                or    a
                sbc   hl,de
                jr    nc,fsvm_fail
                ld    hl,(fs_save_src)        ; copy the data out of the caller's page
                ld    de,GBFAT_DATA           ; into low RAM (caller's page mapped now)
                ld    bc,(fs_save_len)
                ld    a,b
                or    c
                jr    z,fsvm_nlen
                ldir
fsvm_nlen
                ld    hl,fs_req_name          ; name + length -> the transfer area
                ld    de,GBFAT_NAME
                ld    bc,11
                ldir
                ld    hl,fs_dir_clus          ; current browse dir -> the module, so the
                ld    de,GBFAT_DIR            ; save lands here, not in root (#142)
                ld    bc,4
                ldir
                ld    hl,(fs_save_len)
                ld    (GBFAT_LEN),hl
                xor   a                        ; op = save
                ld    (GBFAT_OP),a
                jp    gbfat_run               ; page in + load + run the module
fsvm_fail
                or    a
                ret

; gbfat_run: the transfer area is already filled (name/op + per-op fields). Page in
; PAGE_DATA, load GBFAT.BIN to GBFAT_LOAD via the read path, CALL it, restore the
; caller's page. CF set = GBFAT_RES nonzero (success). Shared by save + delete.
gbfat_run
                ifdef GB_ROM                  ; #152: run the write module straight from GEOBENCH.ROM
                ld    a,(gb_rom_num)          ; (no GBFAT.BIN load, no PAGE_DATA) when the ROM is present
                inc   a
                jr    z,gbfat_run_paged       ; 0xFF = ROM absent -> paged-module fallback
                call  gb_rom_call_write       ; gbfat_entry @ #C009; transfer area already filled
                ld    a,(GBFAT_RES)
                or    a
                ret   z
                scf
                ret
                endif
gbfat_run_paged
                ld    a,(bank_cur)
                push  af
                ld    a,PAGE_DATA
                call  bank_set
                ld    hl,gbfat_modname        ; fs_req_name = "GBFAT   BIN"
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    hl,#2000
                ld    (fs_load_max),hl
                ld    hl,GBFAT_LOAD
                ld    (fs_load_dst),hl
                call  fs_load_sys            ; load GBFAT.BIN -> #5000 (from the boot
                jr    nc,gr_unload            ; drive, where modules live)
                call  GBFAT_LOAD             ; run it (reads low RAM, writes the IDE)
gr_unload
                pop   af
                call  bank_set
                ld    a,(GBFAT_RES)         ; result byte -> CF
                or    a
                ret   z
                scf
                ret

; fside_delete_file: delete the file named fs_req_name from the current directory
; (fs_dir_clus) - free its clusters and clear its dir entry, via the GBFAT module
; (op = delete). CF set = deleted. Used by drag-to-Trash (#62).
fside_delete_file
                ld    hl,fs_req_name          ; name + current dir -> the transfer area
                ld    de,GBFAT_NAME
                ld    bc,11
                ldir
                ld    hl,fs_dir_clus
                ld    de,GBFAT_DIR
                call  copy4
                ld    a,1
                ld    (GBFAT_OP),a            ; op = delete
                jp    gbfat_run               ; page in + load + run the module
gbfat_modname   db    "GBFAT   BIN"          ; 8.3, space-padded

; --- read-path state (shared core state lives in fs_fat32_core.asm) -------
; #152: fs_mounted + flf_* are ROM-only (only the read backend touches them); in the
; FS_STATE_LOWRAM build they live in fs_fat_lowram.inc. fs_dir_sp/fs_dir_stack/
; fs_ent_clus/fs_sys_clus/fs_dir_save stay resident (navigation + system-dir + the
; stub copies fs_ent_clus out of the transfer area).
                ifndef FS_STATE_LOWRAM
fs_mounted      defb  0            ; 0 until the volume is mounted once (#54)
flf_clus        defs  4            ; load: current file cluster
flf_sic         defb  0            ; load: sector within current cluster
flf_secs        defw  0            ; load: sectors remaining
                endif
fs_dir_sp       defb  0            ; directory stack depth (chdir/back)
fs_dir_stack    defs  16           ; 4 parent clusters (4 bytes each)
fs_ent_clus     defs  4            ; selected entry's start cluster
fs_sys_clus     defs  4            ; #134: the /GEOBENCH system dir cluster (root if absent)
fs_dir_save     defs  4            ; #134: browse dir saved across a system load

                ifdef GB_ROM
; ---------------------------------------------------------------------------
; GEOBENCH.ROM seam (#152): probe for the offloaded driver ROM at boot and route
; fs_read_sector through it. The "GBROM" signature sits at ROM #C003. Built with
; -DGB_ROM=1; the paged gbfat.asm write module is built WITHOUT it, so its copy of
; fs_read_sector stays in-RAM.
; ---------------------------------------------------------------------------
; gb_rom_num + gb_rom_probe moved to lib/fs_rom_seam.asm (shared by all backends, #152)

; gb_rom_call: read one sector via GEOBENCH.ROM (#C000, index 0). The kernel has
; staged lba_tmp (#1250); on return fs_secbuf (#1800) holds the sector.
; gb_rom_call_write: run the FAT write module (#C009, index 1) from the ROM - the
; transfer area (GBFAT_*) is already filled; GBFAT_RES holds the result on return.
; Both share gb_rom_invoke: DI across the whole paged-in window (no IRQ sees
; GEOBENCH.ROM at #C000), select the ROM, page it in with #7F85 (upper ROM ON +
; lower ROM OFF - CRUCIAL #152: #7F81 also paged the firmware LOWER ROM over
; #0000-#3FFF and the read fetched a garbage lba_tmp -> reboot), restore AMSDOS.
gb_rom_call
                di                            ; no IRQ may see GEOBENCH.ROM paged in at #C000
                ld    bc,#DF00
                ld    a,(gb_rom_num)
                out   (c),a                  ; select GEOBENCH.ROM
                ld    bc,#7F85               ; upper ROM ON + lower ROM OFF (low RAM visible), mode 1
                out   (c),c
                call  #C000                  ; index 0: read one sector
                ld    bc,#DF00
                ld    a,7
                out   (c),a                  ; restore AMSDOS
                ei
                ret
gb_rom_call_write
                di
                ld    bc,#DF00
                ld    a,(gb_rom_num)
                out   (c),a                  ; select GEOBENCH.ROM
                ld    bc,#7F85
                out   (c),c
                call  #C009                  ; index 1: FAT write (save/delete)
                ld    bc,#DF00
                ld    a,7
                out   (c),a                  ; restore AMSDOS
                ei
                ret
                endif
