; Native root/frame router contract, not the universal APP ABI. Serialized root
; calls on a fixed stack; poll leaves preserve current bank and root lock.
; Poll publishes byte-column/scanline coordinates and click/quit/held bits 0/1/2.
; Menu dispatch consumes the click before focus routing. Frame callbacks and bar
; callbacks run in their respective app pages. Gesture polling uses these same
; invariants; drawing/backdrop/pointer leaves must obey compositor clipping.
; ROOT_LOOP_REPEAT is the loop back-edge (diagnostics may observe/return there).
                assert WM_ESZ==25,"input router native stride changed"
                assert WM_FR_FRAME==5,"input router frame offset changed"
                assert WM_FR_FLAGS==13,"input router flags offset changed"
                assert (SCR_COLS>=10)&(SCR_COLS<=255),"input router byte-column bounds"
                assert (SCR_LINES>=24)&(SCR_LINES<=255),"input router scanline bounds"
