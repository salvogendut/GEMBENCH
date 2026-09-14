; Fixed opt-in bindings. Native banking is the existing mapper leaf; ownership,
; sealing, copied calls and lifetime decisions remain shared policy.
SEC_TABLE equ MSX_SECONDARY_TABLE
SEC_STATE equ MSX_SECONDARY_STATE
SEC_TRANSFER equ MSX_FSCTX_TRANSFER
SEC_CURRENT equ SCHED_CURRENT
SEC_MAPPED equ BANK_CUR
SEC_LOCK equ SCHED_LOCK
SEC_OWNER_MAX equ GB_OWNER_MAX
SEC_OWNER_CURRENT equ GB_OWNER
SEC_MAP equ MSX_PACKAGE_MAP
SEC_ALLOW_IRQ equ 1
                include "core/secondary_contract.inc"

; Called by the serialized normal loader after success AND descriptor close.
msx_secondary_commit
                push ix
                push iy
                ld hl,(MSX_PACKAGE_STATE+2)
                ld (MSX_SECONDARY_BIND),hl
                ld hl,(MSX_PACKAGE_STATE+4)
                ld (MSX_SECONDARY_BIND+2),hl
                ld hl,(MSX_PACKAGE_STATE+14)
                ld (MSX_SECONDARY_BIND+4),hl
                ld hl,(MSX_PACKAGE_STATE+12)
                ld (MSX_SECONDARY_BIND+6),hl
                ld ix,MSX_SECONDARY_BIND
                call secondary_seal_bind
                pop iy
                pop ix
                ret

; HL points to GB_PARAMS' already-copied fixed 16-byte record. Reserved bytes
; are checked before the root gate receives its primary in/out pointer/count.
msx_secondary_parameters
                push hl
                ld de,6
                add hl,de
                ld b,10
msx_secondary_reserved
                ld a,(hl)
                or a
                jr nz,msx_secondary_bad
                inc hl
                djnz msx_secondary_reserved
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
msx_secondary_bad
                pop hl
                ld a,1
                ld e,0
                ret
                include "core/secondary_call.asm"
