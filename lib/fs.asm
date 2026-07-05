; ---------------------------------------------------------------------------
; lib/fs.asm - storage backend dispatcher.
;
; GEOBENCH talks to a generic filesystem interface (fs_dir_first/fs_dir_next)
; and never knows which storage it is reading. The drive-0 ("hard") backend is
; picked at BUILD time (STORAGE_ALBIREO -> lib/fs_albireo.asm, STORAGE_M4 ->
; lib/fs_m4.asm, else the archived IDE lib/fs_ide_fat.asm); at boot fs_init
; probes for that card and falls back to the AMSDOS floppy backend
; (lib/fs_amsdos.asm, fsam_*), so the desktop also runs on a floppy-only CPC.
;
; Interface (filled by whichever backend is active):
;   fs_dir_first -> CF set = first entry ready in fs_ent_*, NC = directory empty
;   fs_dir_next  -> CF set = next entry ready,              NC = end of directory
;   fs_ent_name  11 bytes  (8.3, space padded)
;   fs_ent_attr   1 byte
;   fs_ent_size   4 bytes  (little-endian)
; ---------------------------------------------------------------------------

FS_LOAD_OFS     equ   #144C        ; 24-bit chunked-copy read offset
FS_XFLAGS       equ   #144F        ; bit0 = chunk-read, bit1 = append-write, bit2 = chunk-save

