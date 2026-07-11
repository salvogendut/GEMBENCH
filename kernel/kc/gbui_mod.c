/* GBUI - the paged dialog renderer (#142, step 1b).
 *
 * The kernel's GB_UI call pages this module into PAGE_DATA at #6000 and CALLs it. It
 * reads a marshalled request from the low-RAM UI block (filled by the app-side stubs in
 * gbui_stub.c), renders the dialog by calling the SHARED dialog code (gbdlg/gbprompt/
 * gbpick, compiled in here), and writes the result back to the UI block. Living here -
 * loaded once into the kernel's data page rather than linked into every app - is what
 * frees the ~800 bytes/app that let the data-heavy apps (paint/xaos/iconed) fit.
 *
 * The render uses resident kernel calls (gb_poll/fill/text/dir1 via gblib, which the
 * module links) and the font (in PAGE_DATA alongside us). The app's bank is swapped out
 * while we run, so the request carries everything we need; UI_MODAL (set by the kernel)
 * keeps gb_poll from dispatching top-bar clicks into the absent app.
 */
#include "gb.h"

#define UI_OP    (*(volatile unsigned char *)0x1700)
#define UI_COL   (*(volatile unsigned char *)0x1701)
#define UI_LINE  (*(volatile unsigned char *)0x1702)
#define UI_N     (*(volatile unsigned char *)0x1703)
#define UI_RES   (*(volatile unsigned char *)0x1704)
#define UI_NAME  ((char *)0x1708)            /* OUT: pickfile/prompt result (16 bytes) */
#define UI_TEXT  ((char *)0x1718)            /* IN: packed labels / caption / exts      */

#define UI_OP_POPUP    1
#define UI_OP_PROMPT   2
#define UI_OP_PICKFILE 3
#define UI_OP_PICKDIR  4
#define UI_OP_BROWSER  5
#define UI_OP_BSAVE_AS 8

/* Browser's low-RAM transfer block. The non-visual source/config operations
 * live in GBWEB.MOD; this dialog module only needs their status and proxy text. */
#define BUI_NPAGES     (*(volatile unsigned char *)0x3904)
#define BUI_FLAGS      (*(volatile unsigned char *)0x3909)
#define BUI_PROXY      ((char *)0x3920)
#define BUI_SAVE_NAME  ((char *)0x39C2)
#define BUI_PROXY_MAX  95
#define BUI_SOURCE_FULL 0x01

#define BUI_ACT_NONE   0
#define BUI_ACT_LOAD   1
#define BUI_ACT_SAVE   2
#define BUI_ACT_PROXY  3
#define BUI_ACT_SAVETO 4

static const char *const browser_file[] = { "Load", "Save" };
static const char *const browser_settings[] = { "Proxy...", "Direct" };
static const char *const html_exts[] = { "HTM", 0 };

static void browser_to_83(const char *src)
{
    unsigned char i = 0, j;
    for (j = 0; j < 11; j++) UI_NAME[j] = ' ';
    for (j = 0; j < 8 && src[i] && src[i] != '.'; j++) UI_NAME[j] = src[i++];
    UI_NAME[8] = 'H'; UI_NAME[9] = 'T'; UI_NAME[10] = 'M';
}

static void browser_menu(void)
{
    unsigned char sel;
    UI_RES = BUI_ACT_NONE;
    if (UI_N == 1) {
        sel = gb_popup(10, 8, browser_file, 2);
        if (sel == 0 && gb_pickfile(UI_NAME, html_exts)) UI_RES = BUI_ACT_LOAD;
        else if (sel == 1) UI_RES = BUI_ACT_SAVE;
    } else {
        sel = gb_popup(17, 8, browser_settings, 2);
        if (sel == 0) {
            if (gb_prompt("HTTP proxy:", BUI_PROXY, 0x80 | BUI_PROXY_MAX))
                UI_RES = BUI_ACT_PROXY;
        } else if (sel == 1) {
            BUI_PROXY[0] = 0;
            UI_RES = BUI_ACT_PROXY;
        }
    }
}

static void browser_save_as(void)
{
    char *name = (char *)0x1708;
    unsigned char i;
    UI_RES = BUI_ACT_NONE;
    if (!BUI_NPAGES || (BUI_FLAGS & BUI_SOURCE_FULL)) return;
    if (!gb_pickdir(html_exts)) return;
    if (!gb_prompt("Save HTML as:", name, 12)) return;
    browser_to_83(name);
    for (i = 0; i < 11; i++) BUI_SAVE_NAME[i] = UI_NAME[i];
    UI_RES = BUI_ACT_SAVETO;
}

void main(void)
{
    unsigned char i;
    char *p = UI_TEXT;

    if (UI_OP == UI_OP_POPUP) {
        const char *labels[16];                  /* rebuild the pointer array into UI_TEXT */
        unsigned char n = UI_N;
        if (n > 16) n = 16;
        for (i = 0; i < n; i++) { labels[i] = p; while (*p) p++; p++; }
        UI_RES = gb_popup(UI_COL, UI_LINE, labels, n);

    } else if (UI_OP == UI_OP_PROMPT) {
        char buf[16];
        UI_RES = gb_prompt(UI_TEXT, buf, UI_N);  /* caption in UI_TEXT, result -> buf */
        if (UI_RES) { for (i = 0; i < 16; i++) UI_NAME[i] = buf[i]; }

    } else if (UI_OP == UI_OP_PICKFILE || UI_OP == UI_OP_PICKDIR) {
        const char *exts[8];                     /* rebuild the ext list from UI_TEXT */
        unsigned char ne = 0;
        while (*p && ne < 7) { exts[ne++] = p; while (*p) p++; p++; }
        exts[ne] = 0;
        if (UI_OP == UI_OP_PICKFILE) UI_RES = gb_pickfile(UI_NAME, exts);   /* name -> UI_NAME */
        else                         UI_RES = gb_pickdir(exts);
    } else if (UI_OP == UI_OP_BROWSER) {
        browser_menu();
    } else if (UI_OP == UI_OP_BSAVE_AS) {
        browser_save_as();
    }
}
