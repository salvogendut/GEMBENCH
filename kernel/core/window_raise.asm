; Shared working focus/stack policy (#70); see window_focus_contract.inc.
; wm_raise: A = slot -> move it to z-order top and focus it (keeps the others'
; relative order). Compacts CORE_Z_ORDER removing the slot, then re-appends it at the end.
wm_raise
                ld    (CORE_FOCUS_SLOT),a
                ld    c,a
                call  wm_z_remove                 ; drop it from the z-order...
                ld    a,c
                jp    wm_z_append                  ; ...and re-append on top (tail-call)
