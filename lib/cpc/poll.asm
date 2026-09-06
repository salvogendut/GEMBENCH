; Root-only CPC keyboard/joystick virtual pointer adapter. No firmware or mouse
; detection claim. One byte-column / one scanline per sampled direction; input
; acceleration, mouse protocols and text translation remain separate adapters.
k_poll
                ld a,1
                ld (SCHED_LOCK),a
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
                push bc
                ld a,(CPC_HW_TICKS)
                ld (cpc_poll_stamp),a
cpc_poll_wait
                ei
                halt
                ld a,(cpc_poll_stamp)
                ld b,a
                ld a,(CPC_HW_TICKS)
                sub b
                cp 6                       ; CPC's 300-Hz IRQ -> at most 50 polls/sec
                jr c,cpc_poll_wait
                pop bc
                ld a,(poll_byte)
                cp b
                jr nz,cpc_poll_moved
                ld a,(poll_line)
                cp c
                jr z,cpc_poll_publish
cpc_poll_moved
                push bc
                call cpc_window_pointer_hide
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
                call cpc_window_pointer_show
cpc_poll_publish
                include "../../kernel/core/poll_publish.asm"
