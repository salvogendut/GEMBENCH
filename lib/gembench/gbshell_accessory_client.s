;; Accessory-only exact discovery binding, kept out of legacy shell clients.
        .module gbshell_accessory_client
        .globl  _gb_shell_find_accessory

        .area   _CODE

;; unsigned char gb_shell_find_accessory(unsigned char accessory_id)
;; A=id -> GB_SHELL operation 4, C=id; A=opaque handle or zero.
_gb_shell_find_accessory::
        ld      c, a
        ld      a, #4
        jp      0x80C0
