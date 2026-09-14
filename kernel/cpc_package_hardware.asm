; Small fixed-address loader glue, placed beside transport for CPC's budget.
cpc_package_guard
                push hl                    ; shared entry still needs its app name
                call cpc_package_guard_check
                pop hl
                ret
cpc_package_guard_check
                ld a,(CPC_PACKAGE_READY)
                cp 1
                jp nz,cpc_package_reject
                ld a,(SEC_BUSY)
                ld hl,PKG_BUSY
                or (hl)
                ld hl,io_busy
                or (hl)
                ld hl,SCHED_CURRENT
                or (hl)
                jp nz,cpc_package_reject
                scf
                ret

cpc_package_read
                ld a,(CPC_PACKAGE_PREFIX)
                or a
                jp z,cpc_stream_read
                ld a,b
                dec a
                or c
                jp nz,cpc_package_prefix_bad
                ld de,PKG_BUFFER
                or a
                sbc hl,de
                jp nz,cpc_package_prefix_bad
                xor a
                ld (CPC_PACKAGE_PREFIX),a
                ret
