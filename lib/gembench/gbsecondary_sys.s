;; Minimal architecture calls required by an M6-only application. Applications
;; that explicitly request SYS=1 retain the complete lib/gb/gbsys.s surface.
        .module gbsecondary_sys
        .globl  _gb_owner_current
        .globl  _gb_page_alloc
        .globl  _gb_page_check
        .globl  _gb_window_drag

        .area   _CODE

_gb_owner_current:
        jp      0x80C6

_gb_page_alloc:
        ld      b, a
        xor     a
        jp      0x80C9

_gb_page_check:
        ld      a, #2
        jp      0x80C9

_gb_window_drag:
        ld      a, #8
        jp      0x80CC
