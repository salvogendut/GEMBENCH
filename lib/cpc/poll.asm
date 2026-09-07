; Root-only CPC keyboard/joystick virtual pointer adapter. No firmware or mouse
; detection claim. One byte-column / one scanline per sampled direction; input
; acceleration, mouse protocols and text translation remain separate adapters.
; The cadence is measured from the previous sample, not from entry into POLL.
; Root GB_PARAMS boundaries also service movement, without dispatching events
; or reentering a callback. No keyboard/video work is added to the IRQ handler.
k_poll
                ld a,1
                ld (SCHED_LOCK),a
k_poll_wait
                call cpc_pointer_due
                jr nc,k_poll_ready
                ei
                halt
                jr k_poll_wait
k_poll_ready
                call cpc_pointer_sample
                ld a,(CPC_KEYS+9)
                ld e,a
                ld a,(CPC_KEYS+5)           ; SPACE row 5 bit 7
                rlca
                rlca
                rlca
                rlca
                rlca
                rlca                       ; bit 7 -> bit 5 (joystick fire 1)
                and e
                cpl
                and #20
                ld (in_fire),a
                ld a,(CPC_KEYS+8)           ; Escape row 8 bit 2
                cpl
                and 4
                ld (in_quit),a
                include "../../kernel/core/poll_publish.asm"

; NC if at least six 300-Hz ticks have passed. A 16-bit stamp avoids the old
; 8-bit wrap after a long operation. Missed periods are never replayed as jumps.
cpc_pointer_due
                ld hl,(CPC_HW_TICKS)
                ld de,(cpc_poll_stamp)
                or a
                sbc hl,de
                ld de,6
                or a
                sbc hl,de
                ret

; Safe point between primitives: preserve caller registers, bank, IX, IFF and
; scheduler lock. Only the root may scan/move; workers retain compute-only ABI.
cpc_pointer_service
                push af
                ld a,(SCHED_CURRENT)
                or a
                jr nz,cpc_pointer_service_done
                ld a,(CORE_POINTER_SUPPRESSED)
                or a
                jr nz,cpc_pointer_service_done
                ld a,(pointer_visible)
                or a
                jr nz,cpc_pointer_service_ready
                ld a,(CORE_POINTER_PAINTLOCK)
                or a
                jr z,cpc_pointer_service_done ; respect explicit application hide
cpc_pointer_service_ready
                push hl
                push de
                call cpc_pointer_due
                jr c,cpc_pointer_service_early
                push bc
                ld a,i
                push af
                di
                ld a,(SCHED_LOCK)
                push af
                ld a,1
                ld (SCHED_LOCK),a
                ; Save-under copying is longer than the IRQ period on CPC.
                ; The root/lock prevents reentry; only the PPI scan itself
                ; needs DI. Do not lose time ticks while moving the pointer.
                ei
                call cpc_pointer_sample
                di
                pop af
                ld (SCHED_LOCK),a
                pop af
                jp po,cpc_pointer_service_di
                ei
cpc_pointer_service_di
                pop bc
cpc_pointer_service_early
                pop de
                pop hl
cpc_pointer_service_done
                pop af
                ret

cpc_pointer_sample
                ld hl,(CPC_HW_TICKS)
                ifdef CPC_RUNTIME
                ld de,(cpc_poll_stamp)
                ld (cpc_poll_stamp),hl
                or a
                sbc hl,de
                ld (cpc_pointer_interval),hl
                else
                ld (cpc_poll_stamp),hl
                endif
                call cpc_input_scan
                ld a,(poll_byte)
                ld b,a
                ld a,(poll_line)
                ld c,a
                ld a,(CPC_KEYS+9)           ; joystick directions active low
                ld e,a
                ld a,(CPC_KEYS)
                and e
                bit 0,a
                jr nz,cpc_poll_down
                ld a,c
                or a
                jr z,cpc_poll_down
                dec c
cpc_poll_down
                ld a,(CPC_KEYS)
                rrca                       ; keyboard down bit 2 -> joystick bit 1
                and e
                bit 1,a
                jr nz,cpc_poll_left
                ld a,c
                cp CPC_LINES-1
                jr nc,cpc_poll_left
                inc c
cpc_poll_left
                ld a,(CPC_KEYS+1)
                rlca
                rlca                       ; keyboard left bit 0 -> joystick bit 2
                and e
                bit 2,a
                jr nz,cpc_poll_right
                ld a,b
                or a
                jr z,cpc_poll_right
                dec b
cpc_poll_right
                ld a,(CPC_KEYS)
                rlca
                rlca                       ; keyboard right bit 1 -> joystick bit 3
                and e
                bit 3,a
                jr nz,cpc_poll_fire
                ld a,b
                cp CPC_COLUMNS-1
                jr nc,cpc_poll_fire
                inc b
cpc_poll_fire
                ld a,(poll_byte)
                cp b
                jr nz,cpc_poll_moved
                ld a,(poll_line)
                cp c
                jr nz,cpc_poll_moved
                ifdef CPC_RUNTIME
                xor a
                ld (cpc_pointer_moving),a
                ld (cpc_pointer_max_gap),a
                ld (cpc_pointer_max_gap+1),a
                endif
                ret
cpc_poll_moved
                ifdef CPC_RUNTIME
                ld a,(cpc_pointer_moving)
                or a
                jr z,cpc_pointer_first_move
                ld hl,(cpc_pointer_interval)
                ld de,(cpc_pointer_max_gap)
                or a
                sbc hl,de
                jr c,cpc_pointer_first_move
                ld hl,(cpc_pointer_interval)
                ld (cpc_pointer_max_gap),hl
cpc_pointer_first_move
                ld a,1
                ld (cpc_pointer_moving),a
                ld hl,(cpc_pointer_moves)
                inc hl
                ld (cpc_pointer_moves),hl
                endif
                push bc
                call pointer_hide
                pop bc
                ld a,b
                ld (poll_byte),a
                ld l,b
                ld h,0
                add hl,hl
                add hl,hl
                ld (pointer_x),hl
                ld a,c
                ld (poll_line),a
                ld (pointer_y),a
                ; A timer pass can keep a nonoverlapping pointer visible. If
                ; it moves into ANY pending damage, leave it hidden until the
                ; compositor completes. Never change its clip/region iterator.
                ld a,(CORE_POINTER_PAINTLOCK)
                or a
                jp z,pointer_show
                ifdef CPC_RUNTIME
                ld a,(CORE_PARAM_TIMER_OWNER)
                or a
                ret p                     ; ordinary exposure: pass owns pointer
                ld a,(CORE_COMPOSITOR_DAMAGE)
                ld d,a
                ld a,b
                add a,3
                cp d
                jp c,pointer_show
                jp z,pointer_show
                ld a,(CORE_COMPOSITOR_DAMAGE+2)
                add a,d
                cp b
                jp c,pointer_show
                jp z,pointer_show
                ld a,(CORE_COMPOSITOR_DAMAGE+1)
                ld d,a
                ld a,c
                add a,8
                cp d
                jp c,pointer_show
                jp z,pointer_show
                ld a,(CORE_COMPOSITOR_DAMAGE+3)
                add a,d
                cp c
                jp c,pointer_show
                jp z,pointer_show
                endif
                ret
