; ---------------------------------------------------------------------------
; lib/fs.asm - storage backend dispatcher.
;
; GEOBENCH talks to a generic filesystem interface (fs_dir_first/fs_dir_next)
; and never knows which storage it is reading. At startup fs_init probes for the
; SYMBiFACE II / Cyboard IDE and selects a backend:
;   IDE present  -> lib/fs_ide_fat.asm   (FAT16 over IDE, fside_*)
;   otherwise    -> lib/fs_amsdos.asm    (AMSDOS directory over the floppy, fsam_*)
; so the desktop runs on a plain floppy-only CPC as well as an IDE-equipped one.
;
; Interface (filled by whichever backend is active):
;   fs_dir_first -> CF set = first entry ready in fs_ent_*, NC = directory empty
;   fs_dir_next  -> CF set = next entry ready,              NC = end of directory
;   fs_ent_name  11 bytes  (8.3, space padded)
;   fs_ent_attr   1 byte
;   fs_ent_size   4 bytes  (little-endian)
; ---------------------------------------------------------------------------

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
                if STORAGE_M4                  ; #174: M4 board, FILE-LEVEL backend (the M4 firmware
D0_PRESENT      equ   fsm4_present            ; does the FAT, like Albireo's CH376) - lib/fs_m4.asm,
D0_FIRST        equ   fsm4_dir_first          ; no IDE FAT core. Read-only for now: save/delete
D0_NEXT         equ   fsm4_dir_next           ; fall back to the no-op stub (C_WRITE is a later phase).
D0_LOAD         equ   fsm4_load_file
D0_SAVE         equ   fs_load_none
D0_DELETE       equ   fs_load_none
                else
D0_PRESENT      equ   fs_ide_present
D0_FIRST        equ   fside_dir_first
D0_NEXT         equ   fside_dir_next
D0_LOAD         equ   fside_load_file
D0_SAVE         equ   fside_save_file
D0_DELETE       equ   fside_delete_file
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
                ld    hl,fs_load_none          ; delete not implemented on floppy
                ld    (fs_p_delete),hl
                ret
fs_cur_drive    defb  0
fs_boot_drive   defb  0            ; #110: boot drive number; fs_load_sys loads apps/modules
                                   ; from it regardless of a window's browse drive
fls_browse      defb  0            ; fs_load_sys scratch: browse drive to restore

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
; fs_load_sys: like fs_load_file but loads from the BOOT drive (where the OS apps +
; shared modules live) regardless of the active browse drive (#65/#110) - then, if the
; file is NOT on the boot drive, retries on the browse drive (#250). That lets a window
; browsing floppy B run a Companion app off B while its deps still resolve on Main/A.
fs_load_sys
                ld    a,(fs_cur_drive)            ; save the active browse drive
                ld    (fls_browse),a
                ld    a,(fs_boot_drive)           ; load from the boot drive (where the app
                call  fs_set_drive               ; binaries + GBFAT module live), NOT the
                call  fs_sysdir_enter            ; #134: ...and from the /GEOBENCH system dir,
                call  fs_load_file               ; not the FM's browse folder (window's browse
                push  af                          ; drive - #110: a floppy-B window must still
                call  fs_sysdir_leave            ; load apps off floppy A)
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
fs_load_none
                or    a                        ; not implemented -> NC
                ret

; fs_ide_present: ATA register read-back test on the IDE LBA-low port. A real
; controller latches the value; an unconnected expansion bus does not. CF set =
; IDE present.
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

; --- state / shared per-entry output -------------------------------------
fs_p_first      defw  D0_FIRST         ; default drive 0; fs_init rewrites on detect
fs_p_next       defw  D0_NEXT
fs_p_load       defw  D0_LOAD
fs_p_save       defw  D0_SAVE
fs_p_delete     defw  D0_DELETE
fs_ent_name     defs  11
fs_ent_attr     defb  0
fs_ent_size     defs  4
fs_req_name     defs  11           ; fs_load_file/fs_save_file: 8.3 name
fs_load_dst     defw  0            ; fs_load_file: destination buffer
fs_load_max     defw  #FFFF        ; fs_load_file: max bytes to read (buffer guard)
fs_save_src     defw  0            ; fs_save_file: source buffer
fs_save_len     defw  0            ; fs_save_file: bytes to write