; Drive-0 backend entry points, resolved at build time (#104). Drive 0 is the
; "hard" volume: the Albireo CH376 card (STORAGE_ALBIREO=1) or the SYMBiFACE IDE
; (default). The rest of fs.asm is backend-agnostic - it only uses these aliases.
                if STORAGE_ALBIREO
D0_PRESENT      equ   fsalb_present
D0_FIRST        equ   fsalb_dir_first
D0_NEXT         equ   fsalb_dir_next
D0_LOAD         equ   fsalb_load_file
D0_SAVE         equ   fsalb_save_file
D0_DELETE       equ   fsalb_delete_file
                else
                if STORAGE_M4                  ; #174/#259: M4 board, FILE-LEVEL backend (the M4
D0_PRESENT      equ   fsm4_present            ; firmware does FAT, like Albireo's CH376) - lib/fs_m4.asm,
D0_FIRST        equ   fsm4_dir_first          ; no IDE FAT core; firmware handles the card filesystem.
D0_NEXT         equ   fsm4_dir_next
D0_LOAD         equ   fsm4_load_file
D0_SAVE         equ   fsm4_save_file
D0_DELETE       equ   fsm4_delete_file
D0_FREE         equ   fsm4_free_kib
                else
D0_PRESENT      equ   fs_ide_present
D0_FIRST        equ   fside_dir_first
D0_NEXT         equ   fside_dir_next
D0_LOAD         equ   fside_load_file
D0_SAVE         equ   fside_save_file
D0_DELETE       equ   fside_delete_file
D0_FREE         equ   fs_load_none
                endif
                endif

; fs_init: pick the boot drive once, before any directory call. If the drive-0
; card is present boot from it (Disk C), else fall back to floppy A.
fs_init
                call  D0_PRESENT
                ld    a,1                       ; card absent -> boot drive 1 (floppy A)
                jr    nc,fsi_set
                xor   a                          ; card present -> boot drive 0 (Disk C)
fsi_set
                ld    (fs_boot_drive),a           ; remember the boot drive NUMBER: app
                                                 ; binaries + modules always load from it
                                                 ; (fs_load_sys), regardless of a window's
                                                 ; browse drive (#65/#110). A is still the
                ; drive number -> fall straight through into fs_set_drive (saves a call+ret).

; fs_set_drive: A = drive (0 = IDE/Disk C, 1 = floppy A, 2 = floppy B). Point the
; backend vectors at the IDE or floppy routines (floppy: also set the FDC unit) and
; record the current drive. Lets each File Manager window browse its own drive (#65).
fs_set_drive
                ld    (fs_cur_drive),a
                or    a
                jr    nz,fsd_floppy
                ld    hl,D0_FIRST              ; drive 0 = the build's hard backend
                ld    (fs_p_first),hl
                ld    hl,D0_NEXT
                ld    (fs_p_next),hl
                ld    hl,D0_LOAD
                ld    (fs_p_load),hl
                ld    hl,D0_SAVE
                ld    (fs_p_save),hl
                ld    hl,D0_DELETE
                ld    (fs_p_delete),hl
                ret
fsd_floppy
                dec   a                          ; drive 1->unit 0, drive 2->unit 1
                ld    (fsam_unit),a
                ld    hl,fsam_dir_first
                ld    (fs_p_first),hl
                ld    hl,fsam_dir_next
                ld    (fs_p_next),hl
                ld    hl,fsam_load_file
                ld    (fs_p_load),hl
                ld    hl,fsam_save_file
                ld    (fs_p_save),hl
                ld    hl,fsam_delete_file
                ld    (fs_p_delete),hl
                ret
fs_cur_drive    equ   #1335
fs_boot_drive   equ   #1336        ; #110: boot drive number; fs_load_sys loads apps/modules
                                   ; from it regardless of a window's browse drive
fls_browse      equ   #1337        ; fs_load_sys scratch: browse drive to restore

; fs_dir_first / fs_dir_next / fs_load_file: route to the selected backend.
fs_dir_first
                ld    hl,(fs_p_first)
                jp    (hl)
fs_dir_next
                ld    hl,(fs_p_next)
                jp    (hl)
; fs_load_file: load file (fs_req_name) into (fs_load_dst). CF set = loaded.
fs_load_file
                ld    hl,(fs_p_load)
                jp    (hl)
; fs_load_cur_sys: load fs_req_name from the CURRENT drive's system directory,
; preserving the current directory and returning fs_load_file's CF.
fs_load_cur_sys
                call  fs_sysdir_enter
                call  fs_load_file
                push  af
                call  fs_sysdir_leave
                pop   af
                ret
; fs_load_sys: like fs_load_file but loads from the BOOT drive (where the OS apps +
; shared modules live) regardless of the active browse drive (#65/#110) - then, if the
; file is NOT on the boot drive, retries on the browse drive (#250). That lets a window
; browsing floppy B run a Companion app off B while its deps still resolve on Main/A.
fs_load_sys
                ld    a,(fs_cur_drive)            ; save the active browse drive
                ld    (fls_browse),a
                ld    a,(fs_boot_drive)           ; load from the boot drive (where the app
                call  fs_set_drive               ; binaries + GBFAT module live), NOT the
                call  fs_load_cur_sys            ; #134: ...and from the /GEOBENCH system dir,
                push  af                          ; not the FM's browse folder (window's browse
                ld    a,(fls_browse)             ; (CF result preserved across the restores)
                call  fs_set_drive               ; restore the browse drive
                pop   af
                ret   c                          ; #250: loaded from the boot drive -> done; else
                jp    fs_load_file               ; retry on the (now-current) browse drive so a
                                                 ; Companion app in floppy B loads (boot-first,
                                                 ; browse-fallback). Floppy sysdir is a no-op, and
                                                 ; reusing the restore above = +3 resident bytes.
; fs_save_file: save fs_save_len bytes from (fs_save_src) to fs_req_name. The
; AMSDOS backend creates the file if absent and allocates/frees 1KB blocks as the
; size changes (single extent, <=16KB). CF set = saved, NC = failed (disk/dir
; full, too big, or - FAT16 - not yet implemented).
fs_save_file
                ld    hl,(fs_p_save)
                jp    (hl)
; fs_delete_file: delete the file named fs_req_name from the current directory.
; CF set = deleted, NC = failed/unsupported. (#62 drag-to-Trash)
fs_delete_file
                ld    hl,(fs_p_delete)
                jp    (hl)
; fs_free_kib: return free space on the current drive. HL = KiB, CF set if known.
; Drive 0 can use its native card/backend query. Floppies use the paged FLOPPYSV
; helper so the AMSDOS block scan does not live resident.
fs_free_kib
                if STORAGE_ALBIREO
                ld    hl,#FFFE
                ld    a,(fsam_unit)           ; harmless for the Albireo #FFFD path
                ld    (#170F),a               ; FSV_TX_UNIT
                ld    a,(fs_cur_drive)
                or    a
                jr    nz,fsfk_go
                dec   l                       ; #FFFE -> #FFFD (Albireo free op)
fsfk_go
                jp    fsam_free_mod_op
                else
                ld    a,(fs_cur_drive)
                or    a
                jp    z,D0_FREE
                ld    hl,#FFFE
                ld    a,(fsam_unit)           ; which floppy unit (0=A,1=B)
                ld    (#170F),a               ; FSV_TX_UNIT
                jp    fsam_free_mod_op
                endif
                if !STORAGE_ALBIREO & !STORAGE_M4
fs_load_none
                or    a                        ; not implemented -> NC
                ret
                endif

                if !STORAGE_ALBIREO & !STORAGE_M4
; fs_ide_present: ATA register read-back test on the IDE LBA-low port. A real
; controller latches the value; an unconnected expansion bus does not. CF set =
; IDE present. Only the archived IDE backend calls this; Albireo/M4 builds keep
; it out of resident space (#268).
fs_ide_present
                ld    bc,#FD0B
                ld    a,#55
                out   (c),a
                in    a,(c)
                cp    #55
                jr    nz,fsip_absent
                ld    a,#AA                       ; (BC still #FD0B from the first probe)
                out   (c),a
                in    a,(c)
                cp    #AA
                jr    nz,fsip_absent
                scf
                ret
fsip_absent
                or    a
                ret
                endif

; --- fixed low-RAM state / shared per-entry output -----------------------
; These are runtime cells, not initialized image data. fs_init/fs_set_drive fills
; the dispatch vectors before first use; every caller sets request/load/save args.
fs_p_first      equ   #14D2        ; dispatch vectors for the selected backend
fs_p_next       equ   #14D4
fs_p_load       equ   #14D6
fs_p_save       equ   #14D8
fs_p_delete     equ   #14DA
fs_ent_name     equ   #14DC        ; current dir entry: 11-byte 8.3 name
fs_ent_attr     equ   #14E7
fs_ent_size     equ   #14E8        ; 32-bit little-endian byte size
fs_req_name     equ   #14EC        ; fs_load_file/fs_save_file: 8.3 name
fs_load_dst     equ   #14F7        ; fs_load_file: destination buffer
fs_load_max     equ   #14F9        ; fs_load_file: max bytes to read (buffer guard)
fs_save_src     equ   #14FB        ; fs_save_file: source buffer
fs_save_len     equ   #14FD        ; fs_save_file: bytes to write
