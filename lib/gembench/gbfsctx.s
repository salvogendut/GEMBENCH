;; Compact MSX2 Architecture Milestone-4 filesystem-context gate (#37).
        .module gbfsctx_call
        .globl  _gb_fsctx_call

        .area   _CODE

_gb_fsctx_call::
        jp      0x80D2
