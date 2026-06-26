/* settings - the GEOBENCH control panel (#129).
 *
 * The single, discoverable place to personalise GEOBENCH. It edits GEOBENCH.CFG (the
 * same key=value file the kernel reads at boot and the GBCFG module parses) and saves
 * it, so the choice persists. Phase 1 covers the three appearance keys the kernel
 * already applies at boot:
 *     FONT=<stem>    a .FNT font set      (kernel font_init)
 *     ICONS=<stem>   a .IST icon set      (kernel icon_init)
 *     CURSOR=<stem>  a .SPR pointer sprite(kernel cursor_init)
 * Each row shows the current value; clicking it lists the matching files in the
 * /GBENCH system folder and offers them in a popup. The kernel loads font/icons/cursor
 * only at boot, so a change takes effect on the next boot (noted in the window).
 *
 * Designed to grow (#129): the `rows` table is data-driven, so later settings - desktop
 * colours (INKS=, needs a kernel palette key), a backdrop pattern and a screensaver
 * (both need #128) - drop in as more rows once their kernel support exists.
 *
 * Directory care: app file I/O (gb_fs_load/save) targets the current browse drive+dir,
 * while the system files live in /GBENCH on the BOOT drive. So we (a) pin the drive to
 * the boot drive (card if present, else floppy A - mirrors the kernel's fs_init) before
 * every FS op, and (b) only ever descend one level (root -> GBENCH -> root), which is
 * the safe depth-1 navigation case.
 */
#include "gb.h"

#define TITLE_H   14
#define DEF_X     18
#define DEF_Y     32
#define DEF_W     46           /* byte cols (184 px) */
#define DEF_H     128          /* lines (room for the 5 picker rows + the 5-pen colours editor) */
#define ROW_H     12           /* per-setting row height, px */
#define VAL_COL   16           /* value column offset from the window's left (byte cols); a
                                  gap past the longest label ("Backdrop") so value != label */
#define COLOUR_ROW NROWS       /* the "Colours..." line sits below the picker rows */

static unsigned char win_x, win_y, win_w, win_h;
static void s_draw(void);      /* forward: the colours editor repaints the window on exit */

/* MIN_IST_ICONS: the minimum icon count for an .IST to be offered as the desktop icon
   set. A desktop set must supply every slot the kernel draws - 25 icons since #198 dropped
   the duplicate icon_iconset slot (DEFAULT.IST/REFINED.IST are now 25; was 26). A small
   toolchest like PAINT.IST (5 tool icons) stays filtered out. Keep this in step with the
   GBIS count of build/DEFAULT.IST (tools/build_kernel.sh packicons list) - if it drifts
   ABOVE the real count, every full set is dropped and the Icons picker shows "No files
   found" (#209). */
#define MIN_IST_ICONS 25

/* one configurable setting: a label, its GEOBENCH.CFG key (with '='), the 3-char file
   extension to list, and (for icon sets) the minimum icon count to qualify. */
typedef struct {
    const char *label;
    const char *key;       /* e.g. "FONT=" */
    const char *ext;       /* e.g. "FNT" (raw 3-char, matched against the 8.3 name) */
    unsigned char min_icons;  /* IST: min header count to be a usable set; 0 = no check */
    unsigned int  tfr;     /* kernel transfer-area addr for the 8.3 name (gb_reload, #185) */
} setting_t;

static const setting_t rows[] = {
    { "Font",   "FONT=",     "FNT", 0,             0x120D },  /* KCFG_FONTNAME */
    { "Icons",  "ICONS=",    "IST", MIN_IST_ICONS, 0x1202 },  /* KCFG_ICONNAME */
    { "Cursor", "CURSOR=",   "SPR", 0,             0x1221 },  /* KCFG_CURSORNAME */
    { "Backdrop","BACKDROP=","BDP", 0,             0x1231 },  /* KCFG_BDPNAME (+ BD_SOLID #1290) */
    { "Wallpaper","WALLPAPER=","PIC", 0,           0 },       /* no live tfr: the desktop reads
                                                                 WALLPAPER= from the config (#216) */
};
#define NROWS 5
#define BD_SOLID_ADDR 0x1290   /* kernel BD_SOLID flag */

