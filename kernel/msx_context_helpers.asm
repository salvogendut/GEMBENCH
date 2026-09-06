; Native WM lookup and DOS mapper leaves for the shared context mechanism.
sched_wm_entry
                ld hl,WM_TABLE
                or a
                ret z
                ld b,a
                ld de,WM_ESZ
sched_we_add
                add hl,de
                djnz sched_we_add
                ret
sched_md_call
                jp (hl)
sched_bank_set
                ld (BANK_CUR),a
                ld hl,(MSX_PUTP1)
                jp (hl)                      ; mapper RET returns to our caller
