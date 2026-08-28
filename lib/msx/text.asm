; Compile-time MSX text renderer selector. Only the selected renderer is resident.
                ifdef MSX_SCREEN7
                include "text7.asm"
                else
                include "text6.asm"
                endif