/* GEOBENCH.CFG is loaded once into a full-sector buffer (gb_fs_load copies WHOLE
   512-byte sectors, so a smaller buffer would overflow into the globals after it). */
static char cfgbuf[512];
static unsigned int cfglen;

/* the popup file list: stems of the matching files in /GBENCH. Flat buffer + a pointer
   array (a 2D char array indexed by a uchar wraps the *width at 8 bits - see the FM). */
#define MAXST 16
#define STLEN 9
static char stembuf[MAXST * STLEN];
static const char *stems[MAXST];
static unsigned char nstem;

/* sel_boot: pin the active drive to the boot drive (Disk C if a card is present, else
   floppy A), where GEOBENCH.CFG + /GBENCH live - mirrors the kernel's fs_init. Another
   co-resident window may have left the global drive elsewhere, so we re-assert it
   before every FS op. */
static void sel_boot(void)
{
    unsigned char d = gb_drives();
    gb_set_drive((d & GB_DRV_C) ? GB_DRIVE_C : GB_DRIVE_A);
}

/* ---- GEOBENCH.CFG read/write (generic, key includes the '=') ----------------- */

/* cfg_keypos: index just past KEY's '=' (KEY must sit at a line start), or 0xFFFF. */
static unsigned int cfg_keypos(const char *key)
{
    unsigned char kl = 0, j;
    unsigned int i;
    while (key[kl]) kl++;
    for (i = 0; i + kl <= cfglen; i++) {
        if (i && cfgbuf[i-1] != '\r' && cfgbuf[i-1] != '\n') continue;   /* line start only */
        for (j = 0; j < kl; j++) if (cfgbuf[i+j] != key[j]) break;
        if (j == kl) return i + kl;
    }
    return 0xFFFF;
}

/* cfg_get: copy KEY's value (up to 8 chars, to the line end) into dst; "-" if absent. */
static void cfg_get(const char *key, char *dst)
{
    unsigned int p = cfg_keypos(key);
    unsigned char j = 0;
    if (p != 0xFFFF)
        while (p < cfglen && cfgbuf[p] != '\r' && cfgbuf[p] != '\n' && j < 8)
            dst[j++] = cfgbuf[p++];
    if (j == 0) dst[j++] = '-';
    dst[j] = 0;
}

/* cfg_set: write val into KEY's line (replace in place, preserving other keys; append
   the line if KEY is absent), then save GEOBENCH.CFG to the boot drive. Best-effort. */
static void cfg_set(const char *key, const char *val)
{
    unsigned char kl = 0, vl = 0;
    unsigned int p, end, i;
    while (key[kl]) kl++;
    while (val[vl]) vl++;
    if (cfglen == 0) return;                 /* no config loaded -> nothing to update */

    p = cfg_keypos(key);
    if (p == 0xFFFF) {                        /* no such key: append "KEY=val\r\n" */
        if (cfglen + kl + vl + 2 > sizeof(cfgbuf)) return;
        for (i = 0; i < kl; i++) cfgbuf[cfglen + i] = key[i];
        cfglen += kl;
        for (i = 0; i < vl; i++) cfgbuf[cfglen + i] = val[i];
        cfglen += vl;
        cfgbuf[cfglen++] = '\r'; cfgbuf[cfglen++] = '\n';
    } else {                                  /* replace the value in place */
        end = p;
        while (end < cfglen && cfgbuf[end] != '\r' && cfgbuf[end] != '\n') end++;
        if (vl > (unsigned char)(end - p)) {            /* grow: shift the tail right */
            unsigned int d = vl - (end - p);
            if (cfglen + d > sizeof(cfgbuf)) return;
            for (i = cfglen; i > end; i--) cfgbuf[i - 1 + d] = cfgbuf[i - 1];
            cfglen += d;
        } else if (vl < (unsigned char)(end - p)) {     /* shrink: shift the tail left */
            unsigned int d = (end - p) - vl;
            for (i = end; i < cfglen; i++) cfgbuf[i - d] = cfgbuf[i];
            cfglen -= d;
        }
        for (i = 0; i < vl; i++) cfgbuf[p + i] = val[i];
    }
    sel_boot();
    gb_set_name("GEOBENCHCFG");
    gb_fs_save(cfgbuf, cfglen);
}

