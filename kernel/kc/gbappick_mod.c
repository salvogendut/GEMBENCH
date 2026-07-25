/* GBAPICK.MOD - paged ICONED Open dialog for icon-bearing applications. */
#include "gb.h"

#define UI_RES  (*(volatile unsigned char *)0x1704)
#define UI_NAME ((char *)0x1708)

extern unsigned char gb_pickappicon(char *out11);

void main(void)
{
    UI_RES = gb_pickappicon(UI_NAME);
}
