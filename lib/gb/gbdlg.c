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
 * itself with gb_modal_set(1)/(0) for the same effect. gb_popup saves-under its box
 * and restores it on close (#191), so the close is seamless and the caller repaints
 * only if the menu ACTION changed its content (its own draw brackets gb_curhide/show).
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

/* gb_popup_close: ask the live gb_popup loop to close (cancel). The kernel consumes
 * a click on a menu *title* (the bar is kernel-owned) before the popup loop can see
 * it as a click-away, so a re-click of the title can't close the menu by itself -
 * the title handler calls this to make the toggle work. */
static unsigned char dlg_close;
void          gb_popup_close(void)           { dlg_close = 1; }

/* pop_row: paint row i of a popup either normal (black-on-white) or reverse
 * (white-on-black, for the row under the pointer). The text call paints its own
 * paper behind the glyphs, so no separate fill is needed. Bracket with
 * gb_curhide/show. */
static void pop_row(unsigned char x, unsigned char y,
                    const char *label, unsigned char i, unsigned char rev)
{
    unsigned char ty = (unsigned char)(y + 2 + i * 10);
    if (rev) gb_textrev((unsigned char)(x + 1), ty, label);
    else     gb_textbw ((unsigned char)(x + 1), ty, label);
}

/* #191: save-under buffer for a TRANSPARENT close. The popup saves the screen it
 * covers on open and restores it on close, so a menu leaves the screen pixel-identical
 * - no hole to repair, nothing repainted underneath, no flash. Sized for the menu
 * dropdowns (File/Edit/View/System, <=8 short items); a taller popup (the file picker's
 * full directory list) doesn't fit and falls back to the old erase + damaged-repaint,
 * whose caller repaints behind it anyway. Lives in the paged GBUI module's data.
 * Sized so the System menu (its widest item "Activate screensaver" -> 33x64 = 2112 B)
 * still saves-under: a wide menu that overflowed fell back to erase, and gb_doc_frame's
 * cancel path doesn't repaint -> a hole in the wallpaper on close (#221). 2560 fits the
 * 2112-B System menu with margin while the GBUI module's data still ends below #8000. */
#define POP_BUFSZ 2560
static unsigned char pop_under[POP_BUFSZ];

/* gb_popup: THE GEOBENCH dropdown menu - one implementation every menu uses (the
 * desktop's System menu and every app's title menus), so they all look and behave
 * the same. A framed black-on-white list at (col,line), auto-sized to the longest
 * label; the row under the pointer highlights in reverse video; a click in a row
 * selects it, a click away or ESC cancels. Returns the clicked row, or 0xFF if
 * cancelled. Raises gb_modal() while up (so a caller's on_event ignores top-bar
 * clicks - re-clicking the menu title then closes the menu instead of re-arming
 * it). Saves-under + restores its box so the close is seamless (#191); only a popup
 * too tall to buffer falls back to erasing the box for the caller to repaint. */
/* POP_MAXVIS: how many rows a dropdown shows at once. A longer list (the screensaver
   Module picker once every .SAV is counted, the file picker) is capped to this and
   SCROLLS - the box shifts up to fit on screen and the pointer drives the scroll:
   pushing the cursor past the top/bottom visible row pages the list (the cursor keys
   ARE the pointer on this hardware - k_getkey drops them - so this is "scroll with the
   cursor keys"). Up/down "^"/"v" hints mark a list that has more above/below. Short
   menus (System, File/Edit/View) are <= this, so they look and behave exactly as before. */
#define POP_MAXVIS 10
#define POP_SCROLL_DIV 4                     /* poll frames between scroll steps (held) */

static void pop_draw(unsigned char x, unsigned char y, unsigned char w,
                     unsigned char boxh, const char *const *labels,
                     unsigned char top, unsigned char vis, unsigned char n)
{
    unsigned char i;
    gb_fill(x, y, w, boxh, 1);              /* white box + black frame */
    gb_frame(x, y, w, boxh, 2);
    for (i = 0; i < vis; i++)
        gb_textbw((unsigned char)(x + 1), (unsigned char)(y + 2 + i * 10), labels[top + i]);
    if (top > 0)                            /* more items above */
        gb_textbw((unsigned char)(x + w - 2), (unsigned char)(y + 2), "^");
    if ((unsigned char)(top + vis) < n)     /* more items below */
        gb_textbw((unsigned char)(x + w - 2),
                  (unsigned char)(y + 2 + (vis - 1) * 10), "v");
}

unsigned char gb_popup(unsigned char x, unsigned char y,
                       const char *const *labels, unsigned char n)
{
    unsigned char i, flags, sel = 0xFF, esc = 0, w, c, longest = 0, hot = 0xFF, over;
    unsigned char saved, vis, top = 0, sdiv = 0, ybot;
    unsigned char boxh;

    for (i = 0; i < n; i++) {               /* width = longest label + padding */
        c = 0; while (labels[i][c]) c++;
        if (c > longest) longest = c;
    }
    w = (unsigned char)((longest * 6) / 4 + 4);   /* 6px glyphs over 4px bytes (+1 col: scroll hint) */
    vis = (n < POP_MAXVIS) ? n : POP_MAXVIS;      /* cap visible rows; the rest scroll */
    boxh = (unsigned char)(vis * 10 + 4);
    if ((unsigned char)(y + boxh) > 198)          /* shift up so the box fits on screen */
        y = (unsigned char)(198 - boxh);
    if (y < 8) y = 8;                             /* never under the top bar (8px tall) */
    ybot = (unsigned char)(y + 2 + vis * 10);

    dlg_modal = 1;
    dlg_close = 0;
    gb_curhide();
    saved = (unsigned char)((unsigned int)w * boxh <= POP_BUFSZ);   /* #191: small enough to save-under? */
    if (saved) gb_saverect(x, y, w, boxh, pop_under);
    pop_draw(x, y, w, boxh, labels, top, vis, n);
    gb_curshow();
    for (;;) {
        flags = gb_poll();
        if (dlg_close) { esc = 1; break; }           /* a title re-click asked us to close */

        if (n > vis) {                               /* scroll when the pointer pushes past an edge */
            unsigned char my = gb_my();
            if (my < (unsigned char)(y + 2) && top > 0) {
                if (++sdiv >= POP_SCROLL_DIV) {
                    sdiv = 0; top--; hot = 0xFF;
                    gb_curhide(); pop_draw(x, y, w, boxh, labels, top, vis, n); gb_curshow();
                }
            } else if (my >= ybot && (unsigned char)(top + vis) < n) {
                if (++sdiv >= POP_SCROLL_DIV) {
                    sdiv = 0; top++; hot = 0xFF;
                    gb_curhide(); pop_draw(x, y, w, boxh, labels, top, vis, n); gb_curshow();
                }
            } else sdiv = 0;
        }

        over = 0xFF;                                 /* which visible row is the pointer over? */
        if (gb_my() >= (unsigned char)(y + 2) && gb_my() < ybot &&
            gb_mx() >= x && gb_mx() < (unsigned char)(x + w)) {
            unsigned char r = (unsigned char)((gb_my() - (y + 2)) / 10);
            if (r < vis) over = r;
        }
        if (over != hot) {                           /* move the reverse-video highlight */
            gb_curhide();
            if (hot  != 0xFF) pop_row(x, y, labels[top + hot],  hot,  0);
            if (over != 0xFF) pop_row(x, y, labels[top + over], over, 1);
            gb_curshow();
            hot = over;
        }
        if (flags & GB_QUIT) { esc = 1; break; }     /* ESC closes the menu */
        if (flags & GB_CLICK) { if (over != 0xFF) sel = (unsigned char)(top + over); break; }
    }
    dlg_modal = 0;
    /* Consume the click/ESC that ended the menu so it doesn't leak into POLL_FLAGS,
       where wm_chrome_frame would re-process it as a WINDOW click (#153: a menu
       selection over the title bar hit the close gadget -> the window vanished). */
    while (gb_poll() & (GB_QUIT | GB_CLICK)) ;
    (void)esc;
    gb_curhide();
    if (saved) {
        /* #191: put back exactly what the menu covered - no hole, nothing repainted
           underneath, no flash. The caller repaints only if its CONTENT changed. */
        gb_restorerect(x, y, w, boxh, pop_under);
        gb_curshow();
    } else {
        /* fallback (a popup too tall to buffer, e.g. the file picker's full list):
           the old erase-to-backdrop + damage-clipped repaint - the caller repaints
           behind it. Damage = this box UNION the focused window (#153). */
        gb_fill(x, y, w, boxh, 0);
        gb_curshow();
        {
            unsigned char wx = gb_wm_x(), wy = gb_wm_y();
            unsigned char wr = (unsigned char)(wx + gb_wm_w());
            unsigned char wb = (unsigned char)(wy + gb_wm_h());
            unsigned char br = (unsigned char)(x + w), bb = (unsigned char)(y + boxh);
            unsigned char lx = (x < wx) ? x : wx;
            unsigned char ty = (y < wy) ? y : wy;
            unsigned char rx = (br > wr) ? br : wr;
            unsigned char by = (bb > wb) ? bb : wb;
            gb_wm_damage(lx, ty, (unsigned char)(rx - lx), (unsigned char)(by - ty));
        }
    }
    return sel;
}
