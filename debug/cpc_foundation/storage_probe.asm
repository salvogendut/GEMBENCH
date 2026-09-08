; Step 3C: runtime M4 only. Boot with firmware, then explicit takeover.
                include "layout.inc"
                ifndef FAULT_STORAGE_BANK
FAULT_STORAGE_BANK equ 0
                endif
                ifndef FAULT_STORAGE_ROM
FAULT_STORAGE_ROM equ 0
                endif
                ifndef FAULT_STORAGE_COPY
FAULT_STORAGE_COPY equ 0
                endif
                org FOUNDATION_ORG
probe_start
                ld a,1
                call #BC0E
                di
                ld sp,main_stack_top
                ld a,#8D
                call storage_ga_set
                ld a,#C0
                call foundation_bank_set
                im 1
                ld a,#C3
                ld (#0038),a
                ld hl,storage_irq
                ld (#0039),hl
                ; NMI disabled explicitly before runtime I/O. This command's
                ; ACK disables NMI; no firmware or IRQ ROM routine is called.
                ld a,6
                call storage_rom_set
                ld a,#85
                call storage_ga_set
                ld a,#19
                call storage_command
                ld (hl),1
                inc hl
                call storage_send           ; NMIOFF has no payload; ignore status
                ld a,#8D
                call storage_ga_set
                ld hl,#C000
storage_pixels
                ld a,h
                xor l
                ld (hl),a
                inc hl
                ld a,h
                or l
                jr nz,storage_pixels
                ld a,#C4
storage_seed_page
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#A9
                ldir
                ld a,(bank_shadow)
                inc a
                cp #F8
                jr z,storage_seed_done
                ld b,a
                and 7
                ld a,b
                jr nz,storage_seed_page
                add a,4
                jr storage_seed_page
storage_seed_done
                ld hl,trace_guard_low
                ld de,trace_guard_low+1
                ld bc,15
                ld (hl),#D7
                ldir
                ld hl,trace_guard_high
                ld de,trace_guard_high+1
                ld bc,15
                ld (hl),#D7
                ldir
                ld a,1
                ld (phase),a
storage_round_start
                xor a
                ld (case_index),a
                ld hl,storage_cases
                ld (case_pointer),hl
                ld hl,trace_records
                ld (trace_pointer),hl
storage_case_next
                ld ix,(case_pointer)
                ld a,(ix+24)
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#5A
                ldir
                ld hl,(case_pointer)
                ld de,#4000
                ld a,(ix+18)
                cp #F0
                jr nz,storage_seed_record
                ld a,(ix+19)
                cp #7E
                jr nz,storage_seed_record
                ld de,#7EF0
storage_seed_record
                ld bc,16
                ldir
                ld l,(ix+32)
                ld h,(ix+33)
                ld c,(hl)
                ld b,0
                inc hl
                ld e,(ix+26)
                ld d,(ix+27)
                ldir
                ld hl,storage_payload
                ld e,(ix+28)
                ld d,(ix+29)
                ld bc,128
                ldir
                ld a,(ix+17)
                ld (io_fault),a
                ld a,(ix+25)
                ld (io_busy),a
                ld a,(ix+23)
                call storage_rom_set
                ld a,(ix+22)
                call storage_ga_set
                ld hl,#C000
                ld de,observed_rom
                ld bc,8
                ldir                        ; CPU-visible ROM/RAM, not just shadow
                ld hl,(command_count)
                ld (commands_before),hl
                ld l,(ix+18)
                ld h,(ix+19)
                ld c,(ix+20)
                ld b,(ix+21)
                ld a,(rounds_done)
                and 1
                jr z,storage_call_di
                ei
storage_call_di
                call storage_gate
                ld (observed_status),a
                ld (observed_actual),de
                ld a,i
                jp po,storage_return_di
                ld a,1
                jr storage_record_iff
storage_return_di
                xor a
storage_record_iff
                ld (observed_iff),a
                di
                ld ix,(case_pointer)
                ld a,(rounds_done)
                and 1
                ld hl,observed_iff
                cp (hl)
                ld a,10
                jp nz,probe_fail
                ld a,(observed_status)
                cp (ix+16)
                ld a,8
                jp nz,probe_fail
                ld a,(bank_shadow)
                cp (ix+24)
                ld a,9
                jp nz,probe_fail
                ld a,(#4020)
                cp #5A                      ; physical page, not shadow alone
                ld a,9
                jp nz,probe_fail
                ld a,(ga_shadow)
                cp (ix+22)
                ld a,12
                jp nz,probe_fail
                ld a,(rom_shadow)
                cp (ix+23)
                ld a,12
                jp nz,probe_fail
                ld hl,#C000
                ld de,observed_rom
                ld b,8
storage_check_rom
                ld a,(de)
                cp (hl)
                ld a,12
                jp nz,probe_fail
                inc hl
                inc de
                djnz storage_check_rom
                ld a,(io_busy)
                cp (ix+25)
                ld a,13
                jp nz,probe_fail
                ld a,(io_offline)
                cp (ix+38)
                ld a,14
                jp nz,probe_fail
                ld hl,(observed_actual)
                ld e,(ix+34)
                ld d,(ix+35)
                or a
                sbc hl,de
                ld a,15
                jp nz,probe_fail
                ld hl,(command_count)
                ld de,(commands_before)
                or a
                sbc hl,de
                ld (observed_commands),hl
                ld e,(ix+36)
                ld d,(ix+37)
                or a
                sbc hl,de
                ld a,16
                jp nz,probe_fail
                ld hl,0
                add hl,sp
                ld de,main_stack_top
                or a
                sbc hl,de
                ld a,11
                jp nz,probe_fail
                ; Every round validates control state. Full returned buffers
                ; from the last round survive in fixed low RAM for the HOST.
                call storage_capture
                ld a,(rounds_done)
                and 1
                jr z,storage_irq_checked
                ei
                halt
                di
storage_irq_checked
                xor a
                ld (io_busy),a             ; release fixture's injected busy latch
                ld hl,(request_count)
                inc hl
                ld (request_count),hl
                ld hl,(case_pointer)
                ld de,storage_case_size
                add hl,de
                ld (case_pointer),hl
                ld hl,case_index
                inc (hl)
                ld a,(hl)
                cp storage_case_count
                jp nz,storage_case_next
                ld hl,rounds_done
                inc (hl)
                ld a,(hl)
                cp storage_rounds
                jp nz,storage_round_start
                ld a,#C0
                call foundation_bank_set
                ld a,#8D
                call storage_ga_set
                ld a,7
                call storage_rom_set
                ld hl,main_stack
                call stack_used
                ld (main_stack_used),hl
                ld hl,irq_stack
                call stack_used
                ld (irq_stack_used),hl
                ld (final_sp),sp
                ld a,#A5
                ld (phase),a
probe_stop
                di
                halt
                jr probe_stop
probe_fail
                ld (failure),a
                ld a,#FF
                ld (phase),a
                jr probe_stop

storage_capture
                ld hl,(trace_pointer)
                ld a,(observed_status)
                ld (hl),a
                inc hl
                ld a,(observed_iff)
                ld (hl),a
                inc hl
                ld a,(bank_shadow)
                ld (hl),a
                inc hl
                ld a,(ga_shadow)
                ld (hl),a
                inc hl
                ld a,(rom_shadow)
                ld (hl),a
                inc hl
                ld a,(io_fd)
                ld (hl),a
                inc hl
                ld a,(io_offline)
                ld (hl),a
                inc hl
                ld a,(io_busy)
                ld (hl),a
                inc hl
                ex de,hl
                ld hl,observed_actual
                ld bc,4
                ldir
                ld l,(ix+30)
                ld h,(ix+31)
                ld bc,128
                ldir
                ld hl,#7F00
                ld bc,4
                ldir
                ld (trace_pointer),de
                ret

; These two fixtures elicit a REAL bad-fd response without losing the live fd
; retained for CLOSE. Other faults mutate only the resident response copy.
storage_command_fault
                ld a,(io_fault)
                cp 12
                jr z,storage_wire_read
                cp 13
                ret nz
                ld a,(command_buffer+1)
                cp 3
                ret nz
                jr storage_wire_invalid
storage_wire_read
                ld a,(command_buffer+1)
                cp #12
                ret nz
storage_wire_invalid
                xor a
                ld (command_buffer+3),a
                ret
storage_header_fault
                ld a,(command_buffer+1)
                cp #12
                ret nz
                ld a,(io_fault)
                cp 2
                jr z,storage_fault_oversize
                cp 9
                jr z,storage_fault_empty
                cp 10
                jr z,storage_fault_length
                cp 11
                ret nz
                ld a,#42
                ld (response_buffer+2),a
                ret
storage_fault_oversize
                ld a,136
                ld (response_buffer),a
                ret
storage_fault_empty
                ld a,2
                ld (response_buffer),a
                ret
; Faults mutate the resident COPY only after real M4 I/O. In particular a
; reported write failure need not undo bytes already written to the card.
storage_response_fault
                ld a,(io_fault)
                or a
                ret z
                ld b,a
                ld a,(command_buffer+1)
                cp 1
                jr nz,storage_fault_not_open
                ld a,b
                cp 8
                jr z,storage_fault_echo
                ret
storage_fault_not_open
                cp 4
                jr nz,storage_fault_not_close
                ld a,b
                cp 7
                jr z,storage_fault_error
                ret
storage_fault_not_close
                cp 5
                jr nz,storage_fault_not_seek
                ld a,b
                cp 6
                jr z,storage_fault_error
                ret
storage_fault_not_seek
                cp 3
                jr nz,storage_fault_not_write
                ld a,b
                cp 5
                jr z,storage_fault_error
                ret
storage_fault_not_write
                cp #12
                ret nz
                ld a,b
                cp 1
                jr z,storage_fault_echo
                cp 3
                jr z,storage_fault_count
                cp 4
                jr z,storage_fault_error
                ret
storage_fault_echo
                ld hl,response_buffer+1
                inc (hl)
                ret
storage_fault_length
                ld a,6
                ld (response_buffer),a
                ret
storage_fault_count
                ld hl,129
                ld (response_buffer+4),hl
                ret
storage_fault_error
                ld a,#E1
                ld (response_buffer+3),a
                ret

storage_irq
                ld (interrupted_sp),sp
                ld sp,irq_stack_top
                push af
                push hl
                ld hl,(irq_count)
                inc hl
                ld (irq_count),hl
                pop hl
                pop af
                ld sp,(interrupted_sp)
                ei
                reti
stack_used
                ld de,FOUNDATION_STACK_SIZE
storage_stack_scan
                ld a,(hl)
                cp #A6
                jr nz,storage_stack_found
                inc hl
                dec de
                ld a,d
                or e
                jr nz,storage_stack_scan
storage_stack_found
                ex de,hl
                ret
                include "bank.asm"
                include "storage_driver.asm"
                include "storage_vectors.inc"
code_end
                assert code_end <= FOUNDATION_STATE, "storage code/state overlap"
trace_guard_low equ #1000
trace_records equ trace_guard_low+16
trace_guard_high equ trace_records+storage_case_count*144
                assert trace_guard_high+16 <= #4000, "storage trace enters banked page"
                org FOUNDATION_STATE
state_start
magic           db "CPF3C",1
phase           db 0
failure         db 0
bank_shadow     db #C0
ga_shadow       db #8D
rom_shadow      db 7
rounds_done     db 0
case_index      db 0
case_pointer    dw 0
trace_pointer   dw 0
request_count   dw 0
command_count   dw 0
commands_before dw 0
irq_count       dw 0
observed_status db 0
observed_iff    db 0
observed_actual dw 0
observed_commands dw 0
interrupted_sp  dw 0
final_sp        dw 0
main_stack_used dw 0
irq_stack_used  dw 0
io_busy         db 0
io_offline      db 0
io_status       db 0
io_fd           db 0
io_actual       dw 0
io_fault        db 0
observed_rom    ds 8,0
request_guard_low ds 16,#D7
request_packet  ds 16,0
request_guard_high ds 16,#D7
state_end
                assert state_end <= #9900, "storage state overflow"
                org FOUNDATION_IRQ_STACK-16
irq_guard_low   ds 16,#D7
irq_stack       ds FOUNDATION_STACK_SIZE,#A6
irq_stack_top
irq_guard_high  ds 16,#D7
                org FOUNDATION_MAIN_STACK-16
main_guard_low  ds 16,#D7
main_stack      ds FOUNDATION_STACK_SIZE,#A6
main_stack_top
main_guard_high ds 16,#D7
                assert $ <= #9D30, "stack/storage buffer overlap"
                org #9D30
path_guard_low ds 16,#D7
path_buffer ds 64,0
path_guard_high ds 16,#D7
transfer_guard_low ds 16,#D7
transfer_buffer ds 128,0
transfer_guard_high ds 16,#D7
response_guard_low ds 16,#D7
response_buffer ds 136,0
response_guard_high ds 16,#D7
command_guard_low ds 16,#D7
command_buffer ds 132,0
command_guard_high ds 16,#D7
probe_end
                assert probe_end <= #A000, "storage probe enters firmware workspace"
                save "FOUND.RAW",probe_start,probe_end-probe_start
