; Private #79 profile. Both native apps use the same length/CRC validator.
; No native package or new public ABI; the builder binds each exact payload.
CPC_SETTINGS_PROFILE equ 1
cpc_settings_name db "SETTINGSBIN"
cpc_settings_contract
                dw 0
                dw 0,0
cpc_settings_admission
                ld de,cpc_settings_contract
cpc_native_contract_admission
                ld hl,(fs_ent_size+2)
                ld a,h
                or l
                ret nz
                ld a,(de)
                ld c,a
                inc de
                ld a,(de)
                ld b,a
                or c
                ret z                       ; zero-length contract fails closed
                ld hl,(fs_ent_size)
                or a
                sbc hl,bc
                jr nz,cpc_native_contract_reject
                ld (gb4_file_size),bc
                inc de
                push de
                call gb4_crc32_loaded        ; existing universal/native CRC
                pop de
                ld hl,gb4_crc_value
                ld b,4
cpc_native_contract_crc
                ld a,(de)
                cp (hl)
                jr nz,cpc_native_contract_reject
                inc hl
                inc de
                djnz cpc_native_contract_crc
                scf
                ret
cpc_native_contract_reject
                or a
                ret