/* ---- /GBENCH enumeration ----------------------------------------------------- */

/* enter_sys: at the (root) browse dir, descend into the GBENCH system folder if it is
   present; return 1 if we descended (the caller pairs it with gb_back). A flat layout
   (e.g. a floppy with no GBENCH subdir) returns 0 - enumerate the root as-is. */
static unsigned char enter_sys(void)
{
    char *p = gb_dir1();
    while (p) {
        if (gb_isdir()) {
            const char *r = gb_entname();
            if (r[0]=='G' && r[1]=='B' && r[2]=='E' && r[3]=='N'
                && r[4]=='C' && r[5]=='H' && r[6]==' ') {
                gb_chdir();                  /* positioned on GBENCH: descend */
                return 1;
            }
        }
        p = gb_dirn();
    }
    return 0;
}

/* ist_count: load the icon set `stem`.IST into the kernel copy buffer (low RAM, big
   enough for a full set, so no app bank is spent) and return its GBIS header icon
   count - 0 if it isn't a valid set or is too big to load. */
static unsigned char ist_count(const char *stem)
{
    char nm[11];
    unsigned char k;
    unsigned int n;
    for (k = 0; k < 8; k++) nm[k] = ' ';
    for (k = 0; k < 8 && stem[k]; k++) nm[k] = stem[k];
    nm[8] = 'I'; nm[9] = 'S'; nm[10] = 'T';
    gb_set_name(nm);
    n = gb_fs_load(gb_copybuf, GB_COPYMAX);
    if (n < 16 || gb_copybuf[0] != 'G' || gb_copybuf[1] != 'B'
        || gb_copybuf[2] != 'I' || gb_copybuf[3] != 'S') return 0;
    return (unsigned char)gb_copybuf[5];
}

/* enumerate: fill stems[] with the names of files in /GBENCH whose extension is `ext`.
   If min_icons is non-zero (icon sets), drop any .IST with fewer icons than that - i.e.
   the app toolchests, which can't supply every desktop slot. */
static void enumerate(const char *ext, unsigned char min_icons)
{
    unsigned char descended, k, i, keep;
    unsigned int off;
    char *p;

    nstem = 0;
    sel_boot();
    descended = enter_sys();

    /* pass 1: collect the matching stems (NO file load here - that would disturb the
       gb_dir1/gb_dirn enumerator mid-scan). */
    p = gb_dir1();
    while (p && nstem < MAXST) {
        if (!gb_isdir()) {
            const char *r = gb_entname();
            if (r[8]==ext[0] && r[9]==ext[1] && r[10]==ext[2]) {
                off = (unsigned int)nstem * STLEN;
                for (k = 0; k < 8 && r[k] != ' '; k++) stembuf[off + k] = r[k];
                stembuf[off + k] = 0;
                stems[nstem] = &stembuf[off];
                nstem++;
            }
        }
        p = gb_dirn();
    }

    /* pass 2: icon-set count filter (after the scan, still inside /GBENCH so the loads
       resolve). Compact the keepers down over the dropped entries. */
    if (min_icons) {
        keep = 0;
        for (i = 0; i < nstem; i++) {
            if (ist_count(&stembuf[(unsigned int)i * STLEN]) < min_icons) continue;
            if (keep != i)
                for (k = 0; k < STLEN; k++)
                    stembuf[(unsigned int)keep * STLEN + k] = stembuf[(unsigned int)i * STLEN + k];
            stems[keep] = &stembuf[(unsigned int)keep * STLEN];
            keep++;
        }
        nstem = keep;
    }

    if (descended) gb_back();                /* GBENCH -> root (depth-1, safe) */
}

/* ---- drawing ----------------------------------------------------------------- */

static unsigned char row_y(unsigned char r)
{
    return (unsigned char)(win_y + TITLE_H + 4 + r * ROW_H);
}

/* paint the content: a white panel, each setting's label + current value, and a note
   that changes apply on the next boot. The WM already drew the frame/title/close. */
