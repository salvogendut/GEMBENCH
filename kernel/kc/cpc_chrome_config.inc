/* The Desktop's actual key/stem selection, bound to the retained CPC config.
 * Only the byte reader gains an explicit end/NUL guard: it cannot spill past
 * the 512-byte text allocation when a final line has no terminator. */
#include "../../apps/desktop/core/config_value.inc"
static char chrome_name[11];
static void chrome_select(unsigned char gadgets) __naked
{
    gadgets;
__asm
#define CHROME_BOUNDED_TEXT
#include "../../apps/desktop/core/chrome_select.inc"
cl_load:
    ret
#include "../../apps/desktop/core/chrome_keys.inc"
__endasm;
}

static void chrome_config(void)
{
    unsigned char i;
    chrome_select(0);
    for (i=0; i<11; ++i) CPC_TITLE_NAME[i]=chrome_name[i];
    chrome_select(1);
    for (i=0; i<11; ++i) CPC_GADGET_NAME[i]=chrome_name[i];
}
