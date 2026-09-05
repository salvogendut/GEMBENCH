; #68 hardware adapter only, not a public filesystem/owner implementation.
; Protocol audited against 56478578 lib/fs_m4.asm, kernel/modules/m4save.asm
; and M4ROM.s send_command/char_in/fwrite. No firmware calls or implicit EI.
;
; HL -> 16-byte record in mapped primary [4000,7F00), BC=16.
; op(1 read-at,2 replace), version=1, path_ptr:u16, path_bytes:u8,
; reserved=0, buffer:u16, count:u16<=128, read_offset:u32, reserved:u16=0.
; Path includes the final NUL, 3..64 bytes, starts '/', no embedded NUL or
; control/backslash bytes. Namespace/permission policy belongs above this gate.
; Zero read validates path but does no I/O; zero replace creates an empty file.
; Zero count does not access/validate buffer. Replace requires offset zero.
; A=status (0 OK,1 short/EOF,2 argument,3 I/O,4 protocol,5 busy,6 context,
; 7 offline). DE=actual on OK/EOF, otherwise zero. Other registers volatile.
; Reads copy out only after a successful close; writes are NOT transactional.
; Uncertain open/close poisons the adapter until explicit backend recovery.
; Preconditions: fixed stack/code, lower ROM off, mode 0..2, truthful hardware
; shadows, M4 NMI disabled at takeover. Shared scratch is serialized with DI.
storage_gate
                ld a,i
                push af
                di
                ld a,(io_busy)
                or a
                ld a,5
                jp nz,storage_early
                ld a,(io_offline)
                or a
                ld a,7
                jp nz,storage_early
                ld a,(ga_shadow)
                bit 2,a
                ld a,6
                jp z,storage_early
                ld a,(ga_shadow)
                and 3
                cp 3
                ld a,6
                jp z,storage_early
                ld a,(bank_shadow)
                push af
                ld a,(ga_shadow)
                push af
                ld a,(rom_shadow)
                push af
                ld a,1
                ld (io_busy),a
                xor a
                ld (io_status),a
                ld (io_fd),a
                ld (io_actual),a
                ld (io_actual+1),a
                ld a,b
                or a
                jp nz,storage_argument
                ld a,c
                cp 16
                jp nz,storage_argument
                call storage_span
                jp nc,storage_argument
                if FAULT_STORAGE_COPY
                push hl
                ld a,#F7
                call foundation_bank_set
                pop hl
                ld bc,16
                endif
                ld de,request_packet
                ldir
                ld a,(request_packet)
                dec a
                cp 2
                jp nc,storage_argument
                ld a,(request_packet+1)
                cp 1
                jp nz,storage_argument
                ld a,(request_packet+5)
                ld hl,(request_packet+14)
                or h
                or l
                jp nz,storage_argument
                ld hl,(request_packet+8)
                ld a,h
                or a
                jp nz,storage_argument
                ld a,l
                cp 129
                jp nc,storage_argument
                ld a,(request_packet+4)
                cp 3
                jp c,storage_argument
                cp 65
                jp nc,storage_argument
                ld c,a
                ld b,0
                ld hl,(request_packet+2)
                call storage_span
                jp nc,storage_argument
                ld de,path_buffer
                ldir                        ; copy before any bank replacement
                ld hl,path_buffer
                ld a,(hl)
                cp '/'
                jp nz,storage_argument
                ld a,(request_packet+4)
                dec a
                dec a
                ld b,a
                inc hl
storage_path_chars
                ld a,(hl)
                cp 33
                jp c,storage_argument
                cp 127
                jp nc,storage_argument
                cp 92                       ; backslash
                jp z,storage_argument
                inc hl
                djnz storage_path_chars
                ld a,(hl)
                or a
                jp nz,storage_argument
                ld a,(request_packet)
                cp 2
                jr nz,storage_read_offset
                ld hl,(request_packet+10)
                ld de,(request_packet+12)
                ld a,h
                or l
                or d
                or e
                jp nz,storage_argument
                jr storage_buffer
storage_read_offset
                ld hl,(request_packet+10)
                ld de,(request_packet+8)
                add hl,de
                ld hl,(request_packet+12)
                ld de,0
                adc hl,de
                jp c,storage_argument       ; offset + capacity must not wrap
