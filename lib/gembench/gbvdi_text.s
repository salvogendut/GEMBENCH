;; Dynamic-pen text binding over the existing GB_TEXT kernel entry.
        .module gbvdi_text
        .globl  _gb_vdi_text_raw

        .area   _CODE

;; void gb_vdi_text_raw(u8 col, u8 line, u8 fg, u8 bg, const char *text)
;; A=col, L=line, stack [ret][fg,bg][text].
_gb_vdi_text_raw::
        ld      b, a
        ld      c, l
        pop     hl              ; return address
        pop     de              ; E=foreground, D=background
        ld      a, d
        ld      d, e
        ld      e, a
        ex      (sp), hl        ; HL=text, restore return address to stack
        call    0x800C
        ret