static void s_draw(void)
{
    unsigned char r;
    char val[10];
    win_x = gb_wm_x(); win_y = gb_wm_y(); win_w = gb_wm_w(); win_h = gb_wm_h();
    gb_fill(win_x, (unsigned char)(win_y + TITLE_H), win_w,
            (unsigned char)(win_h - TITLE_H), 1);          /* white panel */
    for (r = 0; r < NROWS; r++) {
        gb_textbw((unsigned char)(win_x + 1), row_y(r), rows[r].label);
        cfg_get(rows[r].key, val);
        gb_textbw((unsigned char)(win_x + VAL_COL), row_y(r), val);
    }
    gb_textbw((unsigned char)(win_x + 1), row_y(COLOUR_ROW), "Colours...");
    gb_textbw((unsigned char)(win_x + 1), (unsigned char)(win_y + win_h - 10),
              "Font/icons: reboot.");
}

/* ---- desktop colours (INKS=) ------------------------------------------------ */

/* 5 colours: the 4 Mode-1 pens + the screen border (its own CPC ink). */
#define NPEN 5
static const char *const pen_lbl[NPEN] = { "Paper", "Text", "Edge", "Accent", "Border" };
static unsigned char ink_cur[NPEN], ink_orig[NPEN];

/* apply a colour live: pens 0-3 via SCR SET INK (&BC32), the border via SCR SET BORDER
   (&BC38). A palette change recolours every pixel of that pen at once, so the whole UI
   updates with no redraw - that is the preview (and, on Save, the immediate effect). */
static volatile unsigned char si_pen, si_ink;
static void si_call(void) __naked
{
__asm
    ld   a,(_si_ink)
    ld   b,a
    ld   c,a
    ld   a,(_si_pen)
    call 0xBC32          ; SCR SET INK (A = pen, B/C = ink)
    ret
__endasm;
}
static void sb_call(void) __naked
{
__asm
    ld   a,(_si_ink)
    ld   b,a
    ld   c,a
    call 0xBC38          ; SCR SET BORDER (B/C = ink)
    ret
__endasm;
}
static void apply_colour(unsigned char i, unsigned char ink)
{
    si_ink = ink;
    if (i < 4) { si_pen = i; si_call(); }
    else sb_call();
}

/* cfg_get_inks: parse INKS= into out[NPEN]; the default palette (1,26,0,6,1) when
   absent. (cfg_get can't be reused - an INKS value can exceed its 8-char cap.) */
static void cfg_get_inks(unsigned char *out)
{
    unsigned int p = cfg_keypos("INKS=");
    unsigned char i;
    out[0] = 1; out[1] = 26; out[2] = 0; out[3] = 6; out[4] = 1;
    if (p == 0xFFFF) return;
    for (i = 0; i < NPEN && p < cfglen; i++) {
        unsigned int v = 0;
        unsigned char got = 0;
        while (p < cfglen && cfgbuf[p] >= '0' && cfgbuf[p] <= '9') { v = v*10 + (cfgbuf[p]-'0'); p++; got = 1; }
        if (got) out[i] = (unsigned char)(v > 26 ? 26 : v);
        if (p >= cfglen || cfgbuf[p] == '\r' || cfgbuf[p] == '\n') break;
        if (cfgbuf[p] == ',') p++;
    }
}

/* cfg_set_inks: write the 5 colours as "d,l,k,a,b" into INKS= and save. */
static void cfg_set_inks(const unsigned char *inks)
{
    char s[18];
    unsigned char i, j = 0, v;
    for (i = 0; i < NPEN; i++) {
        v = inks[i];
        if (v >= 10) s[j++] = (char)('0' + v / 10);
        s[j++] = (char)('0' + v % 10);
        if (i < NPEN - 1) s[j++] = ',';
    }
    s[j] = 0;
    cfg_set("INKS=", s);
}

static unsigned char colp_y(unsigned char i) { return (unsigned char)(win_y + TITLE_H + 13 + i * 12); }

