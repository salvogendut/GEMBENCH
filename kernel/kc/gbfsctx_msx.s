;; Private resident leaf used by the paged GBFSCTX module. A raw BDOS return may
;; replace the module before its next instruction; op #FE performs _CHDIR from
;; the fixed native-FIB workspace and restores PAGE_DATA while still in kernel
;; code. The context module restores/overwrites the FIB after activation.
        .module gbfsctx_msx
        .globl  _gbfs_msx_chdir

        .area   _CODE

_gbfs_msx_chdir::
        ld      a, #0xFE
        call    #0x80D2
        ret
