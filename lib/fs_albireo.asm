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
ALBC_DISKQUERY  equ   #3F

; CH376 status / return codes
ALB_RET_SUCCESS equ   #51          ; SET_USB_MODE ack on the DATA port
ALB_INT_SUCCESS equ   #14
ALB_INT_DISKRD  equ   #1D
ALB_INT_DISKWR  equ   #1E
ALB_USBMODE_SD  equ   3            ; host mode, micro-SD (LLM_MicroSD)
ALB_USBMODE_USB equ   6            ; #132: host mode, USB + reset the USB bus (for UMS drives)

; ---------------------------------------------------------------------------
; #152: the CH376 I/O code below runs from GEOBENCH.ROM (IN_GBROM) and the plain
; resident build; the GB_ROM resident replaces it with thin ROM-call stubs.
                ifndef GB_ROM_STUBS
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
                endif                          ; GB_ROM_STUBS (alb_sendcmd / alb_waitint)

; fsalb_present: probe the chip. CHECK_EXIST echoes ~param on DATA. CF set = found.
; Resident in every build (fs_init calls it at boot, BEFORE gb_rom_probe runs - so it
; can't be a ROM stub) and self-contained (inlines alb_sendcmd, which lives in the ROM).
                ifndef IN_GBROM
fsalb_present
                ld    bc,ALB_CMD
                ld    a,ALBC_CHECK
                out   (c),a
                dec   c                         ; BC -> ALB_DAT
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
                endif                          ; IN_GBROM (fsalb_present resident-only)

                ifndef GB_ROM_STUBS
; alb_ensure_mount: SET_USB_MODE + DISK_MOUNT once. CF set = mounted.
alb_ensure_mount
                ld    a,(fsalb_mounted)
                or    a
                scf
                ret   nz
                call  alb_mount_plain         ; GEOBENCH is loaded BY UniDOS, which ALREADY
                jr    c,aem_ok                 ; SET_USB_MODE+DISK_MOUNT'd the card. Try a plain
                                               ; DISK_MOUNT in the CURRENT mode first - no bus
                                               ; reset - so we don't reset a card UniDOS just set
                                               ; up (a real-HW reboot 1984 never shows: it mounts
                                               ; regardless of mode). Cold boot: fall through.
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

; alb_mount_plain: DISK_MOUNT in whatever USB mode the chip is already in (no SET_USB_MODE,
; no bus reset). CF set = mounted. Used to re-use UniDOS's existing mount on the boot handoff.
alb_mount_plain
                ld    a,ALBC_DISKMOUNT
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                jr    z,amp_ok
                or    a                          ; NC = not mounted in the current mode
                ret
amp_ok
                scf
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
                ld    a,ALBC_SETNAME             ; try ABSOLUTE first: SET_FILE_NAME <path>/* + OPEN
                call  alb_sendcmd                ; ("/*" at root, "/GEOBENCH/*" in a subdir) - works
                call  alb_emit_path              ; on the stateless 1984 CH376 and at root
                ld    a,'/'
                out   (c),a
                ld    a,'*'
                out   (c),a
                xor   a
                out   (c),a                      ; NUL terminator
                ld    a,ALBC_FILEOPEN
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_DISKRD             ; an entry staged? (absolute worked)
                jr    z,alb_scan_eval
                ld    a,(alb_path)               ; absolute gave nothing - a REAL (stateful) CH376
                or    a                           ; can't open an absolute SUBDIR wildcard. At root
                jr    z,alb_scan_eval             ; there's no subdir to enter -> truly empty/done
                ld    a,ALBC_SETNAME             ; cd into alb_path (SET_FILE_NAME the dir + OPEN) ...
                call  alb_sendcmd
                call  alb_emit_path              ; "/GEOBENCH"
                xor   a
                out   (c),a
                ld    a,ALBC_FILEOPEN
                call  alb_sendcmd
                call  alb_waitint                ; enter the dir (ERR_OPEN_DIR/SUCCESS)
                ld    a,ALBC_SETNAME             ; ... then enumerate "*" RELATIVE to it
                call  alb_sendcmd
                ld    a,'*'
                out   (c),a
                xor   a
                out   (c),a
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
                call  alb_open_req                ; absolute, else cd-into-dir + relative (#real-HW)
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
                endif                          ; GB_ROM_STUBS (mount + dir + load CH376 code)

ALB_PATH_MAX    equ   64           ; CH376 current-dir path buffer size (defined here so
                                   ; the #134 alb_path_save defs below can see it)
                ifdef FS_ALB_LOWRAM           ; #152: the low-RAM layout (fs_alb_lowram.inc)
                assert fsalb_mounted==alb_path+ALB_PATH_MAX,"fs_alb_lowram.inc: fsalb_mounted must follow alb_path[ALB_PATH_MAX]"
                endif
; #134 system-dir hooks (Albireo). The CH376 is path-based: system loads run from
; the "/GEOBENCH" path prefix, regardless of the File Manager's browse path. No
; resolve needed (alb_emit_path prefixes alb_path onto every SET_FILE_NAME);
; enter swaps alb_path to /GEOBENCH and leave restores the browse path. These edit
; the alb_path string only (no CH376 I/O), so they stay resident, never in the ROM.
                ifndef IN_GBROM
fs_sys_resolve
                ret
fs_sysdir_enter
                ld    hl,alb_path                 ; save the active browse path
                ld    de,alb_path_save
                ld    bc,ALB_PATH_MAX
                ldir
                ld    hl,alb_sysdir               ; alb_path = "/GEOBENCH"
                ld    de,alb_path
                ld    bc,alb_sysdir_end-alb_sysdir
                ldir
                ret
fs_sysdir_leave
                ld    hl,alb_path_save            ; restore the browse path
                ld    de,alb_path
                ld    bc,ALB_PATH_MAX
                ldir
                ret
alb_sysdir      db    "/GBENCH",0
alb_sysdir_end
alb_path_save   defs  ALB_PATH_MAX
                endif                          ; IN_GBROM (sysdir hooks resident-only)

                ifndef GB_ROM_STUBS
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
                call  alb_emit_83                 ; trimmed 8.3 name
                xor   a
                out   (c),a                        ; NUL terminator
                ret

; alb_emit_83: stream fs_req_name to the open DATA port as a TRIMMED 8.3 name ("GBCFG.BIN",
; not "GBCFG   .BIN") - padding spaces break FILE_OPEN on real HW (1984 tolerates them). D is
; the counter (B is the I/O port high byte #FE!). BC (port) preserved.
alb_emit_83
                ld    hl,fs_req_name
                ld    d,8
ae83_nm         ld    a,(hl)
                cp    ' '
                jr    z,ae83_ext
                out   (c),a
                inc   hl
                dec   d
                jr    nz,ae83_nm
ae83_ext        ld    hl,fs_req_name+8            ; extension at offset 8; omit "." if blank
                ld    a,(hl)
                cp    ' '
                ret   z
                ld    a,'.'
                out   (c),a
                ld    d,3
ae83_e1         ld    a,(hl)
                cp    ' '
                ret   z
                out   (c),a
                inc   hl
                dec   d
                jr    nz,ae83_e1
                ret

; alb_open_req: FILE_OPEN fs_req_name in directory alb_path. Tries the ABSOLUTE path first
; ("/GEOBENCH/GBCFG.BIN") - works on the stateless 1984 CH376, on root files, and on flat cards;
; a REAL (stateful) CH376 can't resolve an absolute SUBDIR path, so on failure it cd's into
; alb_path (SET_FILE_NAME the dir + FILE_OPEN) and re-opens the name RELATIVE. ZF set = opened.
alb_open_req
                call  alb_setname_req             ; absolute "/<path>/NAME.EXT"
                ld    a,ALBC_FILEOPEN
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                ret   z                            ; opened (emulator / root file / flat card)
                ld    a,(alb_path)                 ; absolute failed: at root there is no subdir to
                or    a                             ; enter, so it is genuinely missing (ZF clear)
                ret   z
                ld    a,ALBC_SETNAME               ; stateful CH376: cd into alb_path ...
                call  alb_sendcmd
                call  alb_emit_path               ; "/GEOBENCH"
                xor   a
                out   (c),a
                ld    a,ALBC_FILEOPEN
                call  alb_sendcmd
                call  alb_waitint                 ; enter the dir (ERR_OPEN_DIR/SUCCESS)
                ld    a,ALBC_SETNAME               ; ... then open the name RELATIVE to it
                call  alb_sendcmd
                call  alb_emit_83                 ; "NAME.EXT" (no path, no leading '/')
                xor   a
                out   (c),a
                ld    a,ALBC_FILEOPEN
                call  alb_sendcmd
                call  alb_waitint
                cp    ALB_INT_SUCCESS
                ret                                ; ZF = opened

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
                endif                          ; GB_ROM_STUBS (save + delete + setname + emit)

; ---------------------------------------------------------------------------
; fsalb_chdir / fsalb_back edit the alb_path string only (k_chdir/k_back jp here
; directly, no CH376 I/O), so they stay resident in every build, never in the ROM.
                ifndef IN_GBROM
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
                endif                          ; IN_GBROM (fsalb_chdir / fsalb_back resident-only)

                ifndef GB_ROM_STUBS
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
                endif                          ; GB_ROM_STUBS (alb_inira / outira / invoid)

                ifdef GB_ROM_STUBS
; ---------------------------------------------------------------------------
; #152 GB_ROM resident: thin ROM-call stubs for the CH376 I/O. The real code runs from
; GEOBENCH.ROM (Albireo dispatch slots #C018..#C027); here we marshal the I/O transfer
; area (#1270) <-> the resident fs_ent_*/fs_req_name/fs_load_*/fs_save_*. alb_path (#1293)
; + fsalb_mounted (#12D3) are FIXED shared low RAM, so the ROM reads them directly and the
; stubs needn't pass them (the resident fsalb_chdir/back/sysdir edit them in place).
fsalb_dir_first ld    hl,#C018               ; ROM Albireo idx0
                call  gb_rom_fsam_invoke
                jr    alb_ent_out
fsalb_dir_next  ld    hl,#C01B               ; ROM Albireo idx1
                call  gb_rom_fsam_invoke
                jr    alb_ent_out
fsalb_load_file ld    hl,fs_req_name          ; marshal inputs -> the transfer area
                ld    de,FSAM_IO_REQ
                ld    bc,11
                ldir
                ld    hl,(fs_load_dst)
                ld    (FSAM_IO_DST),hl
                ld    hl,(fs_load_max)
                ld    (FSAM_IO_MAX),hl
                ld    hl,#C01E               ; ROM Albireo idx2
                call  gb_rom_fsam_invoke
                push  af                       ; preserve CF (loaded?)
                ld    hl,FSAM_IO_SIZE         ; copy the loaded size back out
                ld    de,fs_ent_size
                ld    bc,4
                ldir
                pop   af
                ret
fsalb_save_file ld    hl,fs_req_name          ; name + source pointer + length -> transfer area
                ld    de,FSAM_IO_REQ
                ld    bc,11
                ldir
                ld    hl,(fs_save_src)
                ld    (ALB_IO_SRC),hl          ; the app page stays mapped under #7F85
                ld    hl,(fs_save_len)
                ld    (ALB_IO_SLEN),hl
                ld    hl,#C021               ; ROM Albireo idx3
                jp    gb_rom_fsam_invoke
fsalb_delete_file
                ld    hl,fs_req_name
                ld    de,FSAM_IO_REQ
                ld    bc,11
                ldir
                ld    hl,#C024               ; ROM Albireo idx4
                jp    gb_rom_fsam_invoke
fsalb_free_kib
                or    a                      ; ROM-offloaded Albireo does not expose this yet
                ret
; alb_ent_out: copy the entry the ROM wrote to the transfer area (name+attr+size, 16
; contiguous bytes) into the resident fs_ent_* fields. Preserves the dir CF.
alb_ent_out     push  af
                ld    hl,FSAM_IO_NAME
                ld    de,fs_ent_name
                ld    bc,16
                ldir
                pop   af
                ret
                endif                          ; GB_ROM_STUBS (Albireo I/O stubs)

; --- state ------------------------------------------------------------------
; #152: in the GEOBENCH.ROM builds (FS_ALB_LOWRAM) alb_path + fsalb_mounted are fixed
; low-RAM equs (fs_alb_lowram.inc) shared with the ROM; the plain resident/paged builds
; keep the original defs. #104: alb_path is the current directory as a CH376 path,
; NUL-terminated ("" = root; "/GAMES"); fsalb_chdir appends "/<name>", fsalb_back
; truncates at the last '/'; alb_emit_path prefixes it onto every SET_FILE_NAME.
                ifndef FS_ALB_LOWRAM
fsalb_mounted   defb  0            ; 0 until SET_USB_MODE+DISK_MOUNT done once
alb_path        defs  ALB_PATH_MAX ; zero-init = root
                endif

; Shared directory-context state the kernel manipulates generically (k_chdir/k_back,
; cross-drive copy). The CH376 tracks the current dir internally by path and ignores
; fs_dir_clus - these just satisfy the kernel's refs, so they stay resident, never in
; the ROM. TODO(#104): path-based current-dir for subdirectory navigation on Albireo.
                ifndef IN_GBROM
fs_dir_clus     defs  4            ; current directory (unused by the CH376 path model)
fs_dir_sp       defb  0            ; chdir/back stack depth
fs_dir_stack    defs  16           ; 4 parent dirs (4 bytes each)
fs_ent_clus     defs  4            ; positioned entry's start cluster
                endif
