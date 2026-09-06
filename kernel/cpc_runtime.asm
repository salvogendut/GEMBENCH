; #77 unified M4 runtime composition. Same core, no diagnostic WM/callbacks.
; Experimental launcher only, NOT the Desktop distribution or all SDK services.
CPC_RUNTIME equ 1
CPC_DRAWING equ 1
CPC_WM equ 1
CPC_LIFETIME equ 1
CPC_REGISTRATION equ 1
CPC_SERVICES equ 1
CPC_ROUTING equ 1
CPC_LOADING equ 1
CPC_FSCTX equ 1
CPC_FS_DIRECTORY equ 1
CPC_FS_WRITE equ 1
                include "../lib/cpc/production_layout.inc"
                include "cpc_registration_provider.inc"
FAULT_STORAGE_BANK equ 0
FAULT_STORAGE_ROM equ 0
FAULT_STORAGE_COPY equ 0
FAULT_CLIP equ 0
FAULT_COPY equ 0
FAULT_CURSOR equ 0
CPC_WINDOW_MENU_CLEAR equ cpc_menu_clear
CPC_WINDOW_MENU_INSTALL equ cpc_menu_install
CPC_WINDOW_CHROME_DRAW equ wm_chrome_draw
                include "cpc_scheduler.asm"
                include "../lib/cpc/drawing_layout.inc"
                include "cpc_support.asm"
                org CPC_HARDWARE_BASE
cpc_hardware_begin
                include "../lib/cpc/bank.asm"
                include "../lib/cpc/m4.asm"
storage_command_fault
storage_header_fault
storage_response_fault
                ret
                include "../lib/cpc/irq.asm"
                include "../lib/cpc/input.asm"
cpc_hardware_used_end
                assert $<=CPC_HARDWARE_END,"runtime hardware overflow"
                save "HARDWARE.RAW",cpc_hardware_begin,$-cpc_hardware_begin

                org CPC_KERNEL_BASE
cpc_kernel_begin
                include "cpc_runtime_api.inc"
cpc_runtime_core_begin
                include "../lib/cpc/memory.asm"
                include "../lib/cpc/graphics_gate.asm"
                include "../lib/cpc/graphics.asm"
                include "../lib/cpc/text.asm"
                include "../lib/cpc/drawing.asm"
                include "cpc_window_policy.asm"
                include "cpc_lifetime.asm"
                include "cpc_registration.asm"
                include "cpc_services.asm"
                include "cpc_routing.asm"
                include "cpc_loading.asm"
                include "fsctx_size.inc"
                include "cpc_fsctx.asm"
cpc_runtime_core_end
                include "cpc_runtime_services.asm"
                include "../lib/cpc/runtime_input.asm"
                include "cpc_runtime_boot.asm"
cpc_font_payload
                incbin "DEFAULT.FNT"
cpc_font_end
                include "../lib/cpc/cursor.inc"
cpc_kernel_used_end
                assert $<=CPC_KERNEL_END,"unified runtime exceeds high kernel"
                save "CORE.RAW",cpc_kernel_begin,$-cpc_kernel_begin
