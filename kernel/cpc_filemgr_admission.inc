; Private build-matched native File Manager. Not an APP format/ABI extension.
; The builder fills exactly six contract bytes AFTER linking against these
; runtime addresses. Zero length fails closed in every unbound assembly.
; CRC detects corruption/build mismatch, not malicious executable authors.
CPC_FILEMGR_PROFILE equ 1
cpc_filemgr_name db "FILEMGR BIN"
cpc_filemgr_contract
                dw 0                        ; exact linked payload size
                dw 0,0                      ; IEEE CRC32 of all loaded bytes
cpc_filemgr_admission
                ld hl,(fs_ent_size+2)
                ld a,h
                or l
                ret nz                      ; CF=0
                ld de,(cpc_filemgr_contract)
                ld a,d
                or e
                ret z                       ; unbound build
                ld hl,(fs_ent_size)
                or a
                sbc hl,de
                jr nz,cpc_filemgr_reject
                ld (gb4_file_size),de
                call gb4_crc32_loaded        ; same CRC implementation as v4
                ld hl,gb4_crc_value
                ld de,cpc_filemgr_contract+2
                ld b,4
cpc_filemgr_crc_check
                ld a,(de)
                cp (hl)
                jr nz,cpc_filemgr_reject
                inc hl
                inc de
                djnz cpc_filemgr_crc_check
                scf
                ret
cpc_filemgr_reject
                or a
                ret
