; ---------------------------------------------------------------------------
; lib/fs_rom_lowram.inc - fixed low-RAM addresses shared by the resident kernel and
; GEOBENCH.ROM (#152) for the offloaded AMSDOS floppy READ backend.
;
; The backend's code runs from the read-only ROM, so its writable scratch must live
; in low RAM that both sides agree on. Included by kernel/gbkern.asm (resident, for
; the stubs + fs_set_drive) and rom/geobench_rom.asm (the ROM, for the real code)
; whenever FS_RDIO_LOWRAM is set. The fsam_buf (#1A00) directory buffer + fs_secbuf
; are fixed elsewhere. Free gap used: #1256-#128E (above lba_tmp/gb_rom_num #1250/#1254).
; ---------------------------------------------------------------------------

FSAM_STATE_BASE equ   #1256
fsam_unit       equ   FSAM_STATE_BASE+0   ; selected drive: 0 = A, 1 = B
fsam_base       equ   FSAM_STATE_BASE+1   ; first physical sector id (format-dependent)
fsam_track      equ   FSAM_STATE_BASE+2   ; directory track
fsam_dst        equ   FSAM_STATE_BASE+3   ; fsam_read_sector destination, advances
FSAM_CORE_END   equ   FSAM_STATE_BASE+5   ; (fs_amsdos read state continues from here)
fslf_blocks     equ   FSAM_CORE_END+0     ; allocation block numbers of the found extent (16)
fslf_secs       equ   FSAM_CORE_END+16    ; sectors left to read
fslf_si         equ   FSAM_CORE_END+17    ; sector index within the file
fslf_rc         equ   FSAM_CORE_END+18    ; record count (for the no-header size)
fslf_curtrk     equ   FSAM_CORE_END+19    ; track the head is currently on
fsam_idx        equ   FSAM_CORE_END+20    ; directory-listing cursor (ends FSAM_CORE_END+21 = #1270)

; floppy read I/O transfer area (#1270+): the ROM writes/reads these; the resident
; stubs marshal them <-> the real fs_ent_*/fs_req_name/fs_load_*.
FSAM_IO_NAME    equ   #1270        ; output: entry name (11)
FSAM_IO_ATTR    equ   #127B        ; output: entry attribute (1)
FSAM_IO_SIZE    equ   #127C        ; output: entry size (4)
FSAM_IO_REQ     equ   #1280        ; input: name to load (11)
FSAM_IO_DST     equ   #128B        ; input: load destination (2)
FSAM_IO_MAX     equ   #128D        ; input: load max bytes (2)   -> ends #128E
