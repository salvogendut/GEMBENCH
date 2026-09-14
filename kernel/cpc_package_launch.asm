; Private CPC adapter around the SAME shared launch/package transaction.
; One descriptor covers prefix classification, all payload bytes and EOF.
cpc_package_reject
                or a
                ret
cpc_package_launch
                ld a,(SCHED_LOCK)
                push af
                ld a,1
                ld (SCHED_LOCK),a
                call cpc_package_route
                push af
                pop de
                pop af
                ld (SCHED_LOCK),a
                push de
                pop af
                ret
cpc_package_route
                xor a
                ld (WM_OPEN_STRICT),a
                ld (CPC_PACKAGE_PREFIX),a
                call cpc_app_make_path
                ret nc
                call cpc_stream_open
                or a
                jr nz,cpc_package_reject
                ld hl,PKG_BUFFER
                ld bc,256
                call cpc_stream_read
                or a
                jp nz,cpc_package_failed
                ld (cpc_app_got),bc
                ld a,b
                dec a
                or c
                jr nz,cpc_package_primary
                ; Only a bounded canonical v4 prefix selects streaming. All
                ; format, capability and CRC validation remains shared code.
                ld a,(PKG_BUFFER)
                cp #C3
                jr nz,cpc_package_primary
                ld hl,(PKG_BUFFER+3)
                ld de,#4247
                or a
                sbc hl,de
                jr nz,cpc_package_primary
                ld hl,(PKG_BUFFER+5)
                ld de,#5041
                or a
                sbc hl,de
                jr nz,cpc_package_primary
                ld a,(PKG_BUFFER+7)
                cp 4
                jr nz,cpc_package_primary
                ld hl,(PKG_BUFFER+14)
                ld a,h
                or a
                jr nz,cpc_package_primary
                ld a,l
                cp 24
                jr z,cpc_package_prefix_ok
                cp 32
                jr nz,cpc_package_primary
cpc_package_prefix_ok
                ld de,PKG_BUFFER
                add hl,de
                push hl
                pop ix
                ld l,(ix+52)
                ld h,(ix+53)
                ld e,(ix+40)
                ld d,(ix+41)
                or a
                sbc hl,de
                jr c,cpc_package_primary
                jr z,cpc_package_primary
                ld a,1
                ld (CPC_PACKAGE_PREFIX),a
                ld de,(CORE_PENDING_OWNER)
                call package_load
                or a
                jr nz,cpc_package_failed
                ; Shared load preserves IX: classification used the fixed
                ; prefix, whose buffer now holds the last read, not metadata.
                ld de,APP_BASE-PKG_BUFFER
                add ix,de
                call cpc_runtime_admission
                ret nc
                jp cpc_secondary_commit
cpc_package_primary
                ld hl,APP_BASE
                ld (cpc_app_dest),hl
                ld hl,APP_LOAD_MAX
                ld (fs_load_max),hl
                ld hl,0
                ld (cpc_app_offset),hl
                ld bc,(cpc_app_got)
                call cpc_package_copy_have
                or a
                jr nz,cpc_package_failed
                call cpc_stream_close
                or a
                jp nz,cpc_package_reject
                ld hl,(cpc_app_offset)
                ld (fs_ent_size),hl
                ld hl,0
                ld (fs_ent_size+2),hl
                jp cpc_loaded_admission
cpc_package_failed
                call cpc_stream_close       ; includes rejected shared contexts
                xor a
                ld (CPC_PACKAGE_PREFIX),a
                ret                         ; NC: shared launch reclaims all pages

; Consume the already-read prefix without a seek or another OPEN. Only the
; locked transaction owns this buffer; no IRQ/callback may replace its bytes.
cpc_package_prefix_bad
                ld a,2
                ld bc,0
                ret

; Bounded copy for primary-only/native files and the boot module. Destination,
; remaining capacity and offset=0 belong to this transaction. No execution or
; publication; a one-byte boundary EOF probe rejects oversized input.
cpc_package_copy_next
                ld bc,(fs_load_max)
                ld a,b
                or c
                jr nz,cpc_package_copy_bound
                ld c,1
