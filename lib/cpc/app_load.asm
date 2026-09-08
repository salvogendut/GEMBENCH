; M4 single-volume /GBENCH application reader for the shared launch transaction.
; Root serialized, IRQ excluded by caller. No firmware, global cwd mutation,
; directory iteration, fallback drive, or FSCTX API is implied by this leaf.
; The existing 128-byte read-at gate is unchanged. Its request/path/buffer live
; in reserved data-page scratch, never in the image being loaded. Copy through
; fixed staging before mapping the destination; all exits restore that mapping.
CPC_APP_PATH equ #2840              ; 64 bytes, after four reserved FS contexts
cpc_app_offset equ #2880
cpc_app_dest equ #2882
cpc_app_got equ #2884
cpc_app_status equ #2886
cpc_app_native equ #2887
cpc_app_pathbytes equ #2888
CPC_APP_IO_REQUEST equ #6000        ; reserved F7 data-page allocation
CPC_APP_IO_PATH equ #6020
CPC_APP_IO_BUFFER equ #6080
CPC_APP_IO_END equ #6100
                assert CPC_APP_PATH+64<=cpc_app_offset,"app path/state overlap"
                assert cpc_app_pathbytes+1<=#28A0,"app reader/admission overlap"
                assert CPC_APP_IO_BUFFER+128<=CPC_APP_IO_END,"app M4 buffer overflow"
                assert CPC_APP_IO_END<=CPC_APP_LIMIT,"app M4 scratch outside aperture"
                assert CPC_DRAW_STAGING_BASE+128<=CPC_DRAW_STAGING_END,"app staging overflow"

; Strict and normal have identical semantics on this single mounted M4 volume.
; CF=loaded, NC=absent/invalid/oversized/I/O failure. fs_ent_size is exact, not
; sector-rounded. Read one byte past the load limit to reject truncation.
fs_load_cur_sys
fs_load_sys
                ld a,(BANK_CUR)
                ld (cpc_app_native),a
                ld hl,(fs_load_dst)
                ld (cpc_app_dest),hl
                ld de,APP_BASE
                or a
                sbc hl,de
                jp nz,cpc_app_failure
                ld hl,(fs_load_max)
                ld de,APP_LOAD_MAX
                or a
                sbc hl,de
                jp nz,cpc_app_failure
                call cpc_app_make_path
                jp nc,cpc_app_failure
                ld hl,0
                ld (cpc_app_offset),hl
                ld (fs_ent_size),hl
                ld (fs_ent_size+2),hl
cpc_app_read
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                ld hl,cpc_app_request
                ld de,CPC_APP_IO_REQUEST
                ld bc,16
                ldir
                ld hl,CPC_APP_PATH
                ld de,CPC_APP_IO_PATH
                ld bc,64
                ldir
                ld a,(cpc_app_pathbytes)
                ld (CPC_APP_IO_REQUEST+4),a
                ld hl,(cpc_app_offset)
                ld (CPC_APP_IO_REQUEST+10),hl
                ld de,APP_LOAD_MAX
                or a
                sbc hl,de
                jr nz,cpc_app_read_chunk
                ld a,1                       ; boundary EOF probe, never copied
                ld (CPC_APP_IO_REQUEST+8),a
cpc_app_read_chunk
                ld hl,CPC_APP_IO_REQUEST
                ld bc,16
                call storage_gate
                ld (cpc_app_status),a
                ld (cpc_app_got),de
                cp 2                         ; only success or short/EOF
                jp nc,cpc_app_failure
                ld hl,(cpc_app_offset)
                add hl,de
                ld bc,APP_LOAD_MAX+1
                or a
                sbc hl,bc
                jp nc,cpc_app_failure         ; never execute truncated image
                ld hl,(cpc_app_got)
                ld a,h
                or l
                jr z,cpc_app_eof
                ld b,h
                ld c,l
                ld hl,CPC_APP_IO_BUFFER
                ld de,CPC_DRAW_STAGING_BASE
                ldir
                ld a,(cpc_app_native)
                call foundation_bank_set
                ld bc,(cpc_app_got)
                ld hl,CPC_DRAW_STAGING_BASE
                ld de,(cpc_app_dest)
                ldir
                ld (cpc_app_dest),de
                ld hl,(cpc_app_offset)
                ld de,(cpc_app_got)
                add hl,de
                ld (cpc_app_offset),hl
                ld a,(cpc_app_status)
                or a
                jp z,cpc_app_read
cpc_app_eof
                ld a,(cpc_app_native)
                call foundation_bank_set
                ld hl,(cpc_app_offset)
                ld (fs_ent_size),hl
                ld a,h
                or l
                ret z                        ; empty file is not executable
                scf
                ret
cpc_app_failure
                ld a,(cpc_app_native)
                call foundation_bank_set
                or a
                ret

; Convert bounded uppercase, padded 8.3 names. Reject separators, embedded
; padding and empty components before any I/O; no app may escape /GBENCH.
cpc_app_make_path
                ld hl,cpc_app_prefix
                ld de,CPC_APP_PATH
                ld bc,8
                ldir
                ld hl,fs_req_name
                ld b,8
                call cpc_app_component
                ret nc
                ld a,'.'
                ld (de),a
                inc de
                ld b,3
                call cpc_app_component
                ret nc
                xor a
                ld (de),a
                inc de
                ld hl,CPC_APP_PATH
                ex de,hl
                or a
                sbc hl,de
                ld a,l
                ld (cpc_app_pathbytes),a
                scf
                ret
cpc_app_component
                ld c,0                       ; chars seen, then padding marker
cpc_app_character
                ld a,(hl)
                inc hl
                cp ' '
                jr z,cpc_app_padding
                bit 7,c
                jr nz,cpc_app_name_bad
                cp '_'
                jr z,cpc_app_copy
                cp '-'
                jr z,cpc_app_copy
                cp '0'
                jr c,cpc_app_name_bad
                cp '9'+1
                jr c,cpc_app_copy
                cp 'A'
                jr c,cpc_app_name_bad
                cp 'Z'+1
                jr nc,cpc_app_name_bad
cpc_app_copy
                ld (de),a
                inc de
                inc c
                jr cpc_app_name_next
cpc_app_padding
                ld a,c
                or a
                jr z,cpc_app_name_bad
                set 7,c
cpc_app_name_next
                djnz cpc_app_character
                scf
                ret
cpc_app_name_bad
                or a
                ret
cpc_app_prefix db "/GBENCH/"
cpc_app_request db 1,1
                dw CPC_APP_IO_PATH
                db 0,0
                dw CPC_APP_IO_BUFFER,128,0,0,0
