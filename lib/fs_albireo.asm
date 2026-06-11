; ---------------------------------------------------------------------------
; lib/fs_albireo.asm - storage backend: FAT over the Albireo (CH376 USB/SD).
;
; SPIKE (#104): proves GEOBENCH can read its disk through the Albireo card
; instead of the SYMBiFACE IDE. The Albireo is a WCH CH376 chip that owns the
; filesystem in firmware - we do NOT parse FAT here (contrast fs_ide_fat.asm).
; We issue high-level file commands and the chip walks the directory / file.
;
; Two 8-bit ports, addressed with 16-bit OUT (C)/IN A,(C) so A8-A15 = #FE:
;   #FE81  w COMMAND / r STATUS (bit7 = !INT: 0 = interrupt pending)
;   #FE80  r/w DATA   (command parameters + response payload)
; The cmd port is the data port | 1, so "send command then DATA follows" is
; just OUT cmd / DEC C (see alb_sendcmd).
;
; Backend entry points (same shape as fside_*/fsam_* so lib/fs.asm routes here):
;   fsalb_dir_first -> CF set = first entry ready in fs_ent_*, NC = empty
;   fsalb_dir_next  -> CF set = next entry ready,              NC = end of dir
;   fsalb_load_file -> CF set = loaded (fs_ent_size = bytes read), NC = absent
;   fsalb_save_file / fsalb_delete_file -> NC (not in this spike)
;
; CH376 dir entries arrive as the raw 32-byte FAT record (name[11], attr@0x0B,
; size@0x1C) - the same layout fs_ide_fat.asm decodes, so fs_ent_* fills the
; same way and the File Manager is none the wiser.
;
; The INI/OUTI idioms below use `ini:inc b` / `inc b:outi`: OUTI decrements B
; *before* the bus cycle and INI *after*, so during the actual I/O B = #FE and
; the chip is addressed correctly; the inc keeps the port high byte stable
; across the loop (A holds the count, not B).
; ---------------------------------------------------------------------------

ALB_CMD         equ   #FE81        ; command (w) / status (r)
ALB_DAT         equ   #FE80        ; data (r/w)

; CH376 command codes (subset)
ALBC_CHECK      equ   #06
ALBC_USBMODE    equ   #15
ALBC_GETSTAT    equ   #22
ALBC_RDDATA0    equ   #27
ALBC_WRREQ      equ   #2D          ; WR_REQ_DATA (chip asks how many bytes to take)
ALBC_SETNAME    equ   #2F
ALBC_DISKMOUNT  equ   #31
ALBC_FILEOPEN   equ   #32
ALBC_ENUMGO     equ   #33
ALBC_FILECREATE equ   #34
ALBC_FILEERASE  equ   #35
ALBC_FILECLOSE  equ   #36
ALBC_BYTEREAD   equ   #3A
ALBC_BYTERDGO   equ   #3B
ALBC_BYTEWRITE  equ   #3C
ALBC_BYTEWRGO   equ   #3D

; CH376 status / return codes
ALB_RET_SUCCESS equ   #51          ; SET_USB_MODE ack on the DATA port
ALB_INT_SUCCESS equ   #14
ALB_INT_DISKRD  equ   #1D
ALB_INT_DISKWR  equ   #1E
ALB_USBMODE_SD  equ   3            ; host mode, micro-SD (LLM_MicroSD)
ALB_USBMODE_USB equ   6            ; #132: host mode, USB + reset the USB bus (for UMS drives)

; ---------------------------------------------------------------------------
; alb_sendcmd: A = command byte. Writes it to the command port and leaves
; BC = DATA port so the caller can stream parameters with OUT (C)/IN A,(C).
alb_sendcmd
                ld    bc,ALB_CMD
                out   (c),a
                dec   c                        ; BC -> ALB_DAT
                ret

; alb_waitint: spin on the STATUS port until the chip raises its interrupt,
; then GET_STATUS to read and clear it. Returns A = interrupt status code.
alb_waitint
                push  de
                ld    de,0                      ; 65536 spins; the per-spin delay below makes
awi_loop                                        ; that ~3s (#132 - matches UniDOS WaitInterrupt)
                ld    bc,ALB_CMD
                in    a,(c)                     ; STATUS: bit7 = !INT
                rla                              ; bit7 -> CF (1 = no interrupt)
                jr    nc,awi_got
                ex    (sp),hl                  ; #132: pace the poll (~38us/spin) so the timeout
                ex    (sp),hl                  ; is seconds, not ~0.5s. The real CH376 needs that
                ex    (sp),hl                  ; long for DISK_MOUNT / USB enumeration; without it
                ex    (sp),hl                  ; we time out early and trust a premature status,
                ex    (sp),hl                  ; whose garbage byte-count overruns a read buffer ->
                ex    (sp),hl                  ; reboot on real HW (the emulator answers instantly,
                ex    (sp),hl                  ; so it never surfaced). 8 swaps = HL/stack restored.
                ex    (sp),hl
                dec   de
                ld    a,d
                or    e
                jr    nz,awi_loop
awi_got
                pop   de
                ld    a,ALBC_GETSTAT
                out   (c),a                     ; BC still = ALB_CMD here
                dec   c
                in    a,(c)                     ; status code from DATA port
                ret

; fsalb_present: probe the chip. CHECK_EXIST echoes ~param on DATA. CF set = found.
fsalb_present
                ld    a,ALBC_CHECK
                call  alb_sendcmd
                ld    a,#55
                out   (c),a                     ; param -> chip replies ~#55 = #AA
                in    a,(c)
                cp    #AA
                jr    nz,alp_no
                scf
                ret
alp_no
                or    a
                ret

; alb_ensure_mount: SET_USB_MODE + DISK_MOUNT once. CF set = mounted.
alb_ensure_mount
                ld    a,(fsalb_mounted)
                or    a
                scf
                ret   nz
                ld    e,ALB_USBMODE_USB        ; #132: a USB (UMS) drive needs USB-HOST mode, not
                ld    d,1                       ; SD; mode 6 resets the bus -> wait for re-attach
                call  alb_try_mount
                jr    c,aem_ok
                ld    e,ALB_USBMODE_SD         ; fall back to SD-card mode (the original behaviour)
                ld    d,0
                call  alb_try_mount
                jr    nc,aem_fail
aem_ok
                ld    a,1
                ld    (fsalb_mounted),a
                scf
                ret
aem_fail
                or    a
                ret

; alb_try_mount: E = SET_USB_MODE byte; D != 0 if that mode resets the USB bus (then we
; wait for the device to re-enumerate before DISK_MOUNT). CF set = mounted, NC = not.
alb_try_mount
                ld    a,ALBC_USBMODE
                call  alb_sendcmd
                out   (c),e                     ; mode byte -> chip acks on DATA
                ex    (sp),hl                  ; settle >20us before reading the ack
                ex    (sp),hl
                ex    (sp),hl
                ex    (sp),hl
                ex    (sp),hl
                ex    (sp),hl
                in    a,(c)
                cp    ALB_RET_SUCCESS
                jr    nz,atm_fail
                ld    a,d                       ; bus was reset -> consume the CONNECT interrupt
                or    a                          ; (the device re-enumerates) before mounting
                jr    z,atm_mount
                call  alb_waitint
atm_mount
                ld    a,ALBC_DISKMOUNT
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jr    nz,atm_fail
                scf
                ret
atm_fail
                or    a
                ret

; ---------------------------------------------------------------------------
; fsalb_dir_first: open the root directory for a wildcard enumeration. The
; chip stages the first matching entry; we decode it (skipping '.'/'..'/LFN/
; volume) and return it. CF set = entry ready.
fsalb_dir_first
                call  alb_ensure_mount
                jr    nc,alb_scan_end
                ld    a,ALBC_SETNAME             ; SET_FILE_NAME <path>/* (#104: current
                call  alb_sendcmd                ; dir - "/*" at root, "/GAMES/*" in a subdir)
                call  alb_emit_path
                ld    a,'/'
                out   (c),a
                ld    a,'*'
                out   (c),a
                xor   a
                out   (c),a                      ; NUL terminator
                ld    a,ALBC_FILEOPEN
                call  alb_sendcmd
                call  alb_waitint
                jr    alb_scan_eval

; fsalb_dir_next: advance the enumeration to the next entry.
fsalb_dir_next
                ld    a,ALBC_ENUMGO
                call  alb_sendcmd
                call  alb_waitint
alb_scan_eval
                cp    ALB_INT_DISKRD             ; entry available?
                jr    nz,alb_scan_end            ; ERR_MISS_FILE/other -> end
                call  alb_decode_entry           ; fill fs_ent_*, CF = keep
                jr    nc,fsalb_dir_next          ; filtered -> skip to next
                scf
                ret
alb_scan_end
                or    a                          ; NC = end of directory
                ret

; alb_decode_entry: RD_USB_DATA0 the staged 32-byte FAT record into fs_ent_*.
; CF set = a real file/dir to show, NC = skip (LFN fragment / volume / '.').
alb_decode_entry
                ld    a,ALBC_RDDATA0
                call  alb_sendcmd
                in    a,(c)                      ; payload length (expect 32)
                cp    32
                jr    nz,ade_skip
                ld    hl,fs_ent_name             ; name[0..10]
                ld    a,11
                call  alb_inira
                in    a,(c)                      ; attribute @0x0B
                ld    (fs_ent_attr),a
                ld    d,a
                ld    a,16                        ; skip 0x0C..0x1B
                call  alb_invoid
                ld    hl,fs_ent_size             ; size @0x1C (4 bytes)
                ld    a,4
                call  alb_inira
                ld    a,d                          ; LFN fragment? (attr&0x0F==0x0F)
                and   #0F
                cp    #0F
                jr    z,ade_skip
                ld    a,d                          ; volume label? (attr&0x08)
                and   #08
                jr    nz,ade_skip
                ld    a,(fs_ent_name)             ; '.' / '..'
                cp    '.'
                jr    z,ade_skip
                scf
                ret
ade_skip
                or    a
                ret

; ---------------------------------------------------------------------------
; fsalb_load_file: open fs_req_name in the root and stream it into (fs_load_dst).
; Requests #FFFF bytes and reads 255-byte chunks until the chip reports EOF
; (a zero-length chunk with status SUCCESS). fs_ent_size := bytes read.
; CF set = loaded, NC = not found.
fsalb_load_file
                call  alb_ensure_mount
                jp    nc,alf_nf                   ; jp: alf_nf is out of jr range (#110)
                call  alb_setname_req
                ld    a,ALBC_FILEOPEN
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jp    nz,alf_nf                   ; missing / is a directory
                ld    a,ALBC_BYTEREAD
                call  alb_sendcmd
                ld    a,#FF
                out   (c),a                       ; request #FFFF bytes (lo)
                out   (c),a                       ; (hi) -> kicks the read
                ld    hl,0
                ld    (fs_ent_size),hl
                ld    (fs_ent_size+2),hl
alf_loop
                call  alb_waitint                 ; DISK_READ = more, SUCCESS = end
                push  af
                ld    a,ALBC_RDDATA0
                call  alb_sendcmd
                in    a,(c)                        ; chunk length (0..255)
                or    a
                jr    z,alf_eof
                ld    e,a                          ; E = chunk length
                ld    d,0                           ; #110: refuse if this chunk would push
                ld    hl,(fs_ent_size)             ; the total past fs_load_max (the caller's
                add   hl,de                        ; buffer) - the chip doesn't give the size
                ld    bc,(fs_load_max)             ; up front, so guard mid-stream like the IDE
                or    a                             ; backend does up front
                sbc   hl,bc
                jr    z,alf_inbounds               ; total == max: ok
                jr    c,alf_inbounds               ; total <  max: ok
                pop   af                            ; total > max: too big -> abort the load
                jr    alf_toobig
alf_inbounds
                ld    bc,ALB_DAT                    ; restore BC = data port (the cmp used it)
                ld    a,e                           ; A = chunk length
                ld    hl,(fs_load_dst)
                call  alb_inira                    ; A bytes -> (fs_load_dst)
                ld    d,0
                ld    hl,(fs_load_dst)             ; advance destination
                add   hl,de
                ld    (fs_load_dst),hl
                ld    hl,(fs_ent_size)             ; running byte count
                add   hl,de
                ld    (fs_ent_size),hl
                jr    nc,alf_nocarry
                ld    hl,(fs_ent_size+2)
                inc   hl
                ld    (fs_ent_size+2),hl
alf_nocarry
                pop   af
                cp    ALB_INT_SUCCESS              ; was that the final chunk?
                jr    z,alf_done
                ld    a,ALBC_BYTERDGO
                call  alb_sendcmd                  ; ask for the next chunk
                jr    alf_loop
alf_eof
                pop   af
alf_done
                ld    a,ALBC_FILECLOSE
                call  alb_sendcmd
                xor   a
                out   (c),a                        ; close param (no size update)
                call  alb_waitint
                scf
                ret
alf_toobig                                         ; #110: file > buffer -> close + fail (NC)
                ld    a,ALBC_FILECLOSE
                call  alb_sendcmd
                xor   a
                out   (c),a
                call  alb_waitint
alf_nf
                or    a
                ret

; ---------------------------------------------------------------------------
; fsalb_save_file: write fs_save_len bytes from (fs_save_src) to fs_req_name.
; FILE_CREATE truncates/recreates (so this overwrites), then a BYTE_WRITE loop
; streams the data straight from the caller's still-mapped app page - the chip
; meters each round via WR_REQ_DATA, so there's no low-RAM staging or size cap.
; CF set = saved, NC = failed.
fsalb_save_file
                call  alb_ensure_mount
                jr    nc,asv_fail
                call  alb_setname_req
                ld    a,ALBC_FILECREATE
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jr    nz,asv_fail                 ; couldn't create the file
                ld    a,ALBC_BYTEWRITE
                call  alb_sendcmd
                ld    hl,(fs_save_len)            ; total length -> kicks the write
                ld    a,l
                out   (c),a
                ld    a,h
                out   (c),a
                ld    hl,(fs_save_src)            ; HL = source, advanced per chunk
asv_loop
                call  alb_waitint                 ; DISK_WRITE = wants data, SUCCESS = end
                cp    ALB_INT_SUCCESS
                jr    z,asv_close
                cp    ALB_INT_DISKWR
                jr    nz,asv_fail
                ld    a,ALBC_WRREQ                ; ask how many bytes the chip will take
                call  alb_sendcmd
                in    a,(c)                        ; A = accept count (0..255)
                or    a
                jr    z,asv_go
                call  alb_outira                  ; stream A bytes from (HL), advance HL
asv_go
                ld    a,ALBC_BYTEWRGO             ; flush the chunk, advance
                call  alb_sendcmd
                jr    asv_loop
asv_close
                ld    a,ALBC_FILECLOSE
                call  alb_sendcmd
                ld    a,1                          ; close param 1 = update the file size
                out   (c),a
                call  alb_waitint
                scf
                ret
asv_fail
                or    a
                ret

; fsalb_delete_file: erase fs_req_name. FILE_ERASE opens-then-deletes a closed
; file, so SET_FILE_NAME + FILE_ERASE is enough. CF set = deleted, NC = failed.
; NOTE: 1984's fat.c returns DISK_ERR for FILE_ERASE, so this can't be verified in
; the emulator - it works on real CH376 hardware.
fsalb_delete_file
                call  alb_ensure_mount
                jr    nc,adl_fail
                call  alb_setname_req
                ld    a,ALBC_FILEERASE
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jr    nz,adl_fail
                scf
                ret
adl_fail
                or    a
                ret

; ---------------------------------------------------------------------------
; alb_setname_req: SET_FILE_NAME from the 11-byte packed 8.3 fs_req_name, sent
; as "NNNNNNNN.EEE\0" (the chip's normaliser prepends '/' and trims padding).
alb_setname_req
                ld    a,ALBC_SETNAME
                call  alb_sendcmd
                call  alb_emit_path               ; <path> prefix (#104 subdirs)
                ld    a,'/'
                out   (c),a
                ld    hl,fs_req_name
                ld    a,8
                call  alb_outira                  ; 8 name chars
                ld    a,'.'
                out   (c),a
                ld    a,3
                call  alb_outira                  ; 3 extension chars
                xor   a
                out   (c),a                        ; NUL terminator
                ret

; alb_emit_path: stream alb_path (NUL-terminated current dir) to the DATA port for
; use inside a SET_FILE_NAME. "" at root emits nothing. B/C (port) preserved.
alb_emit_path
                ld    hl,alb_path
aep_loop
                ld    a,(hl)
                or    a
                ret   z
                inc   b
                outi                               ; out (c),(hl); hl++; b restored
                jr    aep_loop

; ---------------------------------------------------------------------------
; fsalb_chdir (GB_CHDIR on the Albireo build): descend into the positioned folder
; by appending "/<name>" to alb_path. fs_ent_name holds the folder's 8.3 name (the
; FM dir_seek'd it before chdir). Refuses (no-op) if the path would overflow.
fsalb_chdir
                ld    hl,alb_path                 ; HL -> end of path, B = its length
                ld    b,0
fch_end
                ld    a,(hl)
                or    a
                jr    z,fch_atend
                inc   hl
                inc   b
                jr    fch_end
fch_atend
                ld    a,b                          ; keep room for "/NAME.EXT" + NUL
                cp    ALB_PATH_MAX-14
                ret   nc                            ; too deep -> ignore
                ld    (hl),'/'
                inc   hl
                ; fall through: append the compacted 8.3 fs_ent_name at HL + NUL
alb_append_name
                ld    de,fs_ent_name              ; up to 8 name chars (stop at space)
                ld    b,8
aan_name
                ld    a,(de)
                cp    ' '
                jr    z,aan_ext
                ld    (hl),a
                inc   hl
                inc   de
                djnz  aan_name
aan_ext
                ld    de,fs_ent_name+8            ; extension (3 chars)
                ld    a,(de)
                cp    ' '
                jr    z,aan_done                   ; no extension
                ld    (hl),'.'
                inc   hl
                ld    b,3
aan_extc
                ld    a,(de)
                cp    ' '
                jr    z,aan_done
                ld    (hl),a
                inc   hl
                inc   de
                djnz  aan_extc
aan_done
                ld    (hl),0                       ; NUL-terminate the path
                ret

; fsalb_back (GB_BACK on the Albireo build): go up one level - truncate alb_path at
; its last '/'. Root ("") is a no-op.
fsalb_back
                ld    hl,alb_path
                ld    de,0                          ; DE = last '/' seen (0 = none)
fbk_scan
                ld    a,(hl)
                or    a
                jr    z,fbk_done
                cp    '/'
                jr    nz,fbk_next
                ld    d,h
                ld    e,l
fbk_next
                inc   hl
                jr    fbk_scan
fbk_done
                ld    a,d
                or    e
                ret   z                              ; no '/' -> already at root
                ex    de,hl
                ld    (hl),0                          ; truncate at the last '/'
                ret

; alb_inira: read A bytes from BC(=DATA) into (HL). B preserved (port high).
alb_inira
                ini
                inc   b
                dec   a
                jr    nz,alb_inira
                ret

; alb_outira: write A bytes from (HL) to BC(=DATA). B preserved.
alb_outira
                inc   b
                outi
                dec   a
                jr    nz,alb_outira
                ret

; alb_invoid: read and discard A bytes from BC(=DATA).
alb_invoid
                push  af
                in    a,(c)
                pop   af
                dec   a
                jr    nz,alb_invoid
                ret

fsalb_mounted   defb  0            ; 0 until SET_USB_MODE+DISK_MOUNT done once

; #104: current directory as a CH376 path, NUL-terminated. "" = root; "/GAMES" or
; "/GAMES/RPG" in a subdir. fsalb_chdir appends "/<name>", fsalb_back truncates at
; the last '/'. Prefixed onto every SET_FILE_NAME via alb_emit_path. Zero-init = root.
ALB_PATH_MAX    equ   64
alb_path        defs  ALB_PATH_MAX

; Shared directory-context state the kernel manipulates generically (k_chdir/
; k_back, cross-drive copy). The IDE backend tracks the current directory by FAT
; cluster; the CH376 tracks it internally by path, so this backend lists the root
; only for now and ignores fs_dir_clus - these just satisfy the kernel's refs.
; TODO(#104): path-based current-dir for subdirectory navigation on Albireo.
fs_dir_clus     defs  4            ; current directory (unused by the CH376 path model)
fs_dir_sp       defb  0            ; chdir/back stack depth
fs_dir_stack    defs  16           ; 4 parent dirs (4 bytes each)
fs_ent_clus     defs  4            ; positioned entry's start cluster
