; Shared module call transaction: preserve caller page/load limits, load, call,
; restore on both success and failure. Only allocations/reader are providers.
run_data_module
                ex    de,hl
                ld    a,(bank_cur)
                push  af
                ld    hl,(fs_load_max)
                push  hl
                ld    hl,(fs_load_dst)
                push  hl
                MODULE_MAP_PAGE
                call  bank_set
                ex    de,hl
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    hl,MODULE_LOAD_MAX
                ld    (fs_load_max),hl
                ld    hl,DATA_MODTOP
                ld    (fs_load_dst),hl
                call  MODULE_READ
                pop   de
                ld    (fs_load_dst),de
                pop   de
                ld    (fs_load_max),de
                jr    nc,rdm_miss
                call  DATA_MODTOP
                pop   af
                call  bank_set
                scf
                ret
rdm_miss
                pop   af
                call  bank_set
                or    a
                ret
