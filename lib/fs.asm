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

; fs_init: pick the backend once, before any directory call.
fs_init
                call  fs_ide_present
                jr    nc,fsi_floppy
                ld    hl,fside_dir_first
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
fsi_floppy
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
