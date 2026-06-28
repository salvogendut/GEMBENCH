; kernel/modules.asm - shared PAGE_DATA module dispatchers.

; k_ui (GB_UI #80AE): the paged dialog service (#142). The caller has marshalled its
; request into the low-RAM UI_* block; page in PAGE_DATA, load the GBUI module to
; DATA_MODTOP (#6000, above font+icons), raise UI_MODAL (so the dialog's own gb_poll
; loop doesn't dispatch top-bar clicks into the now-swapped-out app), CALL it to render
; + write UI_RES, then restore. Returns BC = UI_RES for the C trampoline. The dialog is
; modal: this call blocks until the user picks/cancels.
; run_data_module: the shared PAGE_DATA module loader (#238). HL = 11-byte module name.
; Save the caller's page, map PAGE_DATA, load the named module to DATA_MODTOP (#6000)
; from the boot drive, CALL it, restore the page. CF set = loaded (NC = missing). One
; copy instead of three (GB_UI + GB_NET + the floppy-write stub) - reclaims the resident
; bytes the net hook needs.
run_data_module
                ld    a,(bank_cur)
                push  af
                ld    a,PAGE_DATA
                call  bank_set
                ld    de,fs_req_name          ; HL (name) -> fs_req_name
                ld    bc,11
                ldir
                ld    hl,#2000                ; load cap (8 KB window to #8000)
                ld    (fs_load_max),hl
                ld    hl,DATA_MODTOP          ; #6000
                ld    (fs_load_dst),hl
                call  fs_load_sys            ; module -> #6000 (boot drive, preserves browse dir)
                jr    nc,rdm_miss
                call  DATA_MODTOP            ; run it
                pop   af
                call  bank_set
                scf
                ret
rdm_miss
                pop   af
                call  bank_set
                or    a                       ; NC = missing
                ret

k_ui
                ld    a,1
                ld    (UI_MODAL),a            ; modal: the dialog's gb_poll must not dispatch
                ld    hl,gbui_modname         ; top-bar clicks into the swapped-out app
                call  run_data_module
                xor   a
                ld    (UI_MODAL),a
                ld    a,(UI_RES)              ; missing module -> caller pre-set a cancel
                ld    c,a
                ld    b,0
                ret
gbui_modname    db    "GBUI    MOD"

; k_net (GB_NET #80BD): the paged W5100 networking module (#238). The app marshalled an
; op + args into the GBNET_* low-RAM block; run GBNET.MOD and return BC = GBNET_RES.
k_net
                ld    hl,gbnet_modname
                call  run_data_module
                ld    a,(GBNET_RES)
                ld    c,a
                ld    b,0
                ret
gbnet_modname   db    "GBNET   MOD"
