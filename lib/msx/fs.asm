; ---------------------------------------------------------------------------
; lib/msx/fs.asm - MSX-DOS 2 / Nextor storage backend for the MSX2 target (#287).
;
; Replaces the whole CPC storage stack (dispatcher + card/floppy backends):
; the DOS already owns the disk, so every operation is a BDOS call. The
; interface is the same one lib/fs.asm exposed - fs_init / fs_set_drive /
; fs_dir_first / fs_dir_next / fs_load_file / fs_load_cur_sys / fs_load_sys /
; fs_save_file / fs_delete_file / fs_free_kib / fs_sysdir_enter / fs_sysdir_
; leave / fs_sys_resolve + fsmx_chdir / fsmx_back for GB_CHDIR/GB_BACK - and
; the same fs_ent_* / fs_req_name / fs_load_* low-RAM cells.
;
; Directory enumeration maps _FFIRST/_FNEXT FIBs into fs_ent_* (the FIB
; carries name/attr/size straight from the FAT entry). Loads open a handle,
; read up to fs_load_max, and probe one extra byte to detect too-big files.
; M1 scope: read-only (save/delete/free are M2 - they return NC for now).
;
; Notes:
;  - BDOS may be entered with a mapped app segment in page 1: switching only
;    ever goes through PUT_P1, so DOS's page-1 shadow stays coherent and its
;    own restore logic works (the M0 spike proved the map + r/w path).
;  - BDOS calls run with interrupts enabled (an `ei` up front): callers wrap
;    fs ops in DI/EI for the CPC's banking, but the DOS drivers need IRQs.
;  - System files live in \GEOBENCH on the boot drive, entered per-load with
;    _CHDIR and restored with the saved _GETCD path - same semantics as the
;    CPC's fs_sysdir_enter/leave.
; ---------------------------------------------------------------------------

FS_ATTR_DIRS    equ   #10          ; _FFIRST search attributes: include directories

; fs_init: single-drive model for M1 - the DOS current drive is the world.
fs_init
                xor   a
                ld    (fs_boot_drive),a
                ld    (fs_cur_drive),a
                ret

; fs_set_drive: A = drive. Recorded only (drive letters arrive with M2+).
fs_set_drive
                ld    (fs_cur_drive),a
                ret

; fs_sys_resolve: nothing to pre-resolve - fs_sysdir_enter chdirs per call.
fs_sys_resolve
                ret

; fs_sysdir_enter: save the CWD, then _CHDIR into \GEOBENCH. A missing system
; dir leaves the CWD unchanged (loads then resolve against the current dir,
; the same flat-root fallback the CPC card backend has).
fs_sysdir_enter
                ei
                push  ix
                ld    c,_GETCD
                ld    b,0                     ; current drive
                ld    de,fsmx_cwd
                call  BDOS
                ld    c,_CHDIR
                ld    de,fsmx_sysdir
                call  BDOS
                pop   ix
                ret

; fs_sysdir_leave: _CHDIR back to the saved CWD (root-relative path).
fs_sysdir_leave
                ei
                push  ix
                ld    a,(fsmx_cwd)           ; empty string = root
                or    a
                jr    nz,fsl_go
                ld    de,fsmx_root
                jr    fsl_cd
fsl_go
                ld    de,fsmx_cwdsl          ; "\" + saved path
fsl_cd
                ld    c,_CHDIR
                call  BDOS
                pop   ix
                ret

; --- directory enumeration ---------------------------------------------------
; fs_dir_first / fs_dir_next -> CF set = entry ready in fs_ent_*, NC = done.
fs_dir_first
                ei
                push  ix
                ld    c,_FFIRST
                ld    de,fsmx_star           ; "*" in the current directory
                ld    b,FS_ATTR_DIRS
                ld    ix,fsmx_fib
                call  BDOS
                pop   ix
                or    a
                jr    z,fsd_fill
                or    a                       ; error -> NC
                ret
fs_dir_next
                ei
                push  ix
                ld    c,_FNEXT
                ld    ix,fsmx_fib
                call  BDOS
                pop   ix
                or    a
                jr    z,fsd_fill
                or    a
                ret

; fsd_fill: FIB -> fs_ent_name (11-byte padded 8.3), fs_ent_attr, fs_ent_size.
fsd_fill
                ld    hl,fs_ent_name         ; blank the 11-byte name
                ld    de,fs_ent_name+1
                ld    bc,10
                ld    (hl),' '
                ldir
                ld    hl,fsmx_fib+FIB_NAME   ; "NAME.EXT",0 -> padded 8.3
                ld    de,fs_ent_name
                ld    b,8
fsdf_name
                ld    a,(hl)
                or    a
                jr    z,fsdf_done
                cp    '.'
                jr    z,fsdf_dot
                ld    (de),a
                inc   hl
                inc   de
                djnz  fsdf_name
                ld    a,(hl)                  ; 8 name chars used: next is '.' or NUL
                cp    '.'
                jr    nz,fsdf_done
fsdf_dot
                inc   hl                       ; skip the '.'
                ld    de,fs_ent_name+8
                ld    b,3
fsdf_ext
                ld    a,(hl)
                or    a
                jr    z,fsdf_done
                ld    (de),a
                inc   hl
                inc   de
                djnz  fsdf_ext
fsdf_done
                ld    a,(fsmx_fib+FIB_ATTR)
                ld    (fs_ent_attr),a
                ld    hl,(fsmx_fib+FIB_SIZE)
                ld    (fs_ent_size),hl
                ld    hl,(fsmx_fib+FIB_SIZE+2)
                ld    (fs_ent_size+2),hl
                scf
                ret

; --- load ---------------------------------------------------------------------
; fs_load_file: load fs_req_name (11-byte 8.3) into (fs_load_dst), capped at
; (fs_load_max). CF set = loaded, fs_ent_size = byte count. NC = missing or
; too big for the buffer (CPC contract).
fs_load_file
                ei
                push  ix
                call  fsmx_name_to_path      ; fs_req_name -> fsmx_path ASCIIZ
                ld    c,_DOPEN
                ld    de,fsmx_path
                ld    a,1                     ; open mode: no write
                call  BDOS
                or    a
                jr    nz,fsload_miss
                ld    a,b
                ld    (fsmx_handle),a
                ld    c,_READ
                ld    de,(fs_load_dst)
                ld    hl,(fs_load_max)
                call  BDOS
                ld    (fs_ent_size),hl       ; byte count (max 16K -> low word)
                ld    hl,0
                ld    (fs_ent_size+2),hl
                ld    a,(fsmx_handle)        ; probe: 1 more byte readable = too big
                ld    b,a
                ld    c,_READ
                ld    de,fsmx_probe
                ld    hl,1
                call  BDOS
                ld    a,h
                or    l
                jr    nz,fsload_toobig
                ld    a,(fsmx_handle)
                ld    b,a
                ld    c,_DCLOSE
                call  BDOS
                pop   ix
                scf
                ret
fsload_toobig
                ld    a,(fsmx_handle)
                ld    b,a
                ld    c,_DCLOSE
                call  BDOS
fsload_miss
                pop   ix
                or    a
                ret

; fs_load_cur_sys / fs_load_sys: system-dir load, CPC semantics. One drive on
; M1, so both are enter -> load -> leave.
fs_load_cur_sys
fs_load_sys
                call  fs_sysdir_enter
                call  fs_load_file
                push  af
                call  fs_sysdir_leave
                pop   af
                ret

; --- write ops: M2 ------------------------------------------------------------
fs_save_file
fs_delete_file
fs_free_kib
                or    a                       ; not implemented yet -> NC
                ret

; --- GB_CHDIR / GB_BACK --------------------------------------------------------
; fsmx_chdir: descend into the positioned entry (fs_ent_name).
fsmx_chdir
                ei
                push  ix
                ld    hl,fs_ent_name
                ld    de,fsmx_path
                call  fsmx_n2p_copy
                ld    c,_CHDIR
                ld    de,fsmx_path
                call  BDOS
                pop   ix
                ret

; fsmx_back: up one level.
fsmx_back
                ei
                push  ix
                ld    c,_CHDIR
                ld    de,fsmx_dotdot
                call  BDOS
                pop   ix
                ret

; --- name conversion ------------------------------------------------------------
; fsmx_name_to_path: fs_req_name (11 bytes, space padded) -> fsmx_path ASCIIZ.
fsmx_name_to_path
                ld    hl,fs_req_name
                ld    de,fsmx_path
fsmx_n2p_copy                                  ; HL = 11-byte name, DE = dst ASCIIZ
                ld    b,8
fnp_name
                ld    a,(hl)
                cp    ' '
                jr    z,fnp_nskip
                ld    (de),a
                inc   de
fnp_nskip
                inc   hl
                djnz  fnp_name
                ld    a,(hl)                  ; any extension?
                cp    ' '
                jr    z,fnp_term
                ld    a,'.'
                ld    (de),a
                inc   de
                ld    b,3
fnp_ext
                ld    a,(hl)
                cp    ' '
                jr    z,fnp_term
                ld    (de),a
                inc   de
                inc   hl
                djnz  fnp_ext
fnp_term
                xor   a
                ld    (de),a
                ret

; --- state ------------------------------------------------------------------------
fsmx_star       db    "*",0
fsmx_sysdir     db    92,"GBENCH",0           ; "\GBENCH" (the staged system folder)
fsmx_root       db    92,0                    ; "\" (root)
fsmx_dotdot     db    "..",0
fsmx_handle     db    0
fsmx_probe      db    0
fsmx_cwdsl      db    92                      ; "\" prefix, falls into the CWD buffer
fsmx_cwd        ds    64                      ; _GETCD result (no leading slash)
fsmx_path       ds    16                      ; "FILENAME.EXT",0
fsmx_fib        ds    64                      ; the _FFIRST/_FNEXT fileinfo block
fs_dir_clus     ds    4                       ; dummy: k_copy_begin/end context swap

; fixed low-RAM cells: the same contract addresses as the CPC dispatcher
fs_cur_drive    equ   #1335
fs_boot_drive   equ   #1336
fls_browse      equ   #1337
fs_ent_name     equ   #14DC
fs_ent_attr     equ   #14E7
fs_ent_size     equ   #14E8
fs_req_name     equ   #14EC
fs_load_dst     equ   #14F7
fs_load_max     equ   #14F9
fs_save_src     equ   #14FB
fs_save_len     equ   #14FD
