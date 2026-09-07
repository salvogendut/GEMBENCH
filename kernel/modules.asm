; kernel/modules.asm - shared PAGE_DATA module dispatchers.

; k_ui (GB_UI #80AE): the paged dialog service (#142). The caller has marshalled its
; request into the low-RAM UI_* block; page in PAGE_DATA, load the GBUI module to
; DATA_MODTOP (#6000, above font+icons), raise UI_MODAL (so the dialog's own gb_poll
; loop doesn't dispatch top-bar clicks into the now-swapped-out app), CALL it to render
; + write UI_RES, then restore. Returns BC = UI_RES for the C trampoline. The dialog is
; modal: this call blocks until the user picks/cancels.
; run_data_module: the shared PAGE_DATA module loader (#238). HL = 11-byte module name.
; Save the caller's page and fs_load_* request, map PAGE_DATA, load the named module
; to DATA_MODTOP (#6000) from the boot drive, restore fs_load_* for the module's own
; operation, CALL it, restore the page. CF set = loaded (NC = missing). One copy
; instead of three (GB_UI + GB_NET + the floppy-write stub) - reclaims the resident
; bytes the net hook needs.
MODULE_LOAD_MAX equ #2000
MODULE_READ equ fs_load_sys
                macro MODULE_MAP_PAGE
                LD_A_PAGE_DATA
                mend
                macro UI_SELECT_MODULE
                rlca
                ld hl,gbui_modname
                jr nc,kui_run
                ld hl,#3914
                mend
                include "core/data_module.asm"
                include "core/ui_module.asm"

; k_net (GB_NET #80BD): the paged networking module. Apps marshal an op + args
; into the GBNET_* low-RAM block; the kernel loads the module matching the card
; backend and returns BC = GBNET_RES. Albireo uses the W5100/Net4CPC module;
; M4 uses the M4ROM TCP command module.
k_net
                ld    hl,gbnet_modname
                call  run_data_module
                ld    a,(GBNET_RES)
                ld    c,a
                ret
                if STORAGE_M4
gbnet_modname   db    "GBNETM4 MOD"
                else
gbnet_modname   db    "GBNET   MOD"
                endif
