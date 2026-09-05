;; MSX2 app-linked entry for the shared root-side timer collector (#73).
;; Keep its measured placement in Desktop; workers/publication are unchanged.
        .module gbtimer_collect
        .globl  _gb_timer_collect

        .include "msx_timer_collect.inc"
        .include "core/timer_collect_contract.inc"
        .area   _CODE
        .include "core/timer_collect.inc"
