; ---------------------------------------------------------------------------
; lib/fs_m4.asm - M4-board (CH376-free) SD-card backend, raw-sector route (#174).
;
; The M4 board exposes a RAW LBA sector read (C_SDREAD), so - unlike the Albireo
; CH376, which does FAT in firmware - GEOBENCH reuses its own FAT16/FAT32 core
; here verbatim and only swaps the sector primitive. This file supplies the M4
; transport + an M4 fs_read_sector, then includes the shared core + the fside_*
; dir/load layer (identical to the IDE build). Read-only for now: D0_SAVE/DELETE
; map to fs_load_none; writes (C_SDWRITE) are a later phase.
;
; M4 command protocol (mirrors 1984 src/m4.c + the real board):
;   * write the packet [count][cmd_lo][cmd_hi=#43][params...] one byte at a time
;     to the DATAPORT (any I/O addr with high byte #FE/#FF), then
;   * strobe the ACKPORT (write any value to an addr with high byte #FC) - the M4
;     executes and stages the response in its bus_mem, and
;   * read the response from #E800.. - which is bus-bypassed onto the expansion
;     bus ONLY while M4ROM (expansion slot 6) is the selected upper ROM. GEOBENCH
;     already runs with the upper ROM enabled (#7F85 steady state, see screen.asm),
;     so we just select slot 6 (#DF00=6), read, and reselect AMSDOS (#DF00=7).
;   C_SDREAD response: #E803 = status (0=OK), #E804.. = 512 sector bytes.
; ---------------------------------------------------------------------------

M4_DATA         equ   #FE00        ; DATAPORT  (exact port M4ROM uses, low byte #00 matters on HW)
M4_ACK          equ   #FC00        ; ACKPORT   (write = execute; the board holds the bus until done)
M4_RESP         equ   #E800        ; rom_response buffer (mapped while M4ROM/slot 6 is selected)
M4_ROMNUM       equ   6            ; M4ROM expansion slot (auto-loaded by the M4 firmware)
M4C_SDREAD      equ   #14          ; C_SDREAD command low byte (high byte always #43)

; fsm4_read_sector: the fs_read_sector body for STORAGE_M4. Reads the 24/32-bit LBA
; staged in lba_tmp into fs_secbuf via one C_SDREAD. Returns A = M4 status (0 = OK);
; the FAT core ignores the return (it trusts fs_secbuf), matching the IDE primitive.
;
; Mirrors M4ROM's own command flow EXACTLY (M4ROM.s, Duke): M4ROM executes FROM slot 6,
; so the M4 board sees its ROM selected the whole time - the emulator ignores the slot,
; but real hardware only services the DATAPORT/ACKPORT + maps rom_response while slot 6
; is the active upper ROM. So we select slot 6 across the WHOLE transaction (send + ack +
; read), write the leading #00 lead byte M4ROM writes (NOT a length), and let the ACKPORT
; OUT block - the board asserts a bus wait-state until the SD read finishes, so no software
; poll/NMI is needed (M4ROM reads rom_response immediately after the strobe, with no wait).
fsm4_read_sector
                di                            ; no IRQ/NMI may see slot 6 paged over #C000 mid-read
                ld    bc,#7F85               ; upper ROM ON + lower ROM OFF (GEOBENCH steady state,
                out   (c),c                  ;  keeps low RAM lba_tmp/fs_secbuf visible - #152 lesson)
                ld    bc,#DF00
                ld    a,M4_ROMNUM
                out   (c),a                  ; select M4ROM (slot 6) for the whole command
                ld    bc,M4_DATA             ; --- stream the C_SDREAD packet to the DATAPORT ---
                out   (c),c                  ; [0] #00 lead byte (M4ROM writes this, not a length)
                ld    a,M4C_SDREAD
                out   (c),a                  ; [1] cmd lo
                ld    a,#43
                out   (c),a                  ; [2] cmd hi
                ld    a,(lba_tmp)
                out   (c),a                  ; [3] LBA 7-0
                ld    a,(lba_tmp+1)
                out   (c),a                  ; [4] LBA 15-8
                ld    a,(lba_tmp+2)
                out   (c),a                  ; [5] LBA 23-16
                ld    a,(lba_tmp+3)
                out   (c),a                  ; [6] LBA 31-24
                ld    a,1
                out   (c),a                  ; [7] sector count = 1
                ld    bc,M4_ACK              ; --- strobe ACK: BLOCKS (board bus-hold) until done ---
                out   (c),c                  ; (value #00 = C, as M4ROM does)
                ld    a,(M4_RESP+3)          ; response status (ready now - the strobe blocked)
                push  af
                ld    hl,M4_RESP+4           ; copy the 512 sector bytes out of the response buffer
                ld    de,fs_secbuf
                ld    bc,512
                ldir
                ld    bc,#DF00
                ld    a,7
                out   (c),a                  ; reselect AMSDOS (upper ROM stays ON = steady state)
                pop   af                      ; A = status (0 = OK)
                ei
                ret

; fsm4_present (D0_PRESENT): probe the M4 SD by reading LBA 0 and checking the MBR
; boot signature. Doubles as the transport smoke test (a register-readback probe
; can't work - m4_dataport_read always returns "ready"/0). CF set = card present.
fsm4_present
                xor   a                       ; lba_tmp = 0 (the MBR / boot sector)
                ld    (lba_tmp),a
                ld    (lba_tmp+1),a
                ld    (lba_tmp+2),a
                ld    (lba_tmp+3),a
                call  fsm4_read_sector        ; A = status, fs_secbuf = LBA 0
                or    a
                jr    nz,fm4p_no              ; M4 reported a read error
                ld    a,(fs_secbuf+510)       ; #55 #AA boot signature
                cp    #55
                jr    nz,fm4p_no
                ld    a,(fs_secbuf+511)
                cp    #AA
                jr    nz,fm4p_no
                scf                            ; CF = present + readable
                ret
fm4p_no         or    a
                ret

; Reuse the IDE FAT backend wholesale: it brings the shared FAT core (fs_read_sector
; now dispatches to fsm4_read_sector via the STORAGE_M4 arm in fs_fat32_core.asm),
; the fside_* dir/load layer, and the shared FAT/sysdir state + navigation
; (fs_sys_resolve, fs_sysdir_enter/leave, fs_mounted, fs_dir_stack, ...) that fs.asm
; and the kernel depend on. Its IDE-only bits - the FS_IDE_* port equates,
; fs_ide_present, and fside_save/delete - are unused on M4 (D0_PRESENT=fsm4_present,
; D0_SAVE/DELETE=fs_load_none) and assemble as harmless dead code.
                include "fs_ide_fat.asm"
