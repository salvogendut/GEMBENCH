; Shared native modal gate. The provider decides which module selector exists.
k_ui
                ld    hl,UI_MODAL
                inc   (hl)
                UI_SELECT_MODULE
kui_run
                call  run_data_module
                ld    hl,UI_MODAL
                dec   (hl)
                ld    a,(UI_RES)
                ld    c,a
                ret
gbui_modname    db    "GBUI    MOD"
