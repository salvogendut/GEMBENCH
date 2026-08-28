;; Optional MSX2 GEMBENCH-1 managed-window registration wrapper. Kept separate
;; from gblib.s so legacy applications do not pay for an unused v1 entry point.
        .module gbwindow_kind
        .globl  _gb_wm_managed_kind

        .area   _CODE
_gb_wm_managed_kind:
        ld      a, #0xB6        ; GB_WK_ABI_V1 registration selector
        jp      0x80B1          ; GB_WMMANAGED
