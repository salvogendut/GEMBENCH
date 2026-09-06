; Optional operation 8: caller-owned 32-byte FS header and 512-byte transfer.
; PARAM_ENTER already owns IX/IFF/lock and up_dispatch validated mapped owner.
; Validate ALL spans before touching native state. The shared native gate still
; captures implicit owner and applies context policy; never trust header owner.
up_filesystem
                ld a,(CORE_PARAM_CURRENT)
                or a
                jp nz,up_context
                ld hl,(up_request+4)
                ld de,32
                or a
                sbc hl,de
                jp nz,up_bad
                ld hl,(up_request+8)
                ld de,512
                or a
                sbc hl,de
                jp nz,up_bad
                ld hl,(up_request+2)
                ld bc,32
                call up_span
                jp nc,up_bad
                ld hl,(up_request+6)
                ld bc,512
                call up_span
                jp nc,up_bad
                ; Header and transfer must not overlap (either address order).
                ld de,(up_request+2)
                or a
                sbc hl,de
                jr c,up_fs_transfer_first
                ld de,32
                or a
                sbc hl,de
                jp c,up_bad
                jr up_fs_copy
up_fs_transfer_first
                add hl,de                   ; recover transfer start
                ld bc,512
                add hl,bc
                or a
                sbc hl,de
                jp nc,up_fs_transfer_end
                jr up_fs_copy
up_fs_transfer_end
                ld a,h                      ; adjacent buffers are permitted
                or l
                jp nz,up_bad
up_fs_copy
                ld hl,(up_request+2)
                ld a,(hl)
                cp 15
                jp nc,up_bad
                ld de,PARAM_FS_REQUEST
                ld bc,32
                ldir
                ld hl,(up_request+6)
                ld de,PARAM_FS_TRANSFER
                ld bc,512
                ldir
                ld a,(PARAM_FS_REQUEST)
                call PARAM_FS_CALL
                ; Providers restore caller mapping; no callback/reentry while
                ; the scheduler lock is held. Native status is in header[1].
                ld hl,PARAM_FS_REQUEST
                ld de,(up_request+2)
                ld bc,32
                ldir
                ld hl,PARAM_FS_TRANSFER
                ld de,(up_request+6)
                ld bc,512
                ldir
                jp up_ok

                assert (PARAM_FS_REQUEST+32<=PARAM_FS_TRANSFER)|(PARAM_FS_TRANSFER+512<=PARAM_FS_REQUEST),"native FS request/transfer overlap"
                assert ((PARAM_FS_REQUEST>=0)&(PARAM_FS_REQUEST+32<=#4000))|((PARAM_FS_REQUEST>=#8000)&(PARAM_FS_REQUEST+32<=#10000)),"native FS request must remain fixed"
                assert ((PARAM_FS_TRANSFER>=0)&(PARAM_FS_TRANSFER+512<=#4000))|((PARAM_FS_TRANSFER>=#8000)&(PARAM_FS_TRANSFER+512<=#10000)),"native FS transfer must remain fixed"
