/* gbdlg.c - libgb modal dialogs (#114), an OPT-IN module.
 *
 * gb_popup (a list menu) and gb_prompt (a name field) are the dialog primitives
 * the menu-driven apps (PAINT, NOTEPAD, ICONED, and any future one) reuse, so they
 * live in one place with one consistent look. Unlike gbwin.c (linked into every
 * app), this object is linked ONLY by apps that need dialogs - build_capp.sh adds
 * it when DIALOGS=1 - so a dialog-free app (the file manager, the desktop, the
 * clock) carries none of this code.
 *
 * Both dialogs are MODAL: they run their own gb_poll loop while up and raise the
 * shared dlg_modal flag, so an app's on_event can ignore top-bar clicks meanwhile
 * (re-clicking the menu title then just closes the popup via click-away instead of
 * re-arming the menu). A custom app dialog (e.g. NOTEPAD's "Save changes?") brackets
 * itself with gb_modal_set(1)/(0) for the same effect. Both leave the cursor SHOWN
 * and the popup area erased to the backdrop; the caller repaints its window after
 * (its own draw brackets gb_curhide/gb_curshow).
 *
 * Plug-in recipe for a new app: put a menu def in your gb_win_t.menu + an on_event
 * that sets a "want_menu" flag when a title is clicked AND !gb_modal(); in on_frame,
 * when want_menu, call gb_popup(titleCol, 8, items, n), dispatch the row to your
 * New/Load/Save handlers, then repaint. Use gb_prompt for the Save-As name.
 */
#include "gb.h"

static unsigned char dlg_modal;
unsigned char gb_modal(void)                 { return dlg_modal; }
void          gb_modal_set(unsigned char on) { dlg_modal = on; }

/* gb_popup: a framed list of n labels at (col,line), auto-sized to the longest
 * label. Returns the clicked row, or 0xFF if cancelled (clicked away / ESC). */
unsigned char gb_popup(unsigned char x, unsigned char y,
                       const char *const *labels, unsigned char n)
{
    unsigned char i, flags, row, sel = 0xFF, esc = 0, w, c, longest = 0;
    unsigned char boxh = (unsigned char)(n * 10 + 4);

    for (i = 0; i < n; i++) {               /* width = longest label + padding */
        c = 0; while (labels[i][c]) c++;
        if (c > longest) longest = c;
    }
    w = (unsigned char)((longest * 6) / 4 + 3);   /* 6px glyphs over 4px bytes */
    dlg_modal = 1;
    gb_curhide();
    gb_fill(x, y, w, boxh, 1);              /* white box + black frame */
    gb_frame(x, y, w, boxh, 2);
    for (i = 0; i < n; i++)
        gb_text((unsigned char)(x + 1), (unsigned char)(y + 2 + i * 10), labels[i]);
    gb_curshow();
    for (;;) {
        flags = gb_poll();
        if (flags & GB_QUIT) { esc = 1; break; }    /* ESC closes the menu */
        if (!(flags & GB_CLICK)) continue;
        if (gb_my() >= (unsigned char)(y + 2) && gb_my() < (unsigned char)(y + 2 + n * 10) &&
            gb_mx() >= x && gb_mx() < (unsigned char)(x + w)) {
            row = (unsigned char)((gb_my() - (y + 2)) / 10);
            if (row < n) { sel = row; break; }
        }
        break;                                       /* clicked elsewhere -> cancel */
    }
    dlg_modal = 0;
    if (esc) while (gb_poll() & GB_QUIT) ;
    gb_curhide();
    gb_fill(x, y, w, boxh, 0);              /* erase to backdrop; caller redraws */
    gb_curshow();
    return sel;
}

/* gb_prompt: a modal name-entry box. Types an uppercase name (<= maxlen, capped at
 * 12) into buf; Enter with a non-empty name -> 1, ESC / empty -> 0. */
unsigned char gb_prompt(const char *caption, char *buf, unsigned char maxlen)
{
    unsigned char x = 12, y = 60, w = 52, h = 34;
    unsigned char fl = 0, c, n = 0, done = 0, ok = 0, redraw = 1;
    if (maxlen > 12) maxlen = 12;
    dlg_modal = 1;
    buf[0] = 0;
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
            gb_textbw((unsigned char)(x + 2), (unsigned char)(y + 16), buf);
            gb_curshow();
            redraw = 0;
        }
        fl = gb_poll();
        if (fl & GB_QUIT) { done = 1; break; }       /* ESC -> cancel */
        while ((c = gb_getkey()) != 0) {
            if (c == 0x0D) { done = 1; ok = (unsigned char)(n > 0); break; }
            else if ((c == 0x08 || c == 0x7F) && n) { buf[--n] = 0; redraw = 1; }
            else if (c >= 32 && c < 127 && n < maxlen) {
                if (c >= 'a' && c <= 'z') c = (unsigned char)(c - 32);   /* 8.3 is upper */
                buf[n++] = (char)c; buf[n] = 0; redraw = 1;
            }
        }
    }
    dlg_modal = 0;
    if (fl & GB_QUIT) while (gb_poll() & GB_QUIT) ;
    gb_curhide();
    gb_fill(x, y, w, h, 0);
    gb_curshow();
    return ok;
}