storage_buffer
                ld bc,(request_packet+8)
                ld a,b
                or c
                jr z,storage_staged
                ld hl,(request_packet+6)
                call storage_span
                jp nc,storage_argument
                ld a,(request_packet)
                cp 2
                jr nz,storage_staged
                ld de,transfer_buffer
                ldir                        ; stage write while caller still mapped
storage_staged
                ld a,(request_packet)
                cp 1
                jr nz,storage_start
                ld a,(request_packet+8)
                or a
                jp z,storage_finish         ; empty read: no command/handle
storage_start
                ld a,#F7
                call foundation_bank_set   ; deliberately poison caller aperture
                ld a,6
                call storage_rom_set
                ld a,(ga_shadow)
                and #F7                     ; upper on, preserve lower/mode bits
                call storage_ga_set
                ld a,1                      ; C_OPEN
                call storage_command
                ld a,(request_packet)
                cp 2
                ld a,#81                    ; read + dynamic descriptor
                jr nz,storage_open_mode
                ld a,#8A                    ; write + create/truncate + dynamic
storage_open_mode
                ld (hl),a
                inc hl
                ex de,hl
                ld hl,path_buffer
                ld a,(request_packet+4)
                ld c,a
                ld b,0
                ldir
                ex de,hl
                call storage_send
                jp nz,storage_open_uncertain
                ld a,(response_buffer)
                cp 4
                jp nz,storage_open_uncertain
                ld a,(response_buffer+4)
                or a
                jp nz,storage_io_error
                ld a,(response_buffer+3)
                cp 3
                jp c,storage_open_uncertain
                cp #FF
                jp z,storage_open_uncertain
                ld (io_fd),a
                ld a,(request_packet)
                cp 2
                jp z,storage_write
                ld a,5                      ; C_SEEK (32-bit absolute)
                call storage_command_fd
                ex de,hl
                ld hl,request_packet+10
                ld bc,4
                ldir
                ex de,hl
                call storage_send_status
                jp nz,storage_close_result
                ld a,#12                    ; C_READ2 returns actual, no header skip
                call storage_command_fd
                ld a,(request_packet+8)
                ld (hl),a
                inc hl
                ld (hl),0
                inc hl
                call storage_send
                jp nz,storage_close_result
                ld a,(response_buffer+3)
                or a
                jr z,storage_read_header
                cp 20                       ; M4ROM's decimal EOF, not hex 20
                jp nz,storage_read_error
storage_read_header
                ld a,(response_buffer)
                cp 7
                jp c,storage_read_protocol
                ld hl,(response_buffer+4)
                ld a,h
                or a
                jp nz,storage_read_protocol
                ld a,(request_packet+8)
                cp l
                jp c,storage_read_protocol
                ld a,l
                add a,7                     ; fixed response length <= 135
                ld hl,response_buffer
                cp (hl)
                jp nz,storage_read_protocol
                ld hl,(response_buffer+4)
                ld (io_actual),hl
                ld a,(request_packet+8)
                cp l
                ld a,0
                jr z,storage_read_copy
                inc a                       ; short/EOF by actual count, not status
storage_read_copy
                ld (io_status),a
                ld b,h
                ld c,l
                ld a,b
                or c
                jr z,storage_close
                ld hl,response_buffer+8
                ld de,transfer_buffer
                ldir
                jr storage_close
storage_write
                ld a,(request_packet+8)
                or a
                jr z,storage_close_result   ; open+close creates the empty file
                ld a,3                      ; C_WRITE: fd then payload, no count
                call storage_command_fd
                ex de,hl
                ld hl,transfer_buffer
                ld a,(request_packet+8)
                ld c,a
                ld b,0
                ldir
                ex de,hl
                call storage_send_status
                jr nz,storage_close_result
                ld hl,(request_packet+8)
                ld (io_actual),hl
                jr storage_close_result
storage_read_error
                ld a,3
                jr storage_close_result
storage_read_protocol
                ld a,4
storage_close_result
                ; Preserve first failure/EOF across cleanup; CLOSE failure must
                ; never turn a failed read/write into success or publish data.
                or a
                jr z,storage_close
                ld (io_status),a
storage_close
                ld a,4
                call storage_command_fd
                call storage_send_status
                jr z,storage_closed
                push af
                ld a,1
                ld (io_offline),a
                ld a,(io_status)
                cp 2
                jr nc,storage_close_first
                pop af
                ld (io_status),a
                jr storage_finish
storage_close_first
                pop af
                jr storage_finish
