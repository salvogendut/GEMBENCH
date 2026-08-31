;; Universal-SDK semantic drawing leaves. Kept outside monolithic gblib so the
;; compile-once ABI adds no bytes to legacy target-compiled applications.
        .module gbuniversal_draw
        .globl  _gb_line_exec
        .globl  _gb_text_semantic_exec

        .area   _CODE

;; gb_line() owns the portable record and calls this after publishing fields.
_gb_line_exec:
        jp      0x8009          ; GB_LINE (synchronous on conforming v2 kernels)

;; Record at #C039: x, y, semantic pen, semantic paper, string pointer.
_gb_text_semantic_exec:
        ld      a, (0xC039)
        ld      b, a
        ld      a, (0xC03A)
        ld      c, a
        ld      a, (0xC03B)
        ld      d, a
        ld      a, (0xC03C)
        ld      e, a
        ld      hl, (0xC03D)
        jp      0x800C          ; GB_TEXT
