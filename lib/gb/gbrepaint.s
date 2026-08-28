;; Optional top-window repaint binding. Keep this separate from gblib.s: ASxxxx
;; retains whole assembly objects, and several tight apps cannot afford a
;; trampoline they never call.
        .module gbrepaint
        .globl  _gb_repaint_top

        .area   _CODE

_gb_repaint_top:
        jp      0x8027          ; GB_REPAINTTOP (retired modal GB_LAUNCH slot)