cpc_package_copy_bound
                ld a,b
                cp 2
                jr c,cpc_package_copy_read
                ld bc,512
cpc_package_copy_read
                ld hl,PKG_BUFFER
                call cpc_stream_read
                or a
                ret nz
cpc_package_copy_have
                ld a,b
                or c
                ret z
                ld hl,(fs_load_max)
                or a
                sbc hl,bc
                jr c,cpc_package_prefix_bad
                ld (fs_load_max),hl
                ld hl,(cpc_app_offset)
                add hl,bc
                ld (cpc_app_offset),hl
                ld hl,PKG_BUFFER
                ld de,(cpc_app_dest)
                ldir
                ld (cpc_app_dest),de
                jr cpc_package_copy_next

; Executes in high code AFTER the low bootstrap jumps to the kernel. No APP
; can launch until this exact assembled module's size and CRC match. Missing,
; stale, truncated or appended modules fail boot without executing their code.
cpc_package_boot
                ld a,1
                ld (SCHED_LOCK),a
                ld hl,cpc_package_name
                ld de,fs_req_name
                call copy11
                call cpc_app_make_path
                ret nc
                call cpc_stream_open
                or a
                jp nz,cpc_package_reject
                ld hl,CPC_PACKAGE_MODULE_BASE
                ld (cpc_app_dest),hl
                ld hl,CPC_PACKAGE_MODULE_SIZE
                ld (fs_load_max),hl
                ld hl,0
                ld (cpc_app_offset),hl
                call cpc_package_copy_next
                or a
                jp nz,cpc_package_failed
                call cpc_stream_close
                or a
                jp nz,cpc_package_reject
                ld hl,(cpc_app_offset)
                ld de,CPC_PACKAGE_MODULE_SIZE
                or a
                sbc hl,de
                jp nz,cpc_package_reject
                ld hl,#FFFF
                ld (gb4_crc_value),hl
                ld (gb4_crc_value+2),hl
                ld hl,CPC_PACKAGE_MODULE_BASE
                ld bc,CPC_PACKAGE_MODULE_SIZE
                call gb4_crc_byte
                call gb4_crc_finish
                ld hl,gb4_crc_value
                ld de,cpc_package_crc
                ld b,4
cpc_package_boot_crc
                ld a,(de)
                cp (hl)
                jp nz,cpc_package_reject
                inc hl
                inc de
                djnz cpc_package_boot_crc
                ld a,1
                ld (CPC_PACKAGE_READY),a
                xor a
                ld (SCHED_LOCK),a
                scf
                ret
cpc_package_name db "GBPKLOADMOD"
cpc_package_crc
                include "package_crc.inc"

; Native module/asset/root readers use the same single-volume path and stream
; without app admission. Preserve their original fixed aperture/size contract.
fs_load_cur_sys
fs_load_sys
                ld hl,(fs_load_max)
                push hl
                ld a,(SCHED_LOCK)
                push af
                ld a,1
                ld (SCHED_LOCK),a
                call cpc_package_native_read
                push af
                pop de
                pop af
                ld (SCHED_LOCK),a
                pop hl
                ld (fs_load_max),hl
                push de
                pop af
                ret
cpc_package_native_read
                ld hl,(fs_load_dst)
                ld (cpc_app_dest),hl
                ld de,APP_BASE
                or a
                sbc hl,de
                jp nz,cpc_package_reject
                ld hl,(fs_load_max)
                ld de,APP_LOAD_MAX
                or a
                sbc hl,de
                jp nz,cpc_package_reject
                call cpc_app_make_path
                ret nc
                call cpc_stream_open
                or a
                jp nz,cpc_package_reject
                ld hl,0
                ld (cpc_app_offset),hl
                call cpc_package_copy_next
                or a
                jp nz,cpc_package_failed
                call cpc_stream_close
                or a
                jp nz,cpc_package_reject
                ld hl,(cpc_app_offset)
                ld (fs_ent_size),hl
                ld a,h
                or l
                ret z
                ld hl,0
                ld (fs_ent_size+2),hl
                scf
                ret
