; Read-only M4 protocol qualification, not a directory implementation.
; Runs after the shared context fixture; all transactions use its fixed gate.
dp_vector equ #3350
dp_dest equ #3352
dp_done equ #3354
dp_commands equ #3356
DP_TRACE equ #6200
DP_STRIDE equ 144
cpc_fsdir_probe
                di
                ld a,(rom_shadow)
                push af
                xor a                      ; deliberately not the M4 ROM slot
                call storage_rom_set
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                ld hl,(command_count)
                ld (dp_commands),hl
                ld hl,DP_TRACE
                ld (dp_dest),hl
                ld hl,dp_vectors
                ld (dp_vector),hl
dp_next
                ld hl,response_buffer
                ld de,response_buffer+1
                ld bc,135
                ld (hl),#D7
                ldir
                ld ix,(dp_vector)
                ld c,(ix+0)
                ld b,0
                ld l,(ix+1)
                ld h,(ix+2)
                ld de,command_buffer+1
                ldir
                ld (CPC_FS_COMMAND_END),de
                call cpc_fs_exchange
                ld a,l
                ld de,(dp_dest)
                ld hl,136
                add hl,de
                ld (hl),a                  ; transport result, not command status
                inc hl
                ld a,(BANK_CUR)
                ld (hl),a
                inc hl
                ld a,(ga_shadow)
                ld (hl),a
                inc hl
                ld a,(rom_shadow)
                ld (hl),a
                inc hl
                ld a,(io_busy)
                ld (hl),a
                inc hl
                ld a,(io_fd)
                ld (hl),a
                inc hl
                ld a,(SCHED_LOCK)
                ld (hl),a
                inc hl
                ld a,i
                ld a,0
                jp po,dp_iff
                inc a
dp_iff          ld (hl),a
                ld hl,response_buffer
                ld bc,136
                ldir
                ld hl,(dp_dest)
                ld bc,DP_STRIDE
                add hl,bc
                ld (dp_dest),hl
                ld hl,(dp_vector)
                ld bc,3
                add hl,bc
                ld (dp_vector),hl
                ld hl,dp_done
                inc (hl)
                ld a,(hl)
                cp DP_CASES
                jr c,dp_next
                ld hl,(command_count)
                ld de,(dp_commands)
                or a
                sbc hl,de
                ld (dp_commands),hl
                pop af
                call storage_rom_set
                ld a,#C0
                call foundation_bank_set
                ret
                include "fsdir_vectors.inc"
                assert DP_TRACE+DP_CASES*DP_STRIDE<=#7000,"directory trace overflow"
                assert dp_commands+2<=#3400,"directory state overflow"
