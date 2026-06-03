/* chello - the GEOBENCH C-app spike.
 *
 * Proof that a C program (SDCC-compiled) can run as a first-class GEOBENCH app:
 * it is built to load at #4000 inside an expansion bank and reaches the kernel
 * purely through libgb (see gb.h / gblib.s). It clears the screen, greets via
 * the kernel's 6x8 text renderer, and waits for ESC to quit cleanly back to the
 * desktop - exercising the full app lifecycle (enter -> draw -> poll -> return)
 * from C.
 *
 * Launched from the desktop by double-clicking the Clock icon. */
#include "gb.h"

void main(void)
{
    gb_cls();
    gb_text(1,  16, "Hello from C!");
    gb_text(1,  40, "This app is SDCC-compiled, runs in");
    gb_text(1,  52, "an expansion bank, and calls the");
    gb_text(1,  64, "GEOBENCH kernel through libgb - the");
    gb_text(1,  76, "same jump table the asm apps use.");
    gb_text(1, 110, "Press ESC to return to the desktop.");

    while (!(gb_poll() & GB_QUIT)) {
        /* idle until ESC; GB_POLL paces frames and runs the pointer */
    }
}