storage_closed
                xor a
                ld (io_fd),a
                jr storage_finish
storage_open_uncertain
                ld a,1
                ld (io_offline),a           ; unknown handle: do not guess/close fd
                ld a,4
                jr storage_error
storage_io_error
                ld a,3
                jr storage_error
storage_argument
                ld a,2
storage_error
                ld (io_status),a
storage_finish
                pop af
                call storage_rom_set
                pop af
                if FAULT_STORAGE_ROM
                xor 8                      ; injected bad upper-ROM restoration
                endif
                call storage_ga_set
                pop af
                if FAULT_STORAGE_BANK
                ld a,#F7                   ; injected bad caller restoration
                endif
                call foundation_bank_set
                ld de,0
                ld a,(io_status)
                cp 2
                jr nc,storage_return
                ld de,(io_actual)
                ld a,(request_packet)
                cp 1
                jr nz,storage_return
                ld a,d
                or e
                jr z,storage_return
                ld b,d
                ld c,e
                push de
                ld hl,transfer_buffer
                ld de,(request_packet+6)
                ldir                        ; only with caller page/ROM restored
                pop de
storage_return
                xor a
                ld (io_busy),a
                ld a,(io_status)
storage_early
                ; Early failures do not touch another caller's private scratch.
                cp 2
                jr c,storage_return_iff
                ld de,0
storage_return_iff
                pop bc                     ; C holds saved F (P/V = caller IFF2)
                bit 2,c
                ret z
                ei
                ret

; HL+BC whole nonempty span, carry on valid, HL/BC preserved.
storage_span
                ld a,h
                cp #40
                jr c,storage_span_bad
                push hl
                add hl,bc
                jr c,storage_span_over
                ld a,h
                cp #7F
                jr c,storage_span_ok
                jr nz,storage_span_over
                ld a,l
                or a
                jr nz,storage_span_over
storage_span_ok
                pop hl
                scf
                ret
storage_span_over
                pop hl
storage_span_bad
                or a
                ret
storage_ga_set
                ld (ga_shadow),a
                ld bc,#7F00
                out (c),a
                ret
storage_rom_set
                ld (rom_shadow),a
                ld bc,#DF00
                out (c),a
                ret

storage_command_fd
                call storage_command
                ld a,(io_fd)
                ld (hl),a
                inc hl
                ret
storage_command
                ld (command_buffer+1),a
                ld a,#43
                ld (command_buffer+2),a
                ld hl,command_buffer+3
                ret
storage_send_status
                call storage_send
                ret nz
                ld a,(response_buffer)
                cp 3
                jp nz,storage_protocol
                ld a,(response_buffer+3)
                or a
                ret z
                ld a,3
                or a
                ret
storage_send
                ld de,command_buffer+1
                or a
                sbc hl,de
                ld a,h
                or a
                jr nz,storage_protocol
                ld a,l
                cp 3
                jr c,storage_protocol
                cp 132
                jr nc,storage_protocol
                ld (command_buffer),a
                call storage_command_fault ; diagnostic invalid-fd wire fixtures
                ld a,(command_buffer)
                inc a
                ld d,a
                ld hl,command_buffer
                ld bc,#FE00
storage_send_loop
                inc b
                outi                        ; M4ROM-sized packet, exact FE00 port
                dec d
                jr nz,storage_send_loop
                ld bc,#FC00
                out (c),c                   ; bus hold: no software timeout possible
                ld hl,(command_count)
                inc hl
                ld (command_count),hl
                ld hl,#E800
                ld de,response_buffer
                ld bc,3
                ldir                        ; header only, then bounded payload
                push hl
                push de
                call storage_header_fault  ; diagnostic malformed header fixtures
                pop de
                pop hl
                ld a,(response_buffer)
                cp 3
                jr c,storage_protocol
                cp 136
                jr nc,storage_protocol
                sub 2
                ld c,a
                ld b,0
                ldir
                call storage_response_fault ; diagnostic hook, no device mutation
                ld a,(command_buffer+1)
                ld hl,response_buffer+1
                cp (hl)
                jr nz,storage_protocol
                inc hl
                ld a,(hl)
                cp #43
                jr nz,storage_protocol
                ld a,(response_buffer)
                cp 3
                jr c,storage_protocol
                cp 136
                jr nc,storage_protocol
                xor a
                ret
storage_protocol
                ld a,4
                or a
                ret
storage_driver_end
