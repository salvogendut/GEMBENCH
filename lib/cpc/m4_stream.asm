; Private sequential M4 reader for the shared two-bank package transaction.
; NOT a public FS operation and not enabled in the delivery runtime yet.
;
; open: CPC_STREAM_PATH, CPC_STREAM_PATH_BYTES (including NUL), offset zero.
; read: HL=CPC_STREAM_BUFFER, BC=0..512; A=status, BC=actual (zero on error).
; close: idempotent; A=status. One dynamic OPEN, sequential READ2, one CLOSE;
; never SEEK, reopen, CD, publish a page, or call firmware/application code.
; The caller holds SCHED_LOCK with SCHED_CURRENT=0 for the WHOLE lifetime.
; Every entry restores incoming IFF, GA and ROM; no aperture switch occurs.
; io_busy excludes the ordinary storage/FS gate until close. Uncertain open
; or close poisons io_offline, exactly as the read-at adapter does. An error
; after a partial read may have touched the PRIVATE buffer: no bytes are
; executable/published until package_stream.asm validates and closes them.
;
; Provider supplies fixed lower-RAM state (11 bytes), buffer (512 bytes),
; path (64 bytes), and a path-length byte. The validated loader path is still
; checked here, before touching the device. Existing m4.asm supplies the wire
; protocol and bounded response copying. No production addresses are assumed.
CS_OWNED equ CPC_STREAM_STATE
CS_DEST equ CPC_STREAM_STATE+1
CS_REMAIN equ CPC_STREAM_STATE+3
CS_TOTAL equ CPC_STREAM_STATE+5
CS_CHUNK equ CPC_STREAM_STATE+7
CS_STATUS equ CPC_STREAM_STATE+8
CS_GA equ CPC_STREAM_STATE+9
CS_ROM equ CPC_STREAM_STATE+10
                assert CPC_STREAM_STATE>=#0100,"stream state must remain fixed"
                assert CPC_STREAM_STATE+11<=#4000,"stream state must remain fixed"
                assert CPC_STREAM_BUFFER>=#0100,"stream buffer must remain fixed"
                assert CPC_STREAM_BUFFER+512<=#4000,"stream buffer must remain fixed"
                assert CPC_STREAM_PATH>=#0100,"stream path must remain fixed"
                assert CPC_STREAM_PATH+64<=#4000,"stream path must remain fixed"
                assert CPC_STREAM_PATH_BYTES>=#0100 & CPC_STREAM_PATH_BYTES<#4000,"stream path length must remain fixed"
                assert (CPC_STREAM_BUFFER+512<=CPC_STREAM_STATE)|(CPC_STREAM_STATE+11<=CPC_STREAM_BUFFER),"stream state/buffer overlap"
                assert (CPC_STREAM_PATH+64<=CPC_STREAM_STATE)|(CPC_STREAM_STATE+11<=CPC_STREAM_PATH),"stream state/path overlap"
                assert (CPC_STREAM_PATH+64<=CPC_STREAM_BUFFER)|(CPC_STREAM_BUFFER+512<=CPC_STREAM_PATH),"stream path/buffer overlap"

cpc_stream_open
                ld a,i
                push af
                di
                call cpc_stream_context
                jp nz,cpc_stream_return
                ld a,(io_busy)
                ld hl,CS_OWNED
                or (hl)
                ld a,5
                jp nz,cpc_stream_return
                ld a,(io_offline)
                or a
                ld a,7
                jp nz,cpc_stream_return
                ld a,(CPC_STREAM_PATH_BYTES)
                cp 3
                jp c,cpc_stream_argument
                cp 65
                jp nc,cpc_stream_argument
                dec a
                dec a
                ld b,a
                ld hl,CPC_STREAM_PATH
                ld a,(hl)
                cp '/'
                jp nz,cpc_stream_argument
cpc_stream_path_loop
                inc hl
                ld a,(hl)
                cp 33
                jp c,cpc_stream_argument
                cp 127
                jp nc,cpc_stream_argument
                cp 92
                jp z,cpc_stream_argument
                djnz cpc_stream_path_loop
                inc hl
                ld a,(hl)
                or a
                jp nz,cpc_stream_argument
                ld a,1
                ld (io_busy),a
                xor a
                ld (io_fd),a
                call cpc_stream_rom_enter
                ld a,1
                call storage_command
                ld (hl),#81                 ; read, dynamic descriptor
                inc hl
                ex de,hl
                ld hl,CPC_STREAM_PATH
                ld a,(CPC_STREAM_PATH_BYTES)
                ld c,a
                ld b,0
                ldir
                ex de,hl
                call storage_send
                jr nz,cpc_stream_open_uncertain
                ld a,(response_buffer)
                cp 4
                jr nz,cpc_stream_open_uncertain
                ld a,(response_buffer+4)
                or a
                ld a,3
                jr nz,cpc_stream_disown
                ld a,(response_buffer+3)
                cp 3
                jr c,cpc_stream_open_uncertain
                cp #FF
                jr z,cpc_stream_open_uncertain
                ld (io_fd),a
                ld a,1
                ld (CS_OWNED),a
                xor a
                jp cpc_stream_leave
cpc_stream_open_uncertain
                ld a,1
                ld (io_offline),a
                ld a,4
                jr cpc_stream_disown

cpc_stream_close
                ld a,i
                push af
                di
                call cpc_stream_context
                jp nz,cpc_stream_return
                ld a,(CS_OWNED)
                or a
                jp z,cpc_stream_return      ; never close another caller's fd
                call cpc_stream_rom_enter
                ld a,4
                call storage_command_fd
                call storage_send_status
                jr z,cpc_stream_disown
                push af
                ld a,1
                ld (io_offline),a
                pop af
cpc_stream_disown
                push af
                xor a
                ld (CS_OWNED),a
                ld (io_busy),a
                ld (io_fd),a                 ; offline records any uncertain fd
                pop af
                jp cpc_stream_leave

cpc_stream_open_end
                ifndef CPC_STREAM_SPLIT
                include "m4_stream_read.asm"
                endif
