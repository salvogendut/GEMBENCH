;; Accessory-only registration binding, kept out of ordinary shell providers.
        .module gbshell_accessory_register
        .globl  _gb_shell_register_accessory

        .area   _CODE

;; unsigned char gb_shell_register_accessory(unsigned char accessory_id)
;; A=id -> GB_SHELL operation 3, C=id.
_gb_shell_register_accessory::
        ld      c, a
        ld      a, #3
        jp      0x80C0
