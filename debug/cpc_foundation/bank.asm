; Audited from lib/bank.asm at parked CPC commit 56478578.
; Only C0 and configurations 4..7 of the first seven expansion groups are
; accepted: 64K base + 448K expansion = the explicit 512K fixture minimum.
; Caller owns DI. No unconditional EI; caller, code, state and stack must be
; outside 4000..7FFF. Success CF=1, failure CF=0 with mapping/shadow unchanged.
; Clobbers AF/BC only. The foreground and interrupt paths use this SAME gate.
foundation_bank_set
                cp #C0
                jr z,foundation_bank_valid
                cp #C4
                jr c,foundation_bank_invalid
                cp #F8
                jr nc,foundation_bank_invalid
                ld b,a
                and 7
                cp 4
                jr c,foundation_bank_invalid
                ld a,b
foundation_bank_valid
                ld (bank_shadow),a
                ld bc,#7F00
                out (c),a
                scf
                ret
foundation_bank_invalid
                or a
                ret
