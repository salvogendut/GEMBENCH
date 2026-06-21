; ---------------------------------------------------------------------------
; lib/fs_m4.asm - storage backend: FAT over the M4 board (file-level, #174).
;
; Like the Albireo CH376 (fs_albireo.asm), the M4 firmware owns the filesystem -
; we do NOT parse FAT here (contrast fs_ide_fat.asm). We issue the M4's high-level
; file commands and the board walks the directory / file. So this build does NOT
; include fs_fat32_core.asm / fs_ide_read.asm at all - no IDE FAT core resident.
;
; M4 command protocol (mirrors Duke's M4ROM.s + 1984 src/m4.c, proven on real HW):
;   * write a packet [#00 lead][cmd_lo][cmd_hi=#43][params...] one byte at a time
;     to DATAPORT (#FE00), then strobe ACKPORT (#FC00) - the board bus-HOLDS the
;     OUT until the command (incl. the SD access) completes, so no poll/NMI wait.
;   * read the response from rom_response (#E800), visible only while M4ROM (upper
;     ROM slot 6) is the selected upper ROM. Response = [len@0][cmd_lo@1][#43@2]
;     [data@3..]; resp_frame sets len = (#data + 2), so #E800+0 == 2 means "no data"
;     (C_READDIR end-of-directory). Per-command status lives in the data area (+3..).
;   GEOBENCH runs with the upper ROM enabled (#7F85), so each command just selects
;   slot 6 (#DF00=6) for the whole send+ack+read, then restores AMSDOS (#DF00=7).
;
; Backend entry points (same shape as fsalb_*/fside_* so lib/fs.asm routes here):
;   fsm4_dir_first -> CF set = first entry in fs_ent_*, NC = empty
;   fsm4_dir_next  -> CF set = next entry,               NC = end of dir
;   fsm4_load_file -> CF set = loaded (fs_ent_size = bytes), NC = not found
; Read-only: D0_SAVE/DELETE map to fs_load_none (C_WRITE is a later phase).
;
; M4 directory model: C_READDIR enumerates the board's CURRENT directory, so each
; listing first C_CD's to m4_path (absolute, rebuilt from the path string every time
; - like fs_albireo - so chdir/back never desync). Loads use an absolute C_OPEN path,
; so they need no C_CD. NOTE: the M4's C_READDIR prefixes directories with '>' inside
; the 8-char name field, so an 8-character directory name loses its last char in the
; listing (files are unaffected). The system dir is entered by the hardcoded
; "/GEOBENCH" path (fs_sysdir_enter), so boot + app loading never depend on the listing.
; ---------------------------------------------------------------------------

M4_DATA         equ   #FE00        ; DATAPORT  (write command bytes; lead byte then cmd)
M4_ACK          equ   #FC00        ; ACKPORT   (strobe = execute; board bus-holds until done)
M4_RESP         equ   #E800        ; rom_response (read while M4ROM/slot 6 is selected)
M4_ROMNUM       equ   6            ; M4ROM expansion slot

M4C_OPEN        equ   #01          ; C_OPEN   (#4301)
M4C_READ2       equ   #12          ; C_READ2  (#4312) - unbuffered, gives actual size + EOF
M4C_CLOSE       equ   #04          ; C_CLOSE  (#4304)
M4C_CD          equ   #08          ; C_CD     (#4308)
M4C_DIRARGS     equ   #25          ; C_DIRSETARGS (#4325)
M4C_READDIR     equ   #06          ; C_READDIR (#4306)
M4_OPENMODE     equ   #81          ; FA_READ | FA_REALMODE (dynamic fd, bypass AMSDOS fd)
M4_READCHUNK    equ   #0800        ; bytes per C_READ2 (fits the #E800..#F3FF response window)

M4_PATH_MAX     equ   64           ; current-dir path buffer ("" = root, "/GEOBENCH")

; --- transport --------------------------------------------------------------
; m4_io_begin: DI + select M4ROM (slot 6) so DATAPORT/ACKPORT are serviced and the
; response window maps at #E800. Upper ROM stays enabled (#7F85 = GEOBENCH steady).
m4_io_begin
                di
                ld    bc,#7F85               ; upper ROM ON + lower ROM OFF (low RAM visible)
                out   (c),c
                ld    bc,#DF00
                ld    a,M4_ROMNUM
                out   (c),a
                ret
; m4_io_end: restore AMSDOS (slot 7) + EI.
m4_io_end
                ld    bc,#DF00
                ld    a,7
                out   (c),a
                ei
                ret
; m4_lead: start a command packet - BC = DATAPORT, write the #00 lead byte (as M4ROM does).
m4_lead
                ld    bc,M4_DATA
                out   (c),c                  ; lead byte = C = #00
                ret
; m4_go: strobe ACKPORT - blocks (board bus-hold) until the command completes.
m4_go
                ld    bc,M4_ACK
                out   (c),c
                ret
; m4_emit_str: stream the NUL-terminated string at HL to DATAPORT (BC=#FE00), NUL not sent.
m4_emit_str
                ld    a,(hl)
                or    a
                ret   z
                out   (c),a
                inc   hl
                jr    m4_emit_str
; m4_emit_83: stream fs_req_name to DATAPORT as a TRIMMED 8.3 name ("GBCFG.BIN", not
; "GBCFG   .BIN"). D is the counter (B is the port high byte #FE). BC preserved.
m4_emit_83
                ld    hl,fs_req_name
                ld    d,8
me83_nm         ld    a,(hl)
                cp    ' '
                jr    z,me83_ext
                out   (c),a
                inc   hl
                dec   d
                jr    nz,me83_nm
me83_ext        ld    hl,fs_req_name+8
                ld    a,(hl)
                cp    ' '
                ret   z
                ld    a,'.'
                out   (c),a
                ld    d,3
me83_e1         ld    a,(hl)
                cp    ' '
                ret   z
                out   (c),a
                inc   hl
                dec   d
                jr    nz,me83_e1
                ret

; m4_cd_path: C_CD to m4_path (absolute). "" -> "/". No result read (the emulator
; doesn't echo C_CD's status; we trust it and let the following C_READDIR reflect reality).
m4_cd_path
                call  m4_io_begin
                call  m4_lead
                ld    a,M4C_CD
                out   (c),a
                ld    a,#43
                out   (c),a
                ld    a,(m4_path)            ; root? emit a bare "/"
                or    a
                jr    nz,mcd_abs
                ld    a,'/'
                out   (c),a
                jr    mcd_nul
mcd_abs         ld    hl,m4_path             ; else emit the absolute path
                call  m4_emit_str
mcd_nul         xor   a
                out   (c),a                  ; NUL terminator
                call  m4_go
                jp    m4_io_end

; --- present + directory ----------------------------------------------------
; fsm4_present (D0_PRESENT): list the current dir (root at boot) - if it yields an
; entry the M4 SD is present + readable. CF set = present.
fsm4_present
                jp    fsm4_dir_first

; fsm4_dir_first: cd to m4_path, set the wildcard filter, return the first entry.
fsm4_dir_first
                call  m4_cd_path
                call  m4_io_begin            ; C_DIRSETARGS "*" (reset the iterator)
                call  m4_lead
                ld    a,M4C_DIRARGS
                out   (c),a
                ld    a,#43
                out   (c),a
                ld    a,'*'
                out   (c),a
                xor   a
                out   (c),a
                call  m4_go
                call  m4_io_end
                jr    fsm4_dir_next

; fsm4_dir_next: C_READDIR one entry; decode into fs_ent_*. Skips nothing extra (the
; M4 already drops '.'/'..'). CF set = entry ready, NC = end of directory.
fsm4_dir_next
                call  m4_io_begin
                call  m4_lead
                ld    a,M4C_READDIR
                out   (c),a
                ld    a,#43
                out   (c),a
                ld    a,11                    ; max display name length (8.3)
                out   (c),a
                call  m4_go
                ld    a,(M4_RESP)            ; length byte: == 2 means end-of-directory
                cp    2
                jr    z,mdn_end
                call  m4_decode_entry        ; fill fs_ent_* from #E800+3..
                call  m4_io_end
                scf
                ret
mdn_end
                call  m4_io_end
                or    a                       ; NC = end of directory
                ret

; m4_decode_entry: parse the C_READDIR entry (slot 6 still paged) into fs_ent_*.
;   #E800+3..+10 = 8-char name (space-padded); '>' at +3 marks a directory (its name
;                  is then +4.., 7 chars). +12..+14 = 3-char ext. +21..+22 = size (16-bit).
m4_decode_entry
                ld    a,(M4_RESP+3)          ; directory? ('>' prefix)
                cp    '>'
                jr    z,mde_dir
                ld    hl,M4_RESP+3           ; file: 8-char name straight across
                ld    de,fs_ent_name
                ld    bc,8
                ldir
                xor   a
                ld    (fs_ent_attr),a        ; attr 0 = a file
                jr    mde_ext
mde_dir
                ld    hl,M4_RESP+4           ; dir: name is +4.. (7 chars), then pad
                ld    de,fs_ent_name
                ld    bc,7
                ldir
                ld    a,' '
                ld    (de),a                  ; pad fs_ent_name[7]
                ld    a,#10                   ; attr bit4 = directory
                ld    (fs_ent_attr),a
mde_ext
                ld    hl,M4_RESP+12          ; 3-char extension
                ld    de,fs_ent_name+8
                ld    bc,3
                ldir
                ld    hl,(M4_RESP+21)        ; 16-bit size -> fs_ent_size (high word 0)
                ld    (fs_ent_size),hl
                ld    hl,0
                ld    (fs_ent_size+2),hl
                ret

; --- file load --------------------------------------------------------------
; fsm4_load_file: C_OPEN the absolute path m4_path + "/" + fs_req_name, then C_READ2
; #0800-byte chunks into (fs_load_dst) until EOF (status #20), guarding fs_load_max.
; fs_ent_size := bytes read. CF set = loaded, NC = not found / too big.
fsm4_load_file
                call  m4_io_begin            ; --- C_OPEN <mode><path> ---
                call  m4_lead
                ld    a,M4C_OPEN
                out   (c),a
                ld    a,#43
                out   (c),a
                ld    a,M4_OPENMODE
                out   (c),a                  ; mode: FA_READ | dynamic fd
                ld    a,(m4_path)            ; absolute path prefix (m4_path, "" = root)
                or    a
                jr    z,mlf_slash
                ld    hl,m4_path
                call  m4_emit_str
mlf_slash       ld    a,'/'
                out   (c),a
                call  m4_emit_83             ; trimmed 8.3 name
                xor   a
                out   (c),a                  ; NUL
                call  m4_go
                ld    a,(M4_RESP+4)          ; open error (0 = OK)
                or    a
                jr    nz,mlf_nf_io
                ld    a,(M4_RESP+3)          ; file descriptor
                ld    (m4_fd),a
                call  m4_io_end
                ld    hl,0                    ; fs_ent_size = 0
                ld    (fs_ent_size),hl
                ld    (fs_ent_size+2),hl
mlf_loop
                call  m4_read_chunk          ; C_READ2 -> copy actual bytes, advance
                jr    nc,mlf_toobig          ; NC = chunk would overflow fs_load_max
                ; EOF = a PARTIAL chunk (actual < #0800). Detect it by the SIZE field, NOT the
                ; status byte: the emulator reports EOF status #14 but M4ROM/real HW use #20
                ; (cp #20 in M4ROM.s) - reading past EOF on real HW returns garbage and reboots.
                ld    a,(m4_actual+1)        ; actual-size high byte (#0800 -> #08)
                cp    #08
                jr    c,mlf_done             ; actual < #0800 -> last chunk
                jr    mlf_loop               ; actual == #0800 -> more data follows
mlf_done
                call  m4_close_fd
                scf
                ret
mlf_nf_io
                call  m4_io_end
                or    a
                ret
mlf_toobig
                call  m4_close_fd
                or    a
                ret

; m4_read_chunk: C_READ2 m4_fd, #0800 -> guard against fs_load_max, copy the actual
; bytes from #E808 into (fs_load_dst), advance fs_load_dst + fs_ent_size.
; Returns CF set + A = M4 status (#20 = EOF), or NC = chunk overflows fs_load_max.
m4_read_chunk
                call  m4_io_begin
                call  m4_lead
                ld    a,M4C_READ2
                out   (c),a
                ld    a,#43
                out   (c),a
                ld    a,(m4_fd)
                out   (c),a
                ld    a,#00
                out   (c),a                  ; count lo (#0800 = M4_READCHUNK)
                ld    a,#08
                out   (c),a                  ; count hi
                call  m4_go
                ld    a,(M4_RESP+3)          ; status (0 = more, #20 = EOF)
                ld    (m4_status),a
                ld    hl,(M4_RESP+4)        ; actual bytes read this chunk
                ld    (m4_actual),hl
                ; guard: refuse if fs_ent_size + actual would exceed fs_load_max
                ld    de,(fs_ent_size)
                add   hl,de
                ld    de,(fs_load_max)
                or    a
                sbc   hl,de
                jr    z,mrc_ok               ; total == max: ok
                jr    c,mrc_ok               ; total <  max: ok
                call  m4_io_end             ; total > max: abort (NC)
                or    a
                ret
mrc_ok
                ld    hl,(m4_actual)         ; copy actual bytes #E808 -> (fs_load_dst)
                ld    a,h
                or    l
                jr    z,mrc_advance          ; zero-length chunk: nothing to copy
                ld    bc,(m4_actual)
                ld    hl,M4_RESP+8
                ld    de,(fs_load_dst)
                ldir
                ld    (fs_load_dst),de        ; ldir left DE past the copy
                ld    hl,(fs_ent_size)        ; fs_ent_size += actual
                ld    de,(m4_actual)
                add   hl,de
                ld    (fs_ent_size),hl
                jr    nc,mrc_advance
                ld    hl,(fs_ent_size+2)
                inc   hl
                ld    (fs_ent_size+2),hl
mrc_advance
                call  m4_io_end
                ld    a,(m4_status)
                scf
                ret

; m4_close_fd: C_CLOSE m4_fd.
m4_close_fd
                call  m4_io_begin
                call  m4_lead
                ld    a,M4C_CLOSE
                out   (c),a
                ld    a,#43
                out   (c),a
                ld    a,(m4_fd)
                out   (c),a
                call  m4_go
                jp    m4_io_end

; --- #134 system-dir hooks (path-based, like Albireo) -----------------------
; The M4 is path-based: system loads run from the "/GEOBENCH" prefix regardless of
; the File Manager's browse path. enter swaps m4_path to /GEOBENCH, leave restores it.
fs_sys_resolve
                ret
fs_sysdir_enter
                ld    hl,m4_path
                ld    de,m4_path_save
                ld    bc,M4_PATH_MAX
                ldir
                ld    hl,m4_sysdir
                ld    de,m4_path
                ld    bc,m4_sysdir_end-m4_sysdir
                ldir
                ret
fs_sysdir_leave
                ld    hl,m4_path_save
                ld    de,m4_path
                ld    bc,M4_PATH_MAX
                ldir
                ret
m4_sysdir       db    "/GBENCH",0   ; #174: <=7 chars so the M4's '>'-prefixed dir listing
                                     ; round-trips it (an 8-char dir name loses its last char)
m4_sysdir_end
m4_path_save    defs  M4_PATH_MAX

; --- chdir / back (edit the m4_path string, like fsalb_chdir/back) -----------
; fsm4_chdir (k_chdir): descend into the positioned folder by appending "/<name>" to
; m4_path. fs_ent_name holds the folder's 8.3 name. Refuses if the path would overflow.
fsm4_chdir
                ld    hl,m4_path
                ld    b,0
fmc_end         ld    a,(hl)
                or    a
                jr    z,fmc_atend
                inc   hl
                inc   b
                jr    fmc_end
fmc_atend       ld    a,b
                cp    M4_PATH_MAX-14
                ret   nc                       ; too deep -> ignore
                ld    (hl),'/'
                inc   hl
                ld    de,fs_ent_name           ; append up to 8 name chars (stop at space)
                ld    b,8
fmc_name        ld    a,(de)
                cp    ' '
                jr    z,fmc_ext
                ld    (hl),a
                inc   hl
                inc   de
                djnz  fmc_name
fmc_ext         ld    de,fs_ent_name+8         ; extension
                ld    a,(de)
                cp    ' '
                jr    z,fmc_done
                ld    (hl),'.'
                inc   hl
                ld    b,3
fmc_extc        ld    a,(de)
                cp    ' '
                jr    z,fmc_done
                ld    (hl),a
                inc   hl
                inc   de
                djnz  fmc_extc
fmc_done        ld    (hl),0
                ret

; fsm4_back (k_back): go up one level - truncate m4_path at its last '/'. Root is a no-op.
fsm4_back
                ld    hl,m4_path
                ld    de,0
fmb_scan        ld    a,(hl)
                or    a
                jr    z,fmb_done
                cp    '/'
                jr    nz,fmb_next
                ld    d,h
                ld    e,l
fmb_next        inc   hl
                jr    fmb_scan
fmb_done        ld    a,d
                or    e
                ret   z
                ex    de,hl
                ld    (hl),0
                ret

; --- state ------------------------------------------------------------------
m4_path         defs  M4_PATH_MAX  ; current dir as an M4 path (zero-init = root)
m4_fd           defb  0            ; the open file's descriptor
m4_status       defb  0            ; last C_READ2 status
m4_actual       defw  0            ; last C_READ2 byte count

; Shared directory-context state the kernel manipulates generically (k_chdir/k_back,
; cross-drive copy). The M4 tracks the current dir by path and ignores fs_dir_clus -
; these just satisfy the kernel's refs.
fs_dir_clus     defs  4
fs_dir_sp       defb  0
fs_dir_stack    defs  16
fs_ent_clus     defs  4
