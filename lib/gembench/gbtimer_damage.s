;; MSX2 native worker publisher, using shared SDCC/Z80 code (#75).
        .module gbtimer_damage
        .globl  _gb_timer_damage
        .include "msx_timer_publish.inc"
        .include "core/timer_publish_contract.inc"
        .area _CODE
        .include "core/timer_publish.inc"
