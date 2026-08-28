; Compile-time MSX video backend selector. Only the selected driver is resident.
                ifdef MSX_SCREEN7
                include "screen7.asm"
                else
                include "screen6.asm"
                endif
