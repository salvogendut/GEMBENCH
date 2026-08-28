/* gbsizedlg.c - opt-in app stub for the shared two-field dimensions dialog. */
#include "gb.h"

#define UI_OP      (*(volatile unsigned char *)0x1700)
#define UI_MODAL   (*(volatile unsigned char *)0x1705)
#define UI_WIDTH   (*(volatile unsigned int  *)0x1708)
#define UI_HEIGHT  (*(volatile unsigned int  *)0x170A)
#define UI_OP_SIZE 25

extern unsigned char gb_ui(void);

unsigned char gb_size_prompt(unsigned int *width, unsigned int *height)
{
    unsigned char accepted;
    UI_WIDTH = *width;
    UI_HEIGHT = *height;
    UI_OP = UI_OP_SIZE;
    accepted = gb_ui();
    UI_MODAL = 0;
    if (!accepted) return 0;
    *width = UI_WIDTH;
    *height = UI_HEIGHT;
    return 1;
}
