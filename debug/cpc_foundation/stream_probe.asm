; Private #84 transport probe, not a desktop or an application launcher.
; Copy the exact two Notepad segments from one M4 stream to C4/C5, then stop.
; The host checks every byte, untouched tails, code, guards and wire counts.
; Shared admission/seals/call gate integration is a SEPARATE following gate.
                include "../../lib/cpc/production_layout.inc"
                include "stream_fixture.inc"
CPC_FSCTX equ 1
FAULT_STORAGE_BANK equ 0
FAULT_STORAGE_ROM equ 0
FAULT_STORAGE_COPY equ 0
CPC_STREAM_STATE equ #1F00
CPC_STREAM_BUFFER equ #1500
CPC_STREAM_PATH equ #2840
CPC_STREAM_PATH_BYTES equ #2888
probe_remain equ #1F20
probe_dest equ #1F22
probe_count equ #1F24
probe_segment equ #1F26
probe_phase equ CPC_RESULT+6
probe_error equ CPC_RESULT+7
probe_opens equ CPC_RESULT+8
probe_reads equ CPC_RESULT+10
probe_closes equ CPC_RESULT+12

                org #8000
probe_start
                ld a,1
                call #BC0E                  ; final firmware call
                di
                ld sp,#9F00
                ld bc,#7F00
                ld a,#8D
                out (c),a
                ld hl,#0100
                ld de,#0101
                ld bc,#3EFF
                ld (hl),0
                ldir
                ld hl,CPC_MAIN_STACK-16
                ld de,CPC_MAIN_STACK-15
                ld bc,CPC_STACKS_END-(CPC_MAIN_STACK-16)-1
                ld (hl),#D7
                ldir
                ld sp,CPC_MAIN_TOP
                ld a,#8D
                call storage_ga_set
                ld a,#C0
                call foundation_bank_set
                ld a,6
                call storage_rom_set
                ld a,#85
                call storage_ga_set
                ld a,#19                    ; M4 NMI off, no firmware handler
                call storage_command
                ld (hl),1
                inc hl
                call storage_send
                ld a,#8D
                call storage_ga_set
                ld a,7
                call storage_rom_set
                ld hl,probe_magic
                ld de,CPC_RESULT
                ld bc,6
                ldir
                ld hl,probe_path
                ld de,CPC_STREAM_PATH
                ld bc,probe_path_end-probe_path
                ldir
                ld a,probe_path_end-probe_path
                ld (CPC_STREAM_PATH_BYTES),a
                ld hl,#C000
probe_pixels
                ld a,h
                xor l
                ld (hl),a
                inc hl
                ld a,h
                or l
                jr nz,probe_pixels
                ld a,#C4
probe_seed
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#A7
                ldir
                ld a,(bank_shadow)
                inc a
                cp #C6
                jr nz,probe_seed
                ld a,#C4
                call foundation_bank_set
                ld a,#C3
                ld (#0038),a
                ld hl,cpc_irq_entry
                ld (#0039),hl
                ld hl,300
                ld (CPC_HW_DIVIDER),hl
                im 1
                ld a,1
                ld (SCHED_LOCK),a
                ld (probe_phase),a
                ei
                call cpc_stream_open
                or a
                jp nz,probe_fail
                ld hl,APP_PRIMARY_SIZE
                ld (probe_remain),hl
                ld hl,#4000
                ld (probe_dest),hl
probe_read
                ld bc,(probe_remain)
                ld a,b
                cp 2
                jr c,probe_count_ready
                ld bc,512
probe_count_ready
                ld (probe_count),bc
                ld hl,CPC_STREAM_BUFFER
                call cpc_stream_read
                or a
                jp nz,probe_fail
                ld hl,(probe_count)
                or a
                sbc hl,bc
                ld a,8                      ; exact segment was truncated
                jp nz,probe_fail
                ld hl,CPC_STREAM_BUFFER
                ld de,(probe_dest)
                ldir
                ld (probe_dest),de
                ld hl,(probe_remain)
                ld de,(probe_count)
                or a
                sbc hl,de
                ld (probe_remain),hl
                ld a,h
                or l
                jr nz,probe_read
                ld a,(probe_segment)
                or a
                jr nz,probe_eof
                inc a
                ld (probe_segment),a
                ld hl,APP_SECONDARY_SIZE
                ld (probe_remain),hl
                ld hl,#4000
                ld (probe_dest),hl
                di
                ld a,#C5
                call foundation_bank_set
                ei
                jr probe_read
probe_eof
                ld hl,CPC_STREAM_BUFFER
                ld bc,1
                call cpc_stream_read
                or a
                jr nz,probe_fail
                ld a,b
                or c
                ld a,9                      ; unexpected appended byte
                jr nz,probe_fail
                call cpc_stream_close
                or a
                jr nz,probe_fail
                ld a,#A5
                jr probe_finish
probe_fail
                ld (probe_error),a
                call cpc_stream_close      ; idempotent; no guessed descriptor
                ld a,#FF
probe_finish
                di
                ld (probe_phase),a
probe_done
                halt
                jr probe_done
probe_magic     db "CPS84",1
probe_path      db "/GBENCH/NOTEPAD.APP",0
probe_path_end

                include "../../lib/cpc/bank.asm"
                include "../../lib/cpc/m4.asm"
storage_command_fault
                ld a,(command_buffer+1)
                ld hl,probe_opens
                cp 1
                jr z,probe_count_command
                ld hl,probe_reads
                cp #12
                jr z,probe_count_command
                ld hl,probe_closes
                cp 4
                ret nz
probe_count_command
                inc (hl)
                ret nz
                inc hl
                inc (hl)
                ret
storage_header_fault
storage_response_fault
                ret
                include "../../lib/cpc/m4_stream.asm"
                include "../../lib/cpc/irq.asm"
sched_irq_body
                ei                          ; fixed-time IRQ only, never app dispatch
                reti
probe_end
                assert probe_end<=#9A00,"stream diagnostic hits firmware workspace"
                assert APP_PRIMARY_SIZE>0 & APP_PRIMARY_SIZE<=#3F00,"primary bounds"
                assert APP_SECONDARY_SIZE>0 & APP_SECONDARY_SIZE<=#3F00,"secondary bounds"
                save "STREAM.RAW",probe_start,probe_end-probe_start
