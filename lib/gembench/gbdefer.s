;; Compact MSX2 Architecture Milestone-3 deferred-message bindings (#35).
        .module gbdefer
        .globl  _gb_defer_register
        .globl  _gb_defer_send
        .globl  _gb_defer_current
        .globl  _gb_defer_slots_free
        .globl  _gb_defer_find_service
        .globl  _gb_defer_find_accessory
        .globl  _gb_defer_cancel_all

        .area   _CODE

_gb_defer_register::
        xor     a
        jp      0x80CF

_gb_defer_send::
        ld      a, #1
        jp      0x80CF

_gb_defer_current::
        ld      a, #2
        jp      0x80CF

_gb_defer_slots_free::
        ld      a, #3
        jp      0x80CF

_gb_defer_find_service::
        ld      b, a
        ld      a, #4
        jp      0x80CF

_gb_defer_find_accessory::
        ld      c, a
        ld      a, #5
        jp      0x80CF

_gb_defer_cancel_all::
        ld      a, #6
        jp      0x80CF
