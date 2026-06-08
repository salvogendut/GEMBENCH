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

; fs_init: pick the backend once, before any directory call. Drive 0 is the
; "hard" volume - the Albireo (CH376 USB/SD) if fitted, else the SYMBiFACE IDE;
; fs_drive0_is_alb records which so fs_set_drive routes drive 0 correctly (#104).
fs_init
                xor   a
                ld    (fs_drive0_is_alb),a
                call  fsalb_present              ; Albireo present? -> boot drive 0
                jr    nc,fsi_tryide
                ld    a,1
                ld    (fs_drive0_is_alb),a
                xor   a
                jr    fsi_set
fsi_tryide
                call  fs_ide_present
                ld    a,1                       ; no IDE -> boot drive 1 (floppy A)
                jr    nc,fsi_set
                xor   a                          ; IDE -> boot drive 0 (Disk C)
fsi_set
                call  fs_set_drive               ; select the boot drive, then capture its
                ld    hl,(fs_p_load)             ; loader as fs_sys_load: app binaries/
                ld    (fs_sys_load),hl           ; modules always load from the boot drive,
                ret                               ; regardless of a window's browse drive
                ; (fs_set_drive falls through below for the GB_SETDRIVE path)

; fs_set_drive: A = drive (0 = IDE/Disk C, 1 = floppy A, 2 = floppy B). Point the
; backend vectors at the IDE or floppy routines (floppy: also set the FDC unit) and
; record the current drive. Lets each File Manager window browse its own drive (#65).
fs_set_drive
                ld    (fs_cur_drive),a
                or    a
                jr    nz,fsd_floppy
                ld    a,(fs_drive0_is_alb)      ; drive 0 = Albireo or IDE
                or    a
                jr    nz,fsd_alb
                ld    hl,fside_dir_first        ; drive 0 = IDE
                ld    (fs_p_first),hl
                ld    hl,fside_dir_next
                ld    (fs_p_next),hl
                ld    hl,fside_load_file
                ld    (fs_p_load),hl
                ld    hl,fside_save_file
                ld    (fs_p_save),hl
                ld    hl,fside_delete_file
                ld    (fs_p_delete),hl
                ret
fsd_alb
                ld    hl,fsalb_dir_first        ; drive 0 = Albireo (CH376)
                ld    (fs_p_first),hl
                ld    hl,fsalb_dir_next
                ld    (fs_p_next),hl
                ld    hl,fsalb_load_file
                ld    (fs_p_load),hl
                ld    hl,fsalb_save_file
                ld    (fs_p_save),hl
                ld    hl,fsalb_delete_file
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
fs_drive0_is_alb defb 0            ; #104: 0 = drive 0 is IDE, 1 = Albireo (CH376)
fs_sys_load     defw  fside_load_file ; the boot drive's loader (fs_init captures it)

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
; fs_load_sys: like fs_load_file but always from the BOOT drive (where app binaries
; and the GBFAT module live), regardless of the active browse drive (#65).
fs_load_sys
                ld    hl,(fs_sys_load)
                jp    (hl)
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
                ld    bc,#FD0B
                ld    a,#AA
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
fs_p_first      defw  fside_dir_first   ; default IDE; fs_init rewrites on detect
fs_p_next       defw  fside_dir_next
fs_p_load       defw  fside_load_file
fs_p_save       defw  fside_save_file
fs_p_delete     defw  fside_delete_file
fs_ent_name     defs  11
fs_ent_attr     defb  0
fs_ent_size     defs  4
fs_req_name     defs  11           ; fs_load_file/fs_save_file: 8.3 name
fs_load_dst     defw  0            ; fs_load_file: destination buffer
fs_load_max     defw  #FFFF        ; fs_load_file: max bytes to read (buffer guard)
fs_save_src     defw  0            ; fs_save_file: source buffer
fs_save_len     defw  0            ; fs_save_file: bytes to write
