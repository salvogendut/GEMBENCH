;; FormRef's M6 application-owned secondary renderer. It owns no pointers into
;; the primary page: every dynamic value arrives through the fixed transfer
;; record at 0xC400, and all drawing crosses the resident kernel jump table.
        .module formref_secondary

        .area   _CODE
_start::
        jp      formref_draw
        .db     0x47, 0x42, 0x53, 0x33, 0x01   ; "GBS3", version 1

;; Transfer layout: x, y, autosave, refined, resource-ready, saved-name[13].
formref_draw:
        ;; Window content surface.
        ld      a, (0xC400)
        ld      b, a
        ld      a, (0xC401)
        add     a, #14
        ld      c, a
        ld      d, #42
        ld      e, #56
        ld      a, #1
        call    0x8033                  ; GB_FILL

        ;; Saved name.
        ld      a, (0xC400)
        add     a, #2
        ld      b, a
        ld      a, (0xC401)
        add     a, #21
        ld      c, a
        ld      hl, #0xC405
        call    draw_textbw

        ;; Autosave status.
        ld      a, (0xC400)
        add     a, #2
        ld      b, a
        ld      a, (0xC401)
        add     a, #32
        ld      c, a
        ld      hl, #autosave_off
        ld      a, (0xC402)
        or      a
        jr      z, autosave_ready
        ld      hl, #autosave_on
autosave_ready:
        call    draw_textbw

        ;; Layout status.
        ld      a, (0xC400)
        add     a, #2
        ld      b, a
        ld      a, (0xC401)
        add     a, #43
        ld      c, a
        ld      hl, #classic_text
        ld      a, (0xC403)
        or      a
        jr      z, layout_ready
        ld      hl, #refined_text
layout_ready:
        call    draw_textbw

        ;; The unchanged 18x10 Open form button.
        ld      a, (0xC400)
        add     a, #2
        ld      b, a
        ld      a, (0xC401)
        add     a, #56
        ld      c, a
        ld      d, #18
        ld      e, #10
        ld      a, #1
        call    0x8033                  ; GB_FILL
        ld      a, (0xC400)
        add     a, #2
        ld      b, a
        ld      a, (0xC401)
        add     a, #56
        ld      c, a
        ld      d, #18
        ld      e, #10
        ld      a, (0xC404)
        or      a
        ld      a, #1                   ; disabled edge = Surface
        jr      z, button_edge
        ld      a, #2                   ; enabled edge = Text/Edge
button_edge:
        call    0x8021                  ; GB_FRAME
        ld      a, (0xC400)
        add     a, #4
        ld      b, a
        ld      a, (0xC401)
        add     a, #57
        ld      c, a
        ld      hl, #open_form_text
        call    draw_textbw
        ret

draw_textbw:
        ld      d, #2                   ; Text on Surface
        ld      e, #1
        call    0x800C                  ; GB_TEXT
        ret

autosave_on:   .asciz  "Autosave on"
autosave_off:  .asciz  "Autosave off"
refined_text:  .asciz  "Refined"
classic_text:  .asciz  "Classic"
open_form_text:.asciz  "Open form"

        .area   _DATA
        .area   _BSS
