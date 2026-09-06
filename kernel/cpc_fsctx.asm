; Private composition of the same resident gate and an M4-loaded C module.
CPC_FS_REQUEST equ #2400
CPC_FS_XFER equ #1500
CPC_FS_CURSOR equ #2420
CPC_FS_PENDING equ #2460
CPC_FS_DIAG equ #24A0
CPC_FS_IO_STATUS equ #24A6
CPC_FS_COMMAND_END equ #24A8
CPC_FS_MODULE equ #4400
CPC_FS_MODULE_LIMIT equ #6000
                ifdef CPC_FS_DIRECTORY
cpc_fs_directory_enabled equ 1
                endif
cpc_fs_ready equ #24AA
cpc_fs_module_offset equ #24AC
cpc_fs_module_dest equ #24AE
FSCTX_GATE_OP equ CPC_FS_REQUEST
FSCTX_GATE_STATUS equ CPC_FS_REQUEST+1
FSCTX_GATE_HANDLE equ CPC_FS_REQUEST+2
FSCTX_GATE_OWNER equ CPC_FS_REQUEST+4
FSCTX_MODULE_RUN equ cpc_fs_run_module
GB_FSCTX_ERR_UNSUPPORTED equ 1
GB_FSCTX_ERR_CONTEXT equ 7
                macro FSCTX_PRIVATE_DISPATCH
                mend
                macro FSCTX_CHECK_WORKER
                ld a,(SCHED_CURRENT)
                or a
                jr nz,kfsctx_context
                mend
cpc_fsctx_begin
; Serialized private adapter wrapper. The implicit owner is captured by the
; SHARED gate while the actual caller page is still mapped; not from REQ_OWNER.
cpc_fsctx_call
                push af
                ld a,i
                push af
                di
                ld a,(SCHED_LOCK)
                push af
                ld a,1
                ld (SCHED_LOCK),a
                pop bc
                pop de
                pop af
                push de
                push bc
                call k_fsctx
                pop bc
                push af
                ld a,b
                ld (SCHED_LOCK),a
                pop af
                pop bc
                bit 2,c
                ret z
                ei
                ret
                include "core/fsctx_gate.asm"
gbfsctx_modname db "GBFSCTX MOD"
cpc_fs_run_module
                ld a,(cpc_fs_ready)
                or a
                ret z
                ifdef CPC_FAULT_FS_OWNER
                ld de,(draw_root_owner)      ; negative: ignore mapped caller
                ld (CPC_FS_REQUEST+4),de
                endif
                ld a,(CPC_FS_REQUEST)
                ifndef CPC_FS_DIRECTORY
                cp 5
                jr z,cpc_fs_unsupported
                cp 6
                jr z,cpc_fs_unsupported
                cp 14
                jr z,cpc_fs_unsupported
                endif
                cp 9
                jr z,cpc_fs_unsupported
                cp 10
                jr z,cpc_fs_unsupported
                ld a,(BANK_CUR)
                push af
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                call CPC_FS_MODULE
                pop af
                call foundation_bank_set
                scf
                ret
cpc_fs_unsupported
                ld a,GB_FSCTX_ERR_UNSUPPORTED
                ld (FSCTX_GATE_STATUS),a
                ld hl,0
                ld (CPC_FS_REQUEST+10),hl
                xor a
                ld (CPC_FS_REQUEST+21),a
                scf
                ret

; Fixed-code bridge for CD and GETPATH. File I/O still uses storage_gate.
; The module has staged a bounded command and is mapped in F7, IRQ excluded.
cpc_fs_exchange
                ld a,(io_busy)
                or a
                ld a,5
                jr nz,cpc_fs_exchange_early
                ld a,(io_offline)
                or a
                ld a,7
                jr nz,cpc_fs_exchange_early
                ld a,1
                ld (io_busy),a
                ld a,(ga_shadow)
                push af
                ld a,(rom_shadow)
                push af
                ld a,(ga_shadow)
                and #F7
                call storage_ga_set
                ld a,6
                call storage_rom_set
                ld hl,(CPC_FS_COMMAND_END)
                call storage_send
                ld (CPC_FS_IO_STATUS),a
                pop af
                call storage_rom_set
                pop af
                call storage_ga_set
                xor a
                ld (io_busy),a
                ld a,(CPC_FS_IO_STATUS)
