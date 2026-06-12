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
    }
}
