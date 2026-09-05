; CPC restart #65, package 3A: boot through M4, then own the hardware.
; Deliberately no desktop, shared policy replacements or universal APP loader.
                include "layout.inc"
                ifndef FAULT_RESTORE
FAULT_RESTORE equ 0
                endif
                ifndef FAULT_REGISTER
FAULT_REGISTER equ 0
                endif
                ifndef FAULT_STACK
FAULT_STACK equ 0
                endif
                org FOUNDATION_ORG
probe_start
                ld a,1
                call #BC0E             ; SCR SET MODE, last firmware call
                di
                ld sp,main_stack_top
                ld bc,#7F00
                ld a,#8D               ; Mode 1, BOTH ROMs off
                out (c),a
                ld a,#C0
                call foundation_bank_set
                im 1
                ld a,#C3
                ld (#0038),a
                ld hl,foundation_irq
                ld (#0039),hl
                ld a,1
                ld (phase),a

                ; Pixel RAM is never scratch. Every byte has a known pattern,
                ; including CPC raster gaps, so host checks catch stray writes.
                ld hl,FOUNDATION_SCREEN
screen_fill
                ld a,h
                xor l
                ld (hl),a
                inc hl
                ld a,h
                or l
                jr nz,screen_fill

                ; Seed ALL bytes in each of 29 distinct physical pages. The
                ; final SNA checker verifies the entire 464K, not just markers.
                ld ix,page_tags
seed_next
                ld a,(ix+0)
                or a
                jr z,seed_done
                call foundation_bank_set
                ld hl,FOUNDATION_WINDOW
seed_byte
                ld a,(bank_shadow)
                xor h
                xor l
                ld (hl),a
                inc hl
                ld a,h
                cp #80
                jr nz,seed_byte
                inc ix
                jr seed_next
seed_done
                ld a,2
                ld (phase),a
round_next
                xor a
                ld (page_index),a
page_next
                ld a,(page_index)
                ld e,a
                ld d,0
                ld hl,page_tags
                add hl,de
                ld a,(hl)
                ld (expected_bank),a
                call foundation_bank_set
                call check_samples
                call exercise_irq
                ld a,(failure)
                or a
                jp nz,probe_fail        ; propagate an IRQ-side mapping failure
                ld a,(bank_shadow)
                ld hl,expected_bank
                cp (hl)
                ld a,2                 ; bad restored bank/shadow
                jp nz,probe_fail
                call check_samples     ; verify actual hardware mapping too
                ld hl,page_checks
                inc (hl)
                jr nz,checks_no_carry
                inc hl
                inc (hl)
checks_no_carry
                ld hl,page_index
                inc (hl)
                ld a,(hl)
                cp page_count
                jr nz,page_next
                ld hl,rounds_done
                inc (hl)
                ld a,(hl)
                cp FOUNDATION_ROUNDS
                jr nz,round_next

                ld a,#C0
                call foundation_bank_set
                ; Invalid requests must not map vectors, code or framebuffer,
                ; and must return failure without enabling interrupts.
                ld ix,invalid_tags
invalid_next
                ld a,(ix+0)
                call foundation_bank_set
                ld a,4
                jp c,probe_fail
                ld a,(bank_shadow)
                cp #C0
                ld a,4
                jp nz,probe_fail
                ld a,i
                ld a,5
                jp pe,probe_fail        ; IFF2 must still be disabled
                inc ix
                ld a,ixl
                cp invalid_end&#FF
                jr nz,invalid_next

                ; Store observed stack footprint (sentinel-based lower bound)
                ; and inspect BOTH guards on both stacks before publishing PASS.
                if FAULT_STACK
                xor a
                ld (main_guard_low),a
                endif
                ld hl,irq_guard_low
                call check_guard
                ld hl,irq_guard_high
                call check_guard
                ld hl,main_guard_low
                call check_guard
                ld hl,main_guard_high
                call check_guard
                ld hl,irq_stack
                call stack_used
                ld (irq_stack_used),hl
                ld hl,main_stack
                call stack_used
                ld (main_stack_used),hl
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

; Sample start of every 256-byte block plus end of page in every round.
; Host checks every byte in every page after completion.
check_samples
                ld hl,FOUNDATION_WINDOW
sample_next
                ld a,(expected_bank)
                xor h
                cp (hl)
                ld a,1
                jp nz,probe_fail
                inc h
                ld a,h
                cp #80
                jr nz,sample_next
                dec hl
                ld a,(expected_bank)
                xor #7F
                xor #FF
                cp (hl)
                ld a,1
                jp nz,probe_fail
                ret

; An IRQ is deliberately delivered with known primary/alternate registers and
; IX/IY. Save the returned values before using any of them. EI/HALT/DI do not
; alter AF, so flags are tested as well as the usual general registers.
exercise_irq
                ld hl,#2468
                push hl
                pop af
                ex af,af'
                ld bc,#3456
                ld de,#4567
                ld hl,#5678
                exx
                ld bc,#6789
                ld de,#789A
                ld ix,#89AB
                ld iy,#9ABC
                ld hl,#1357
                push hl
                pop af
                ld hl,#ABCD
                ei
                halt
                di
                ld (observed+2),bc
                ld (observed+4),de
                ld (observed+6),hl
                ld (observed+8),ix
                ld (observed+10),iy
                push af
                pop hl
                ld (observed),hl
                exx
                ld (observed+14),bc
                ld (observed+16),de
                ld (observed+18),hl
                exx
                ex af,af'
                push af
                pop hl
                ld (observed+12),hl
                ex af,af'
                ld hl,observed
                ld de,expected_registers
                ld b,20
register_next
                ld a,(de)
                cp (hl)
                ld a,3
                jp nz,probe_fail
                inc hl
                inc de
                djnz register_next
                ret

; IM1 pushes PC on the interrupted fixed stack. Switch stacks BEFORE pushing
; our context, with IRQs still disabled. Only this wrapper maps an IRQ page;
; later shared scheduling policy must remain outside this hardware probe.
foundation_irq
                ld (interrupted_sp),sp
                ld sp,irq_stack_top
                push af
                push bc
                push de
                push hl
                push ix
                push iy
                exx
                ex af,af'
                push af
                push bc
                push de
                push hl
                ld a,(bank_shadow)
                push af
                ld a,#F7               ; temporary service page
                call foundation_bank_set
                ld a,(#4000)
                cp #F7^#40
                jr z,irq_mapping_ok
                ld a,6
                ld (failure),a
irq_mapping_ok
                ld hl,irq_count
                inc (hl)
                jr nz,irq_count_ok
                inc hl
                inc (hl)
irq_count_ok
                ld a,(page_index)
                ld e,a
                ld d,0
                ld hl,irq_per_page
                add hl,de
                inc (hl)
                pop af
                if FAULT_RESTORE
                ld a,#C4
                endif
                call foundation_bank_set
                pop hl
                pop de
                pop bc
                pop af
                ex af,af'
                exx
                pop iy
                pop ix
                pop hl
                pop de
                pop bc
                pop af
                if FAULT_REGISTER
                inc bc
                endif
                ld sp,(interrupted_sp)
                ei
                reti

check_guard
                ld b,16
guard_next
                ld a,(hl)
                cp #D7
                ld a,7
                jp nz,probe_fail
                inc hl
                djnz guard_next
                ret
stack_used
                ld de,FOUNDATION_STACK_SIZE
stack_scan
                ld a,(hl)
                cp #A6
                jr nz,stack_found
                inc hl
                dec de
                ld a,d
                or e
                jr nz,stack_scan
stack_found
                ex de,hl
                ret

                include "bank.asm"
page_tags
                db #C0,#C4,#C5,#C6,#C7,#CC,#CD,#CE,#CF
                db #D4,#D5,#D6,#D7,#DC,#DD,#DE,#DF
                db #E4,#E5,#E6,#E7,#EC,#ED,#EE,#EF,#F4,#F5,#F6,#F7
page_count equ $-page_tags
                db 0
invalid_tags
                db #00,#80,#BF,#C1,#C2,#C3,#C8,#F8,#FC,#FF
invalid_end
expected_registers
                dw #1357,#6789,#789A,#ABCD,#89AB,#9ABC
                dw #2468,#3456,#4567,#5678
code_end
                assert code_end <= FOUNDATION_STATE, "probe code/state overlap"
                assert (invalid_tags>>8) == (invalid_end>>8), "invalid table indexing"
                org FOUNDATION_STATE
state_start
magic           db "CPF3A",1
phase           db 0
failure         db 0
bank_shadow     db #C0
expected_bank   db 0
page_index      db 0
rounds_done     db 0
page_checks     dw 0
irq_count       dw 0
interrupted_sp  dw 0
final_sp        dw 0
irq_stack_used  dw 0
main_stack_used dw 0
observed        ds 20,0
irq_per_page    ds page_count,0
state_end
                assert state_end <= FOUNDATION_STATE+#0100, "state overflow"
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
probe_end
                save "FOUND.RAW",probe_start,probe_end-probe_start
