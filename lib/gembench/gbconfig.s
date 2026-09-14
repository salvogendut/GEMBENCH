;; Optional compact binding for the bounded resident configuration cache.
        .module gbconfig
        .globl  _gb_config_publish

        .area   _CODE

;; unsigned char gb_config_publish(const char *text, unsigned int length)
;; __sdcccall(1): HL=text, DE=length. Operation 5 consumes/copies synchronously.
_gb_config_publish::
        ld      b, d
        ld      c, e
        ld      a, #5
        jp      0x80C0
