; #77 production-address adapter link + private execution probe.
; Does not expose an incomplete public jump table or claim a desktop.
                include "../lib/cpc/production_layout.inc"
FAULT_STORAGE_BANK equ 0
FAULT_STORAGE_ROM equ 0
FAULT_STORAGE_COPY equ 0
                ifndef CPC_FAULT_GUARD
CPC_FAULT_GUARD equ 0
                endif
                ifndef CPC_FAULT_RESTORE
CPC_FAULT_RESTORE equ 0
                endif
                include "cpc_scheduler.asm"
                ifdef CPC_DRAWING
                include "../lib/cpc/drawing_layout.inc"
                include "cpc_support.asm"
                endif

                org CPC_HARDWARE_BASE
cpc_hardware_begin
                include "../lib/cpc/bank.asm"
                include "../lib/cpc/m4.asm"
storage_command_fault
storage_header_fault
storage_response_fault
                ret                          ; diagnostic hooks inactive here
                include "../lib/cpc/irq.asm"
                include "../lib/cpc/input.asm"
cpc_hardware_used_end
                assert cpc_hardware_used_end<=CPC_HARDWARE_END,"CPC hardware allocation overflow"
                save "HARDWARE.RAW",cpc_hardware_begin,cpc_hardware_used_end-cpc_hardware_begin

                org CPC_KERNEL_BASE
cpc_kernel_begin
                jp cpc_probe_start
                include "../lib/cpc/memory.asm"
                include "../debug/cpc_production/probe.asm"
                ifdef CPC_DRAWING
cpc_drawing_begin
FAULT_CLIP equ 0
FAULT_COPY equ 0
FAULT_CURSOR equ 0
                include "../lib/cpc/graphics_gate.asm"
                include "../lib/cpc/graphics.asm"
                include "../lib/cpc/text.asm"
                include "../lib/cpc/drawing.asm"
cpc_drawing_end
                include "../debug/cpc_production/drawing_probe.asm"
                include "drawing_vectors.inc"
cpc_font_payload
                incbin "DEFAULT.FNT"
cpc_font_end
                endif
                ifdef CPC_WM
                include "../debug/cpc_production/window_probe.asm"
                include "cpc_window_policy.asm"
                endif
                ifdef CPC_LIFETIME
                include "cpc_lifetime.asm"
                include "../debug/cpc_production/lifetime_probe.asm"
                endif
                ifdef CPC_PAD_KERNEL
                ds CPC_KERNEL_END-$,#B9       ; boot stress, NOT real kernel code
                endif
cpc_kernel_used_end
                assert cpc_kernel_used_end<=CPC_KERNEL_END,"CPC kernel allocation overflow"
                save "CORE.RAW",cpc_kernel_begin,cpc_kernel_used_end-cpc_kernel_begin
