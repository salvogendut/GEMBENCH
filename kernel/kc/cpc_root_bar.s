; Two resident entry points. No startup/initialized data: reset explicitly
; initializes the live flags before the first shared bar refresh.
        .module cpc_root_bar_entry
        .globl _cpc_bar_reset
        .globl _cpc_bar_tick
        .globl _cpc_desk_calculator
        .area _CODE
        jp _cpc_bar_reset
        jp _cpc_bar_tick
        jp _cpc_desk_calculator
