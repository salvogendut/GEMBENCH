;; Compact target-side binding for applications which only advertise a shell
;; service.  Kept separate from the client calls for code-constrained Notepad.
        .module gbshell_register
        .globl  _gb_shell_register
        .globl  _gb_shell_respond

        .area   _CODE

;; unsigned char gb_shell_register(unsigned char service_class)
;; A=class -> GB_SHELL operation 0, B=class.
_gb_shell_register::
        ld      b, a
        xor     a
        jp      0x80C0

;; void gb_shell_respond(unsigned char response)
;; The synchronous shell mailbox is part of the frozen callback ABI.
_gb_shell_respond::
        ld      (0x1304), a
        ret
