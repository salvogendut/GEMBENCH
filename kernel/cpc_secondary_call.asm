; Only copied parameter marshalling and completed-load binding are CPC glue.
; Ownership, generation seals, banked calls and release remain the shared core.
cpc_secondary_commit
                push ix
                push iy
                ld hl,(PKG_OWNER)
                ld (CPC_SECONDARY_BIND),hl
                ld hl,(PKG_PAGE)
                ld (CPC_SECONDARY_BIND+2),hl
                ld hl,(PKG_ENTRY)
                ld (CPC_SECONDARY_BIND+4),hl
                ld hl,(PKG_SECONDARY_SIZE)
                ld (CPC_SECONDARY_BIND+6),hl
                ld ix,CPC_SECONDARY_BIND
                call secondary_seal_bind
                pop iy
                pop ix
                ret
cpc_secondary_parameters
                push hl
                ld de,6
                add hl,de
                ld b,10
cpc_secondary_reserved
                ld a,(hl)
                or a
                jr nz,cpc_secondary_bad
                inc hl
                djnz cpc_secondary_reserved
                pop hl
                inc hl
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld c,(hl)
                inc hl
                ld b,(hl)
                ex de,hl
                jp secondary_call
cpc_secondary_bad
                pop hl
                ld a,1
                ld e,0
                ret
                include "core/secondary_call.asm"
