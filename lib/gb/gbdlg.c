/* gbdlg.c - libgb modal-list dialog (#114), an OPT-IN module.
 *
 * gb_popup (a list menu) + the shared modal flag are the dialog building blocks the
 * menu-driven apps (PAINT, NOTEPAD, ICONED, and any future one) reuse, so they live
 * in one place with one consistent look. Unlike gbwin.c (linked into every app),
 * this object is linked ONLY by apps that ask for it - build_capp.sh adds it when
 * DIALOGS=1 - so a dialog-free app (file manager, desktop, clock) carries none of
 * it. The text-entry box lives separately in gbprompt.c (PROMPT=1), so a popup-only
 * app like ICONED doesn't pay for a prompt it never shows.
 *
 * gb_popup is MODAL: it runs its own gb_poll loop while up and raises the shared
 * dlg_modal flag, so an app's on_event can ignore top-bar clicks meanwhile
 * (re-clicking the menu title then just closes the popup via click-away instead of
 * re-arming the menu). A custom app dialog (e.g. NOTEPAD's "Save changes?") brackets
 * itself with gb_modal_set(1)/(0) for the same effect. gb_popup leaves the cursor
 * SHOWN and its box erased to the backdrop; the caller repaints its window after
 * (its own draw brackets gb_curhide/gb_curshow).
 *
 * Plug-in recipe for a new app: put a menu def in your gb_win_t.menu + an on_event
 * that sets a "want_menu" flag when a title is clicked AND !gb_modal(); in on_frame,
 * when want_menu, call gb_popup(titleCol, 8, items, n), dispatch the row to your
 * New/Load/Save handlers, then repaint. Add gbprompt.c (PROMPT=1) for a Save-As name.
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
