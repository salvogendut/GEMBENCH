; Optional module loader, emitted after the aligned VDP tables just like the
; deferred service. Keeps alignment padding out of the child-COM growth.
; Called only after the primary admission module has passed boot validation.
data_pages_load
                ld    hl,name_data_pages
                ld    de,fs_req_name
                call  copy11
                ld    hl,MSX_DATA_PAGE_ENTRY
                ld    (fs_load_dst),hl
                ld    hl,MSX_DATA_PAGE_LIMIT-MSX_DATA_PAGE_ENTRY
                ld    (fs_load_max),hl
                call  fs_load_sys
                ret   nc
                ld    hl,(fs_ent_size)
                ld    de,MSX_DATA_PAGE_SIZE
                or    a
                sbc   hl,de
                jr    nz,data_pages_load_bad
                ld    hl,(MSX_DATA_PAGE_ENTRY+3)
                ld    de,#4247                 ; GB
                or    a
                sbc   hl,de
                jr    nz,data_pages_load_bad
                ld    hl,(MSX_DATA_PAGE_ENTRY+5)
                ld    de,#5044                 ; DP
                or    a
                sbc   hl,de
                jr    nz,data_pages_load_bad
                ld    a,(MSX_DATA_PAGE_ENTRY+7)
                dec   a
                jr    nz,data_pages_load_bad
                scf
                ret
data_pages_load_bad
                xor   a
                ret
name_data_pages db    "GBDPAGE MOD"
