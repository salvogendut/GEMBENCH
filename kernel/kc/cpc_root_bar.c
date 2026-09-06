/* Native kernel integration of the existing Desktop bar, NOT a CPC Desktop
 * APP or a new portable ABI. Code is resident; private state belongs to the
 * kernel root's C0 page. Only the root loop / root DRAW may enter this module.
 * Replace this binding when the complete shared Desktop becomes the root. */
#include "gb.h"
#define GB_DEFER_MESSAGES 1
#include "gbdefer.h"
#include "gbshell.h"
#define GB_DESK_CATALOG_DATA
#include "gbdesk_catalog.h"

#define KCFG_MEMSTR "512K"
#define MENU_DEF ((volatile unsigned char *)0x1310)
#define WM_FS ((volatile unsigned char *)0x130A)
#define CLK_COL (GB_COLS - 12)
static unsigned int ss_idle;
static unsigned char ss_lmx, ss_lmy;

#include "../../apps/desktop/core/bar_render.inc"

void cpc_bar_reset(void)
{
    bar_init = bar_wasfs = 0;
}

void cpc_bar_tick(void)
{
    unsigned char msig, i;
#include "../../apps/desktop/core/bar_refresh.inc"
}

/* Temporary root binding for the real Desktop activation policy. F7 is a
 * private integration control, not a substitute Desk menu. Capacity/failure
 * presentation are native leaves until the full Desktop/UI is connected. */
volatile unsigned char cpc_accessory_requests, cpc_accessory_full;
static unsigned char cpc_accessory_capacity(void)
{
    return *(volatile unsigned char *)0x1350 >= 8 ||
           *(volatile unsigned char *)0x22E5 == 0;
}
static void cpc_accessory_full_alert(const char *first, const char *second)
{
    (void)first; (void)second;
    cpc_accessory_full = 1;
}
#define gb_wm_full cpc_accessory_capacity
#define gb_alert cpc_accessory_full_alert
#include "../../apps/desktop/core/accessory_open.inc"

void cpc_desk_calculator(void)
{
    ++cpc_accessory_requests;
    cpc_accessory_full = 0;
    open_accessory(GB_DESK_ACCESSORY_CALCULATOR_INDEX);
}
