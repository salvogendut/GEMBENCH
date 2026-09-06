; Seven root-page entry points. No startup/initialized data: reset explicitly
; initializes the live flags before the first shared bar refresh.
        .module cpc_root_bar_entry
        .globl _cpc_bar_reset
        .globl _cpc_bar_tick
        .globl _cpc_desk_calculator
        .globl _cpc_desk_clock
        .globl _cpc_desktop_init
        .globl _cpc_desktop_frame
        .globl _cpc_desktop_event
        .area _CODE
        jp _cpc_bar_reset
        jp _cpc_bar_tick
        jp _cpc_desk_calculator
        jp _cpc_desk_clock
        jp _cpc_desktop_init
        jp _cpc_desktop_frame
        jp _cpc_desktop_event