static void colp_num(unsigned char i)        /* draw pen i's ink number (00-26) */
{
    char t[3];
    unsigned char v = ink_cur[i];
    t[0] = (char)((v >= 10) ? '0' + v / 10 : ' ');
    t[1] = (char)('0' + v % 10);
    t[2] = 0;
    gb_fill((unsigned char)(win_x + 13), colp_y(i), 3, 8, 1);
    gb_textbw((unsigned char)(win_x + 13), colp_y(i), t);
}

static void colp_draw(void)
{
    unsigned char i, by = (unsigned char)(win_y + win_h - 11);
    gb_fill(win_x, (unsigned char)(win_y + TITLE_H), win_w,
            (unsigned char)(win_h - TITLE_H), 1);
    gb_textbw((unsigned char)(win_x + 1), (unsigned char)(win_y + TITLE_H + 1), "Desktop colours");
    for (i = 0; i < NPEN; i++) {
        gb_textbw((unsigned char)(win_x + 1),  colp_y(i), pen_lbl[i]);
        gb_textbw((unsigned char)(win_x + 11), colp_y(i), "-");
        colp_num(i);
        gb_textbw((unsigned char)(win_x + 17), colp_y(i), "+");
    }
    gb_textbw((unsigned char)(win_x + 1), by, "Save");
    gb_textbw((unsigned char)(win_x + 8), by, "Cancel");
}

/* colours_dialog: modal 4-pen editor. Each -/+ steps a pen's CPC ink (0-26, wrapping)
   and applies it live. Save writes INKS= and keeps the live palette (so it also takes
   effect at once); Cancel / ESC restore the inks the dialog opened with. */
static void colours_dialog(void)
{
    unsigned char i, flags = 0, done = 0;
    cfg_get_inks(ink_cur);
    for (i = 0; i < NPEN; i++) ink_orig[i] = ink_cur[i];
    gb_modal_set(1);
    gb_curhide();
    colp_draw();
    gb_curshow();
    while (!done) {
        flags = gb_poll();
        if (flags & GB_QUIT) {                       /* ESC = cancel: restore + leave */
            for (i = 0; i < NPEN; i++) apply_colour(i, ink_orig[i]);
            done = 1;
            break;
        }
        if (!(flags & GB_CLICK)) continue;
        {
            unsigned char mx = gb_mx(), my = gb_my();
            unsigned char by = (unsigned char)(win_y + win_h - 11);
            if (my >= by && my < by + 8) {
                if (mx >= win_x + 1 && mx < win_x + 7) {            /* Save */
                    cfg_set_inks(ink_cur);
                    done = 1;
                } else if (mx >= win_x + 8 && mx < win_x + 18) {    /* Cancel */
                    for (i = 0; i < NPEN; i++) apply_colour(i, ink_orig[i]);
                    done = 1;
                }
            } else {
                for (i = 0; i < NPEN; i++) {
                    unsigned char ry = colp_y(i);
                    if (my < ry || my >= ry + 8) continue;
                    if (mx >= win_x + 10 && mx < win_x + 13)          /* - */
                        ink_cur[i] = (unsigned char)((ink_cur[i] == 0) ? 26 : ink_cur[i] - 1);
                    else if (mx >= win_x + 16 && mx < win_x + 20)     /* + */
                        ink_cur[i] = (unsigned char)((ink_cur[i] >= 26) ? 0 : ink_cur[i] + 1);
                    else continue;
                    apply_colour(i, ink_cur[i]);                     /* live preview */
                    gb_curhide(); colp_num(i); gb_curshow();
                    break;
                }
            }
        }
    }
    if (flags & GB_QUIT) while (gb_poll() & GB_QUIT) ;   /* swallow the ESC repeat */
    gb_modal_set(0);
    gb_curhide();
    s_draw();
    gb_curshow();
}

/* ---- interaction ------------------------------------------------------------- */

/* live_apply: write the chosen 8.3 name into the kernel transfer area for row r and
   call gb_reload, so the font/icon set/cursor/backdrop change shows with no reboot
   (#185). For the backdrop, also set BD_SOLID. */
