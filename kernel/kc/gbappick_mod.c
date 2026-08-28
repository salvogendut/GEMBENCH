/* GBAPICK.MOD - paged ICONED Open dialog for icon-bearing applications. */
#include "gb.h"

#define UI_RES  (*(volatile unsigned char *)0x1704)
#ifdef GB_PREEMPTIVE
#define UI_OP   (*(volatile unsigned char *)0x1700)
#define UI_COL  (*(volatile unsigned char *)0x1701)
#define UI_LINE (*(volatile unsigned char *)0x1702)
#define UI_N    (*(volatile unsigned char *)0x1703)
#endif
#define UI_NAME ((char *)0x1708)

extern unsigned char gb_pickappicon(char *out11);
#ifdef GB_PREEMPTIVE
extern unsigned char gb_drawappicon(const char *name11, unsigned char x,
                                    unsigned char y, unsigned char half);
#endif

void main(void)
{
#ifdef GB_PREEMPTIVE
    if (UI_OP == 1)
        UI_RES = gb_drawappicon(UI_NAME, UI_COL, UI_LINE, UI_N);
    else
#endif
        UI_RES = gb_pickappicon(UI_NAME);
}
