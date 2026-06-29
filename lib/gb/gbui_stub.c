/* gbui_stub.c - the app-side stubs for the paged dialog service (#142, step 1b).
 *
 * Apps link this small file instead of gbdlg.c/gbprompt.c/gbpick.c. Each stub marshals
 * its request into the low-RAM UI block and calls gb_ui() (the GB_UI kernel call), which
 * pages in the GBUI module and runs the actual render. This is the ~800-byte/app saving:
 * the heavy dialog code lives once in the module, not in every bank. The API (gb.h) is
 * unchanged, so gbdoc.c and the apps need no edits.
 */
#include "gb.h"

#define UI_OP    (*(volatile unsigned char *)0x1700)
#define UI_COL   (*(volatile unsigned char *)0x1701)
#define UI_LINE  (*(volatile unsigned char *)0x1702)
#define UI_N     (*(volatile unsigned char *)0x1703)
#define UI_MODAL (*(volatile unsigned char *)0x1705)
#define UI_NAME  ((char *)0x1708)            /* OUT: pickfile/prompt result */
#define UI_TEXT  ((char *)0x1718)            /* IN: packed labels / caption / exts */

extern unsigned char gb_ui(void);            /* GB_UI trampoline -> UI_RES */

static unsigned char run_ui(void)
{
    unsigned char r = gb_ui();
    UI_MODAL = 0;                            /* defensive: a stale modal latch kills top-bar clicks */
    return r;
}

/* pack_exts: a NULL-terminated 3-char-ext list -> UI_TEXT as "EXT\0EXT\0\0" (double-NUL
   ends it); NULL -> just the terminator (show all). */
static void pack_exts(const char *const *exts)
{
    char *p = UI_TEXT;
    unsigned char i, k;
    if (exts) for (k = 0; exts[k]; k++) { for (i = 0; i < 3; i++) *p++ = exts[k][i]; *p++ = 0; }
    *p = 0;
}

unsigned char gb_popup(unsigned char col, unsigned char line,
                       const char *const *labels, unsigned char n)
{
    char *p = UI_TEXT;
    const char *s;
    unsigned char i;
    UI_OP = 1; UI_COL = col; UI_LINE = line; UI_N = n;
    for (i = 0; i < n; i++) { s = labels[i]; while (*s) *p++ = *s++; *p++ = 0; }
    return run_ui();
}

/* gb_alert: a click-to-dismiss notice. Reuses gb_popup (already paged in the module)
   as the box - the two lines ARE the "rows"; any click closes it and the return value
   is ignored. Centered horizontally for the typical width (#153). */
void gb_alert(const char *l1, const char *l2)
{
    const char *const m[2] = { l1, l2 };
    gb_popup(23, 84, m, 2);
}

unsigned char gb_prompt(const char *caption, char *buf, unsigned char maxlen)
{
    char *p = UI_TEXT;
    const char *s = caption;
    unsigned char i;
    UI_OP = 2; UI_N = maxlen;
    while (*s) *p++ = *s++;
    *p = 0;
    if (!run_ui()) return 0;
    for (i = 0; i < maxlen && i < 16; i++) buf[i] = UI_NAME[i];
    return 1;
}

unsigned char gb_pickfile(char *name11, const char *const *exts)
{
    unsigned char i;
    UI_OP = 3;
    pack_exts(exts);
    if (!run_ui()) return 0;
    for (i = 0; i < 11; i++) name11[i] = UI_NAME[i];
    return 1;
}

unsigned char gb_pickdir(const char *const *exts)
{
    UI_OP = 4;
    pack_exts(exts);
    return run_ui();
}

/* Modality is now the kernel's UI_MODAL (raised only while a dialog module runs). The
   app never executes during a dialog, so from its side it is always "not modal". These
   keep gb.h's API intact for callers (gbdoc.c) with no behavioural cost. */
unsigned char gb_modal(void) { return 0; }
void gb_modal_set(unsigned char on) { (void)on; }
void gb_popup_close(void) { }