static void live_apply(unsigned char r, const char *name)
{
    const char *ext = rows[r].ext;
    /* Wallpaper (PIC) has NO live kernel transfer cell: the desktop reads WALLPAPER= from the
       config text itself at boot (#216 - every fixed cell collided; #1700 broke the System
       menu). cfg_set already persisted it; it applies on the next reboot. */
    if (ext[0] != 'P') {
        char *dst = (char *)rows[r].tfr;
        unsigned char i = 0;
        while (i < 8 && name[i]) { dst[i] = name[i]; i++; }
        while (i < 8) dst[i++] = ' ';
        dst[8] = ext[0]; dst[9] = ext[1]; dst[10] = ext[2];
        if (ext[0] == 'B')                       /* backdrop: BD_SOLID = (name == "SOLID") */
            *(unsigned char *)BD_SOLID_ADDR =
                (unsigned char)(name[0]=='S' && name[1]=='O' && name[2]=='L' &&
                                name[3]=='I' && name[4]=='D' && name[5]==0);
    }
    gb_reload();
}

/* open_picker: list the files for row r and let the user pick one; write it to the
   config and repaint. */
static void open_picker(unsigned char r)
{
    const char *list[MAXST + 1];
    unsigned char sel, i, n = 0;
    const char *ext = rows[r].ext;
    enumerate(ext, rows[r].min_icons);
    if (ext[0] == 'B') list[n++] = "SOLID";  /* the Backdrop list leads with SOLID (no tile) */
    else if (ext[0] == 'P') list[n++] = "NONE";  /* the Wallpaper list leads with NONE (#212) */
    for (i = 0; i < nstem; i++) list[n++] = stems[i];
    if (n == 0) {
        gb_alert("No files found", "in /GBENCH.");
        s_draw();
        return;
    }
    sel = gb_popup((unsigned char)(win_x + VAL_COL), row_y(r), list, n);
    gb_curhide();
    if (sel != 0xFF) {
        cfg_set(rows[r].key, list[sel]);     /* persist to GEOBENCH.CFG */
        live_apply(r, list[sel]);            /* ...and apply now, no reboot (#185) */
        gb_wm_damage(0, 0, 80, 200);         /* assets changed everywhere -> full repaint */
        gb_restore_parent();                 /* desktop + windows redraw with the new assets */
    }
    s_draw();                                /* repaint our content (new font/value) */
    gb_curshow();
}

/* a content press: which row was clicked? */
static void s_click(void)
{
    unsigned char my, r;
    win_x = gb_wm_x(); win_y = gb_wm_y(); win_w = gb_wm_w(); win_h = gb_wm_h();
    my = gb_my();
    for (r = 0; r < NROWS; r++) {
        unsigned char ry = row_y(r);
        if (my >= (unsigned char)(ry - 2) && my < (unsigned char)(ry + ROW_H - 2)) {
            open_picker(r);
            return;
        }
    }
    {
        unsigned char ry = row_y(COLOUR_ROW);
        if (my >= (unsigned char)(ry - 2) && my < (unsigned char)(ry + ROW_H - 2))
            colours_dialog();
    }
}

static void s_drag(void)
{
    win_x = gb_wm_x(); win_y = gb_wm_y();
    if (gb_drag_window(&win_x, &win_y, gb_wm_w(), gb_wm_h())) {
        gb_wm_setpos(win_x, win_y);
        gb_restore_parent();
    }
}

static void s_proc(void)
{
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  s_draw();      break;
        case GB_MSG_CLICK: s_click();     break;
        case GB_MSG_CLOSE: gb_wm_close(); break;
        case GB_MSG_DRAG:  s_drag();      break;
    }
}

static const gb_mwin_t smw = {
    DEF_X, DEF_Y, DEF_W, DEF_H, 0, 0, s_proc, "Settings"
};

void main(void)
{
    unsigned char n;
    gb_wm_managed(&smw);                            /* register FIRST (no draw), like the other apps */
    sel_boot();
    gb_set_name("GEOBENCHCFG");
    cfglen = gb_fs_load(cfgbuf, sizeof(cfgbuf));   /* load the config once (0 if none) */
    for (n = 64; n; n--) if (!gb_getkey()) break;  /* drain the launch keystrokes (#142) */
    gb_restore_parent();                            /* first paint: WM chrome + s_draw */
}
