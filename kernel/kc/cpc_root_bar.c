/* Native integration of the shared Desktop root menu/bar, not another Desktop
 * or a portable APP. Code and state now belong to root C0; the fixed kernel
 * loads the bounded module before callbacks run. Assets/File Manager follow. */
#include "gb.h"
#define GB_DESK_ACCESSORIES 1
#define DESKTOP_SYSTEM_MENU 0 /* its native providers are not qualified yet */
#define GB_DEFER_MESSAGES 1
#include "gbdefer.h"
#include "gbshell.h"
#define GB_DESK_CATALOG_DATA
#include "gbdesk_catalog.h"

#include GB_UI_PROVIDER
#define MENU_DEF ((volatile unsigned char *)0x1310)
#define WM_FS ((volatile unsigned char *)0x130A)
#define CLK_COL (GB_COLS - 12)
static unsigned int ss_idle;
static unsigned char ss_lmx, ss_lmy;
static const gb_doc_t deskdoc = { 0 };
static unsigned char want_accessory;

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

/* Temporary root binding for the real Desktop activation policy. F2/F7 are
 * private integration controls, not a substitute Desk menu. Capacity/failure
 * presentation are native leaves until the full Desktop/UI is connected. */
volatile unsigned char cpc_accessory_requests, cpc_accessory_full;
static unsigned char cpc_accessory_capacity(void)
{
    return *(volatile unsigned char *)0x1350 >= 8 ||
           *(volatile unsigned char *)0x22E5 == 0;
}
static void cpc_accessory_full_alert(const char *first, const char *second)
{
    const char *const rows[2] = { first, second };
    cpc_accessory_full = 1;
    gb_popup(23, 84, rows, 2);
}
#define gb_wm_full cpc_accessory_capacity
#define gb_alert cpc_accessory_full_alert
#include "../../apps/desktop/core/accessory_open.inc"
#include "../../apps/desktop/core/accessory_menu.inc"
#include "../../apps/desktop/core/menu_init.inc"

void cpc_desktop_init(void)
{
    desktop_menu_init();
}

void cpc_desktop_event(void)
{
    gb_doc_event();
}

void cpc_desktop_frame(void)
{
    if (gb_doc_frame()) {
        /* Desk has no content mutation: the shared popup already restored its
         * save-under. Launch/activation is the only resulting window damage. */
#include "../../apps/desktop/core/accessory_pending.inc"
    }
}

void cpc_desk_calculator(void)
{
    ++cpc_accessory_requests;
    cpc_accessory_full = 0;
    open_accessory(GB_DESK_ACCESSORY_CALCULATOR_INDEX);
}

void cpc_desk_clock(void)
{
    ++cpc_accessory_requests;
    cpc_accessory_full = 0;
    open_accessory(GB_DESK_ACCESSORY_CLOCK_INDEX);
}

/* Private keys exercise the real paged native service while the full System
 * menu remains gated. These marshal requests, not replacement dialog policy. */
extern unsigned char gb_ui(void);
static void ui_text(const char *s)
{
    char *p = UI_TEXT;
    while ((*p++ = *s++) != 0) ;
}
void cpc_test_prompt(void)
{
    UI_OP = 2; UI_N = 12; ui_text("Name:"); gb_ui();
}
void cpc_test_popup(void)
{
    unsigned char i;
    static const char labels[] = "Continue\0Cancel";
    UI_OP = 1; UI_N = 2; UI_COL = 23; UI_LINE = 84;
    for (i = 0; i < sizeof(labels); i++) UI_TEXT[i] = labels[i];
    gb_ui();
}
void cpc_test_about(void)
{
    UI_OP = 24; UI_COL = (GB_COLS - 60) / 2; UI_LINE = (GB_LINES - 62) / 2;
    gb_ui();
}
void cpc_test_size(void)
{
    UI_OP = 25; UI_WIDTH = 320; UI_HEIGHT = 200; gb_ui();
}
