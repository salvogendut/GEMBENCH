; #66: isolated hardware/proposed parameter-boundary proof, not a desktop ABI.
                include "layout.inc"
                ifndef FAULT_CLIP
FAULT_CLIP equ 0
                endif
                ifndef FAULT_CURSOR
FAULT_CURSOR equ 0
                endif
                ifndef FAULT_COPY
FAULT_COPY equ 0
                endif
                org FOUNDATION_ORG
probe_start
                ld a,1
                call #BC0E
                di
                ld sp,main_stack_top
                ld bc,#7F00
                ld a,#8D
                out (c),a
                ld a,#C0
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#5A
                ldir
                ld a,#F7
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#A9              ; poison service page (never parameter data)
                ldir
                ld a,#C0
                call foundation_bank_set
                im 1
                ld a,#C3
                ld (#0038),a
                ld hl,graphics_irq
                ld (#0039),hl
                ld a,1
                ld (phase),a
round_start
                xor a
                ld (pointer_visible),a
                ld (capture_count),a
                ld hl,0
                ld (pointer_saves),hl
                ld (pointer_restores),hl
                ld a,#C4
                ld (capture_native),a
                ld hl,#C000
initial_pixels
                ld a,h
                xor l
                ld (hl),a
                inc hl
                ld a,h
                or l
                jr nz,initial_pixels
                call maybe_capture
                ld hl,graphics_cases
                ld (case_pointer),hl
                xor a
                ld (case_index),a
case_next
                ld hl,(case_pointer)
                ld de,#4000
                ld bc,16
                ldir
                ld hl,#4000
                ld de,#7EF0             ; last valid descriptor boundary fixture
                ld bc,16
                ldir
                ld ix,(case_pointer)
                ld l,(ix+18)
                ld h,(ix+19)
                ld c,(ix+20)
                ld b,(ix+21)
                ld a,(ix+22)
                or a
                jr z,call_disabled
                ei
call_disabled
                call graphics_gate
                ld (observed_status),a
                ld a,i
                jp po,returned_disabled
                ld a,1
                jr returned_iff
returned_disabled
                xor a
returned_iff
                ld (observed_iff),a
                di
                ld ix,(case_pointer)
                cp (ix+22)
                ld a,10
                jp nz,probe_fail
                ld a,(observed_status)
                cp (ix+16)
                ld a,8
                jp nz,probe_fail
                ld a,(bank_shadow)
                cp #C0
                ld a,9
                jp nz,probe_fail
                ld a,(#4020)
                cp #5A
                ld a,9
                jp nz,probe_fail
                ld hl,0
                add hl,sp
                ld de,main_stack_top
                or a
                sbc hl,de
                ld a,11
                jp nz,probe_fail
                ld a,(ix+22)
                or a
                jr z,irq_checked
                ei
                halt
                di
irq_checked
                ld hl,(request_count)
                inc hl
                ld (request_count),hl
                ld a,(ix+17)
                or a
                call nz,maybe_capture
                ld hl,(case_pointer)
                ld de,graphics_case_size
                add hl,de
                ld (case_pointer),hl
                ld hl,case_index
                inc (hl)
                ld a,(hl)
                cp graphics_case_count
                jp nz,case_next
                ld hl,rounds_done
                inc (hl)
                ld a,(hl)
                cp FOUNDATION_ROUNDS
                jp nz,round_start
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

; Last-round framebuffer snapshots occupy distinct expansion pages C4..F6.
; The F7 poison/service page is never used for captures. Nothing is stored in
; raster gaps: the HOST sees every gap byte alongside all displayed pixels.
maybe_capture
                ld a,(rounds_done)
                cp FOUNDATION_ROUNDS-1
                ret nz
                ld a,(capture_native)
                call foundation_bank_set
                ld hl,#C000
                ld de,#4000
                ld bc,#4000
                ldir
                ld a,#C0
                call foundation_bank_set
                ld a,(capture_count)
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,trace_records
                add hl,de
                ex de,hl
                ld hl,pointer_saves
                ld bc,4
                ldir
                ld hl,capture_count
                inc (hl)
                ld a,(capture_native)
                inc a
                ld b,a
                and 7
                ld a,b
                jr nz,capture_tag_ok
                add a,4
capture_tag_ok
                ld (capture_native),a
                ret

graphics_irq
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
                include "graphics_gate.asm"
                include "graphics_driver.asm"
                include "graphics_vectors.inc"
code_end
                assert code_end <= FOUNDATION_STATE, "graphics code/state overlap"
                assert graphics_capture_count <= 27, "capture pages overlap service page"
                org FOUNDATION_STATE
state_start
magic           db "CPF3B",1
phase           db 0
failure         db 0
bank_shadow     db #C0
rounds_done     db 0
case_index      db 0
case_pointer    dw 0
request_count   dw 0
irq_count       dw 0
observed_status db 0
observed_iff    db 0
interrupted_sp  dw 0
final_sp        dw 0
main_stack_used dw 0
irq_stack_used  dw 0
capture_count   db 0
capture_native  db 0
gate_status     db 0
transfer_count  db 0
axis_x          db 0
axis_start      db 0
axis_end        db 0
rect_x          db 0
rect_y          db 0
rect_w          db 0
rect_h          db 0
block_x         db 0
block_y         db 0
block_w         db 0
block_h         db 0
block_buffer    dw 0
copy_direction  db 0
copy_pointer    dw 0
draw_y          db 0
draw_rows       db 0
draw_cols       db 0
fill_value      db 0
pointer_visible db 0
pointer_x       dw 0
pointer_y       db 0
pointer_col     db 0
pointer_line    db 0
pointer_w       db 0
pointer_h       db 0
pointer_sprite  dw 0
pointer_excluded db 0
pointer_saves   dw 0
pointer_restores dw 0
request_guard_low ds 16,#D7
request_packet  ds 16,0
request_guard_high ds 16,#D7
state_end
                assert state_end <= #9900, "graphics state overflow"
                org #9900
trace_records   ds 27*4,0
trace_end
                assert trace_end <= FOUNDATION_IRQ_STACK-16, "trace/stack overlap"
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
                assert $ <= #9D30, "stack/pointer buffer overlap"
                org #9D30
pointer_guard_low ds 16,#D7
pointer_background ds 24,0
pointer_guard_high ds 16,#D7
                org #9D80
transfer_guard_low ds 16,#D7
transfer_buffer ds 64,0
transfer_guard_high ds 16,#D7
probe_end
                assert probe_end <= #A000, "graphics probe enters firmware workspace"
                save "FOUND.RAW",probe_start,probe_end-probe_start
