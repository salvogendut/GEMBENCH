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
#ifdef GBUI_APPICON_PICKER
#define UI_MODNAME ((char *)0x3914)
static const char appick_modname[11] = {
    'G','B','A','P','I','C','K',' ','M','O','D'
};

static unsigned char run_appick(void) __naked
{
__asm
    ld a,#0x80
    call #0x80AE
    ld a,c
    ret
__endasm;
}
#endif

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

/* Generated GBRM menus use UI_OP 6. UI_TEXT carries decorated NUL labels while
 * UI_NAME carries the live state bytes. This reuses the proven paged popup and
 * costs no second modal loop in GBUI.MOD's tight 8 KiB page. */
#ifdef GBR_MENU_RUNTIME
unsigned char gb_resource_menu_popup(unsigned char col,
                                     const unsigned char *descriptor,
                                     unsigned int size,
                                     const unsigned char *state)
{
    char *out = UI_TEXT;
    const unsigned char *item;
    unsigned char i, j, n, title_len;
    if (!descriptor || !state || size < 7 || descriptor[0] != 'G' ||
        descriptor[1] != 'B' || descriptor[2] != 'R' || descriptor[3] != 'M')
        return 0xFF;
    n = descriptor[5];
    title_len = descriptor[6];
    item = descriptor + 7 + title_len;
    UI_OP = 6; UI_COL = col; UI_LINE = 8; UI_N = n;
    for (i = 0; i < n; i++) {
        UI_NAME[i] = (char)state[i];
        if (state[i] & 0x04) {
            *out++ = (state[i] & 0x01) ? '{' : '(';
            *out++ = (state[i] & 0x02) ? 'x' : ' ';
            *out++ = (state[i] & 0x01) ? '}' : ')';
            *out++ = ' ';
        } else if (state[i] & 0x08) {
            *out++ = (state[i] & 0x01) ? '{' : '[';
            *out++ = (state[i] & 0x02) ? 'x' : ' ';
            *out++ = (state[i] & 0x01) ? '}' : ']';
            *out++ = ' ';
        } else if (state[i] & 0x01) {
            *out++ = '-'; *out++ = '-'; *out++ = ' '; *out++ = ' ';
        } else {
            *out++ = ' '; *out++ = ' '; *out++ = ' '; *out++ = ' ';
        }
        for (j = 0; j < item[3]; j++) *out++ = (char)item[4 + j];
        *out++ = 0;
        item += (unsigned char)(4u + item[3]);
    }
    return run_ui();
}
#endif

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
#ifdef GBUI_APPICON_PICKER
    unsigned char result;
    (void)exts;
    for (i = 0; i < 11; i++) UI_TEXT[i] = UI_MODNAME[i];
    for (i = 0; i < 11; i++) UI_MODNAME[i] = appick_modname[i];
    UI_OP = 0;
    result = run_appick();
    for (i = 0; i < 11; i++) UI_MODNAME[i] = UI_TEXT[i];
    UI_MODAL = 0;
    if (!result) return 0;
#else
    UI_OP = 3;
    pack_exts(exts);
    if (!run_ui()) return 0;
#endif
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
