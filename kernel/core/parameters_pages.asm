; Optional operation 10. Reuse the resident page policy, not app-local banking.
up_data_pages
                ld a,(CORE_PARAM_CURRENT)
                or a
                jp nz,up_context
                ld bc,(up_request+4)
                ld a,b
                or a
                jp nz,up_bad
                ld a,c
                cp 16
                jp nz,up_bad
                ld hl,(up_request+2)
                call up_span
                jp nc,up_bad
                PARAM_DATA_CALL
                jp up_ok
