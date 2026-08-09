#include "gb.h"
#include "gbtitle.h"

#define TITLE_VALID (*(volatile unsigned char *)0x1710)
#define TITLE_READY (*(volatile unsigned char *)0x124F)
#define TITLE_MODNAME ((char *)0x3914)

static unsigned char run_title_module(void) __naked
{
__asm
    ld a,#0x80
    call #0x80AE
    ret
__endasm;
}

static void install(unsigned char mode)
{
    static const char name[11] = {
        'G','B','T','I','T','L','E',' ','M','O','D'
    };
    unsigned char i;
    for (i = 0; i < 11; i++) TITLE_MODNAME[i] = name[i];
    TITLE_VALID = mode;
    run_title_module();
}

void gb_titlebar_install(unsigned int size)
{
    install((size >= 106) ? 2 : (size >= 56));
}

void gb_titlebar_init(unsigned int size)
{
    TITLE_READY = 0;
    gb_titlebar_install(size);
}

void gb_gadgets_install(unsigned int size)
{
    install((size >= 50) ? 3 : 0);
}
