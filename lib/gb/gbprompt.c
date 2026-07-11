/* gbprompt.c - libgb name-entry dialog (#114), an OPT-IN module.
 *
 * gb_prompt is split out from gbdlg.c so an app that only shows a list popup
 * (ICONED: Load / Save) doesn't link a text-entry box it never uses. build_capp.sh
 * links this only when PROMPT=1 (which implies DIALOGS=1 - it uses gb_modal_set from
 * gbdlg.c). Apps with a Save-As / New-name flow (PAINT, NOTEPAD) set both.
 *
 * Like gb_popup it is MODAL (raises the shared dlg_modal via gb_modal_set), leaves
 * the cursor SHOWN and its box erased to the backdrop; the caller repaints after.
 */
#include "gb.h"

/* gb_prompt: a modal name-entry box. Normal callers get the original uppercase
 * 8.3 editor (<=12 chars). The paged Browser settings dialog sets bit 7 of
 * maxlen for a scrolling, case-preserving value editor; the low seven bits are
 * then the real limit and the caller's existing value is retained. */
unsigned char gb_prompt(const char *caption, char *buf, unsigned char maxlen)
{
    unsigned char x = 12, y = 60, w = 52, h = 34, plain = (unsigned char)(maxlen & 0x80);
    unsigned char fl = 0, c, n = 0, done = 0, ok = 0, redraw = 1;
    maxlen &= 0x7F;
    if (!plain && maxlen > 12) maxlen = 12;
    if (plain) { while (buf[n] && n < maxlen) n++; buf[n] = 0; }
    else buf[0] = 0;
    gb_modal_set(1);
    while (gb_getkey()) ;                   /* drop the click's buffered keys */
    gb_curhide();
    gb_fill(x, y, w, h, 1);
    gb_frame(x, y, w, h, 2);
    gb_textbw((unsigned char)(x + 2), (unsigned char)(y + 3), caption);
    gb_curshow();
    while (!done) {
        if (redraw) {
            gb_curhide();
            gb_fill((unsigned char)(x + 2), (unsigned char)(y + 16),
                    (unsigned char)(w - 4), 8, 1);
            gb_textbw((unsigned char)(x + 2), (unsigned char)(y + 16),
                      plain && n > 30 ? buf + n - 30 : buf);
            gb_curshow();
            redraw = 0;
        }
        fl = gb_poll();
        if (fl & GB_QUIT) { done = 1; break; }       /* ESC -> cancel */
        while ((c = gb_getkey()) != 0) {
            if (c == 0x0D) { done = 1; ok = (unsigned char)(n > 0); break; }
            else if ((c == 0x08 || c == 0x7F) && n) { buf[--n] = 0; redraw = 1; }
            else if (c >= 32 && c < 127 && n < maxlen) {
                if (!plain && c >= 'a' && c <= 'z') c = (unsigned char)(c - 32);
                buf[n++] = (char)c; buf[n] = 0; redraw = 1;
            }
        }
    }
    gb_modal_set(0);
    if (fl & GB_QUIT) while (gb_poll() & GB_QUIT) ;
    gb_curhide();
    gb_fill(x, y, w, h, 0);
    gb_curshow();
    return ok;
}
