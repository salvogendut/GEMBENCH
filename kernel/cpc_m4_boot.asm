; M4 boot: firmware loads only this small image below its workspace. After the
; final MODE call, copy the loader/transport to fixed low RAM and load CORE.BIN
; using our own M4 path. Nothing calls firmware after takeover.
                include "../lib/cpc/production_layout.inc"
                include "boot_symbols.inc"
                org #8000
cpc_boot_start
                ld a,1
                call #BC0E
                di
                ld sp,#9F00                 ; temporary boot stack, not being filled
                ld bc,#7F00
                ld a,#8D
                out (c),a
                ld hl,#0100
                ld de,#0101
                ld bc,#3EFF
                ld (hl),0
                ldir
                ; Distinct live-stack canary bytes; do not initialize code or
                ; hardware state by a broad fill once the copied leaves exist.
                ld hl,CPC_MAIN_STACK-16
                ld de,CPC_MAIN_STACK-15
                ld bc,CPC_STACKS_END-(CPC_MAIN_STACK-16)-1
                ld (hl),#D7
                ldir
                ld hl,CPC_MAIN_STACK
                ld bc,256
                call boot_stack_fill
                ld hl,CPC_IRQ_STACK
                ld bc,256
                call boot_stack_fill
                ld hl,CPC_TMP_STACK
                ld bc,128
                call boot_stack_fill
                ld hl,hardware_payload
                ld de,CPC_HARDWARE_BASE
                ld bc,hardware_payload_end-hardware_payload
                ldir
                ld hl,scheduler_payload
                ld de,CPC_SCHED_BASE
                ld bc,scheduler_payload_end-scheduler_payload
                ldir
                ld hl,loader_payload
                ld de,CPC_LOADER_BASE
                ld bc,loader_payload_end-loader_payload
                ldir
                ld a,#8D
                call storage_ga_set
                ld a,#C0
                call foundation_bank_set
                ld a,6
                call storage_rom_set
                ld a,#85
                call storage_ga_set
                ld a,#19                    ; M4 NMI off; no firmware handler
                call storage_command
                ld (hl),1
                inc hl
                call storage_send
                ld a,#8D
                call storage_ga_set
                ld hl,CPC_SCREEN_BASE
boot_pixels
                ld a,h
                xor l
                ld (hl),a
                inc hl
                ld a,h
                or l
                jr nz,boot_pixels
                jp CPC_LOADER_BASE
boot_stack_fill
                ld (hl),#A6
                inc hl
                dec bc
                ld a,b
                or c
                jr nz,boot_stack_fill
                ret
hardware_payload
                incbin "HARDWARE.RAW"
hardware_payload_end
scheduler_payload
                incbin "SCHED.RAW"
scheduler_payload_end
loader_payload
                incbin "LOADER.RAW"
loader_payload_end
cpc_boot_end
                assert cpc_boot_end<=#9A00,"boot image overwrites live firmware workspace"
                save "BOOT.RAW",cpc_boot_start,cpc_boot_end-cpc_boot_start