cpc_fs_exchange_early
                ld l,a                       ; SDCC stack-call byte return
                ret
cpc_fs_read128
                ld hl,CPC_APP_IO_REQUEST
                ld bc,16
                call storage_gate
                ld (CPC_FS_IO_STATUS),a
                ex de,hl                     ; SDCC stack-call word return
                ret

; Load the C module from M4 before exposing the private gate. No incbin copy
; of its executable, no execution in the app aperture before it has loaded.
cpc_fs_load_module
                ld a,(BANK_CUR)
                push af
                ld a,CPC_DATA_PAGE
                call foundation_bank_set
                ld hl,cpc_fs_module_request
                ld de,CPC_APP_IO_REQUEST
                ld bc,16
                ldir
                ld hl,cpc_fs_module_path
                ld de,CPC_APP_IO_PATH
                ld bc,11
                ldir
                ld hl,CPC_FS_MODULE
                ld (cpc_fs_module_dest),hl
                ld hl,0
                ld (cpc_fs_module_offset),hl
cpc_fs_module_next
                ld hl,(cpc_fs_module_offset)
                ld (CPC_APP_IO_REQUEST+10),hl
                call cpc_fs_read128
                ld a,(CPC_FS_IO_STATUS)
                cp 2
                jr nc,cpc_fs_module_fail
                ld b,h
                ld c,l
                ld de,(cpc_fs_module_dest)
                add hl,de
                ld de,CPC_FS_MODULE_LIMIT+1
                or a
                sbc hl,de
                jr nc,cpc_fs_module_fail
                ld a,b
                or c
                jr z,cpc_fs_module_eof
                ld de,(cpc_fs_module_dest)
                ld hl,CPC_APP_IO_BUFFER
                ldir
                ld (cpc_fs_module_dest),de
                ld hl,(cpc_fs_module_offset)
                ld de,128
                add hl,de
                ld (cpc_fs_module_offset),hl
                ld a,(CPC_FS_IO_STATUS)
                or a
                jr z,cpc_fs_module_next
cpc_fs_module_eof
                ld hl,(cpc_fs_module_dest)
                ld de,CPC_FS_MODULE+CPC_FS_MODULE_BYTES
                or a
                sbc hl,de
                jr nz,cpc_fs_module_fail
                ld a,1
                ld (cpc_fs_ready),a
                pop af
                call foundation_bank_set
                scf
                ret
cpc_fs_module_fail
                pop af
                call foundation_bank_set
                or a
                ret
cpc_fs_module_request db 1,1
                dw CPC_APP_IO_PATH
                db 11,0
                dw CPC_APP_IO_BUFFER,128,0,0,0
cpc_fs_module_path db "/FSCTX.BIN",0
cpc_fsctx_end
                assert CPC_FS_XFER>=#1500 && CPC_FS_XFER+512<=#1700,"FS transfer overflow"
                assert CPC_FS_REQUEST+32<=CPC_FS_CURSOR,"FS request/cursor overlap"
                assert CPC_FS_CURSOR+64<=CPC_FS_PENDING,"FS cursor/pending overlap"
                assert CPC_FS_PENDING+64<=CPC_FS_DIAG,"FS pending/diag overlap"
                assert cpc_fs_module_dest+2<=#24C0,"FS gate/path overlap"
                assert #2500+64<=CORE_FSCTX_TABLE,"FS path/contexts overlap"
                assert #2540+16<=CORE_FSCTX_TABLE,"FS directory entry/context overlap"
                assert CPC_FS_MODULE+CPC_FS_MODULE_BYTES<=CPC_FS_MODULE_LIMIT,"FS module/scratch overlap"
