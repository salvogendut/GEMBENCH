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
                ret
fsi_floppy
                ld    hl,fsam_dir_first
                ld    (fs_p_first),hl
                ld    hl,fsam_dir_next
                ld    (fs_p_next),hl
                ret

; fs_dir_first / fs_dir_next: route to the selected backend.
fs_dir_first
                ld    hl,(fs_p_first)
                jp    (hl)
fs_dir_next
                ld    hl,(fs_p_next)
                jp    (hl)

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
fs_ent_name     defs  11
fs_ent_attr     defb  0
fs_ent_size     defs  4
