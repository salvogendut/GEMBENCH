;; Client-side bindings for bounded GEMBENCH shell discovery and delivery.
        .module gbshell_client
        .globl  _gb_shell_find
        .globl  _gb_shell_send

        .area   _CODE

;; unsigned char gb_shell_find(unsigned char service_class)
;; A=class -> GB_SHELL operation 1, B=class; A=opaque handle or zero.
_gb_shell_find::
        ld      b, a
        ld      a, #1
        jp      0x80C0

;; unsigned char gb_shell_send(unsigned char handle, unsigned char request,
;;                             const char *argument11)
;; A=handle, L=request, stack [ret][argument].  Kernel wants B/C/HL.
_gb_shell_send::
        ld      b, a
        ld      c, l
        pop     hl
        ex      (sp), hl
        ld      a, #2
        call    0x80C0
        ret
