; Continuation of m4_stream.asm. The private runtime places this read/return
; half in its existing hardware region; standalone fixtures remain contiguous.
cpc_stream_read
                ld a,i
                push af
                di
                call cpc_stream_context
                jp nz,cpc_stream_return
                ld a,(CS_OWNED)
                or a
                ld a,6
                jp z,cpc_stream_return
                ld a,h
                cp CPC_STREAM_BUFFER/256
                jp nz,cpc_stream_argument
                ld a,l
                cp CPC_STREAM_BUFFER&255
                jp nz,cpc_stream_argument
                ld a,b
                cp 2
                jr c,cpc_stream_read_count
                jp nz,cpc_stream_argument
                ld a,c
                or a
                jp nz,cpc_stream_argument
cpc_stream_read_count
                ld (CS_DEST),hl
                ld (CS_REMAIN),bc
                ld hl,0
                ld (CS_TOTAL),hl
                ld a,b
                or c
                jp z,cpc_stream_return
                call cpc_stream_rom_enter
cpc_stream_read_loop
                ld hl,(CS_REMAIN)
                ld a,h
                or a
                ld a,128
                jr nz,cpc_stream_read_chunk
                cp l
                jr c,cpc_stream_read_chunk
                ld a,l
cpc_stream_read_chunk
                ld (CS_CHUNK),a
                ld a,#12                    ; READ2, actual count and EOF status
                call storage_command_fd
                ld a,(CS_CHUNK)
                ld (hl),a
                inc hl
                ld (hl),0
                inc hl
                call storage_send
                jp nz,cpc_stream_leave
                ld a,(response_buffer+3)
                or a
                jr z,cpc_stream_read_header
                cp 20                       ; decimal M4 EOF
                ld a,3
                jp nz,cpc_stream_leave
cpc_stream_read_header
                ld a,(response_buffer)
                cp 7
                jr c,cpc_stream_read_protocol
                ld bc,(response_buffer+4)
                ld a,b
                or a
                jr nz,cpc_stream_read_protocol
                ld a,(CS_CHUNK)
                cp c
                jr c,cpc_stream_read_protocol
                ld a,c
                add a,7
                ld hl,response_buffer
                cp (hl)
                jr nz,cpc_stream_read_protocol
                ld a,c
                or a
                jp z,cpc_stream_leave      ; EOF: A=0, accumulated BC on return
                push bc
                ld hl,response_buffer+8
                ld de,(CS_DEST)
                ldir
                ld (CS_DEST),de
                pop bc
                ld hl,(CS_TOTAL)
                add hl,bc
                ld (CS_TOTAL),hl
                ld hl,(CS_REMAIN)
                or a
                sbc hl,bc
                ld (CS_REMAIN),hl
                ld a,(CS_CHUNK)
                cp c
                jr nz,cpc_stream_read_done ; short read terminates, not a reopen
                ld a,h
                or l
                jr nz,cpc_stream_read_loop
cpc_stream_read_done
                xor a
                jr cpc_stream_leave
cpc_stream_read_protocol
                ld a,4
                jr cpc_stream_leave
cpc_stream_argument
                ld a,2
                jr cpc_stream_return

cpc_stream_context
                ld a,(SCHED_LOCK)
                or a
                jr z,cpc_stream_context_bad
                ld a,(SCHED_CURRENT)
                or a
                jr nz,cpc_stream_context_bad
                ld a,(ga_shadow)
                bit 2,a                     ; no lower ROM, truthful mode/shadows
                jr z,cpc_stream_context_bad
                and 3
                cp 3
                jr z,cpc_stream_context_bad
                xor a
                ret
cpc_stream_context_bad
                ld a,6
                or a
                ret
cpc_stream_rom_enter
                ld a,(ga_shadow)
                ld (CS_GA),a
                ld a,(rom_shadow)
                ld (CS_ROM),a
                ld a,6
                call storage_rom_set
                ld a,(ga_shadow)
                and #F7
                jp storage_ga_set
cpc_stream_leave
                ld (CS_STATUS),a
                ld a,(CS_ROM)
                call storage_rom_set
                ld a,(CS_GA)
                call storage_ga_set
                ld a,(CS_STATUS)
cpc_stream_return
                ld bc,0
                or a
                jr nz,cpc_stream_return_iff
                ld bc,(CS_TOTAL)
cpc_stream_return_iff
                pop de
                bit 2,e
                jr z,cpc_stream_return_di
                ei
cpc_stream_return_di
                or a
                ret
cpc_stream_end
