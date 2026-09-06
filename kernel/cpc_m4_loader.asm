; Fixed low M4 loader; copied here by cpc_m4_boot.asm before first I/O.
                include "../lib/cpc/production_layout.inc"
                include "boot_symbols.inc"
                org CPC_LOADER_BASE
boot_load_start
                ld sp,CPC_MAIN_TOP
                ld hl,CPC_LOAD_BYTES
                ld (CPC_LOAD_REMAIN),hl
                ld hl,CPC_KERNEL_BASE
                ld (CPC_LOAD_DEST),hl
                ld hl,boot_request
                ld de,#4000
                ld bc,16
                ldir
                ld hl,boot_path
                ld de,#4020
                ld bc,10
                ldir
boot_load_next
                ld hl,(CPC_LOAD_REMAIN)
                ld a,h
                or a
                jr nz,boot_load_full
                ld a,l
                cp 128
                jr c,boot_load_count
boot_load_full
                ld a,128
boot_load_count
                ld (#4008),a
                ld l,a
                ld h,0
                ld (CPC_LOAD_COUNT),hl
                ld hl,(CPC_LOAD_OFFSET)
                ld (#400A),hl
                ld hl,#4000
                ld bc,16
                call storage_gate
                or a
                jr nz,boot_load_fail
                ld hl,(CPC_LOAD_COUNT)
                or a
                sbc hl,de
                jr nz,boot_load_fail
                ld bc,(CPC_LOAD_COUNT)
                ld hl,#4100
                ld de,(CPC_LOAD_DEST)
                ldir
                ld (CPC_LOAD_DEST),de
                ld bc,(CPC_LOAD_COUNT)
                ld hl,(CPC_LOAD_OFFSET)
                add hl,bc
                ld (CPC_LOAD_OFFSET),hl
                ld hl,(CPC_LOAD_REMAIN)
                or a
                sbc hl,bc
                ld (CPC_LOAD_REMAIN),hl
                ld a,h
                or l
                jr nz,boot_load_next
                jp CPC_KERNEL_BASE
boot_load_fail
                ld a,#E1
                ld (CPC_FAILURE),a
                ld a,#FF
                ld (CPC_PHASE),a
                di
                halt
                jr boot_load_fail
boot_request    db 1,1
                dw #4020
                db 10,0
                dw #4100,128,0,0,0
boot_path       db "/CORE.BIN",0
boot_load_end
                assert boot_load_end<=CPC_LOADER_END,"low boot loader overflow"
                save "LOADER.RAW",boot_load_start,boot_load_end-boot_load_start
