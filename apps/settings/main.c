/* settings - the GEOBENCH control panel (#129).
 *
 * The single, discoverable place to personalise GEOBENCH. It edits GEOBENCH.CFG (the
 * same key=value file the kernel reads at boot and the GBCFG module parses) and saves
 * it, so the choice persists. Phase 1 covers the three appearance keys the kernel
 * already applies at boot:
 *     FONT=<stem>    a .FNT font set      (kernel font_init)
 *     ICONS=<stem>   a .IST icon set      (kernel icon_init)
 *     CURSOR=<stem>  a .SPR pointer sprite(kernel cursor_init)
 *     BACKDROP=[D:]<stem>[.BDP]
 *     WALLPAPER=[D:]<stem>[.PIC]
 *     SAVER=[D:]<stem>[.SAV]
 *     MSXMODE=6|7       selected MSX video mode at the next boot
 * Each row shows the current value; clicking it lists the matching files in the
 * /GBENCH system folder (or root-level /PICS for wallpapers) and offers them in
 * a popup. The kernel loads font/icons/cursor only at boot, so a change takes
 * effect on the next boot (noted in the window).
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
#include "gbcfg.h"
#include "gbsaver.h"

#define TITLE_H   14
#define DEF_X     18
#define DEF_Y     32
#define DEF_W     58           /* byte cols (232 px) */
#ifdef GB_MSX2
#define DEF_H     162          /* includes the next-boot video-mode row */
#else
#define DEF_H     150
#endif
#define ROW_H     12           /* per-setting row height, px */
#define VAL_COL   16           /* value column offset from the window's left (byte cols); a
                                  gap past the longest label ("Backdrop") so value != label */
#define COLOUR_ROW NROWS       /* the "Colours..." line sits below the picker rows */
/* The screensaver section: module picker, per-saver Configure command, then timeout. */
#ifdef GB_MSX2
#define VIDEO_ROW  (NROWS + 1) /* Screen 6/7 selection; applied by GBMSX.COM at boot */
#define SS_HDR_ROW (NROWS + 2)
#define SS_MOD_ROW (NROWS + 3)
#define SS_CFG_ROW (NROWS + 4)
#define SS_TM_ROW  (NROWS + 5)
#else
#define SS_HDR_ROW (NROWS + 1)
#define SS_MOD_ROW (NROWS + 2)
#define SS_CFG_ROW (NROWS + 3)
#define SS_TM_ROW  (NROWS + 4)
#endif
#define ROW_BACKDROP 3
#define ROW_WALLPAPER 4
#define DRIVE_NONE 0xFF

static unsigned char win_x, win_y, win_w, win_h;
static void s_draw(void);      /* forward: the colours editor repaints the window on exit */
static void saver_value(char *dst);       /* forward: s_draw shows the current SAVERTIME= (#219) */
static void ss_module_value(char *dst);   /* forward: s_draw shows the current SAVER= module (#219) */
static unsigned char ss_is_starfield(void);

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
#define BD_DRIVE_ADDR 0x123C   /* kernel KCFG_BDDRIVE: selected backdrop drive */
#define BD_TILE_ADDR  0x1250   /* kernel BD_TILE: the loaded 16x16 backdrop tile (#216) */

/* GEOBENCH.CFG is loaded once into a full-sector buffer (gb_fs_load copies WHOLE
   512-byte sectors, so a smaller buffer would overflow into the globals after it). */
static char cfgbuf[512];
static unsigned int cfglen;

/* the popup file list: stems of the matching files in /GBENCH. Flat buffer + a pointer
   array (a 2D char array indexed by a uchar wraps the *width at 8 bits - see the FM). */
#define MAXST 24      /* max files a picker lists (savers/icons/fonts); the popup scrolls */
#define STLEN 11
static char stembuf[MAXST * STLEN];
static const char *stems[MAXST];
static unsigned char nstem;
static unsigned char stem_drive[MAXST];       /* source drive for each media entry */

/* sel_boot: pin the active drive to the boot drive (Disk C if a card is present, else
   floppy A), where GEOBENCH.CFG + /GBENCH live - mirrors the kernel's fs_init. Another
   co-resident window may have left the global drive elsewhere, so we re-assert it
   before every FS op. */
static void sel_boot(void)
{
    unsigned char d = gb_drives();
    gb_set_drive((d & GB_DRV_C) ? GB_DRIVE_C : GB_DRIVE_A);
}

static void sel_boot_root(void)
{
    unsigned char i;
    sel_boot();
    for (i = 0; i < 4; i++) gb_back();      /* root on FAT/path backends; no-op on floppy/root */
}

static unsigned char boot_drive(void)
{
    return (gb_drives() & GB_DRV_C) ? GB_DRIVE_C : GB_DRIVE_A;
}

static char drive_letter(unsigned char d)
{
    if (d == GB_DRIVE_A) return 'A';
    if (d == GB_DRIVE_B) return 'B';
    return 'C';
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

/* cfg_get: copy KEY's value (up to 14 chars, to the line end) into dst; "-" if absent. */
static void cfg_get(const char *key, char *dst)
{
    unsigned int p = cfg_keypos(key);
    unsigned char j = 0;
    if (p != 0xFFFF)
        while (p < cfglen && cfgbuf[p] != '\r' && cfgbuf[p] != '\n' && j < 14)
            dst[j++] = cfgbuf[p++];
    if (j == 0) dst[j++] = '-';
    dst[j] = 0;
}

static unsigned char cfg_drive(const char *key, unsigned char fallback)
{
    unsigned int p = cfg_keypos(key);
    if (p != 0xFFFF && p + 1 < cfglen && cfgbuf[p + 1] == ':') {
        if (cfgbuf[p] == 'A') return GB_DRIVE_A;
        if (cfgbuf[p] == 'B') return GB_DRIVE_B;
        if (cfgbuf[p] == 'C') return GB_DRIVE_C;
    }
    return fallback;
}

static void cfg_path(char *dst, unsigned char drive, const char *stem, const char *ext)
{
    unsigned char i = 0, j = 0;
    if (drive != boot_drive()) {
        dst[j++] = drive_letter(drive);
        dst[j++] = ':';
    }
    while (stem[i]) dst[j++] = stem[i++];
    dst[j++] = '.';
    dst[j++] = ext[0]; dst[j++] = ext[1]; dst[j++] = ext[2];
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
    sel_boot_root();
    gb_set_name("GEOBENCHCFG");
    gb_fs_save(cfgbuf, cfglen);
    /* Keep the kernel's in-memory config copy in step with the disk, so changes the
       desktop reads straight from it (the screensaver SAVER=/SAVERTIME=, #219) take
       effect without a reboot - the desktop re-parses it when it repaints. */
    {
        char *km = (char *)0x1000;                 /* KCFG_TEXT */
        unsigned int i;
        for (i = 0; i < cfglen; i++) km[i] = cfgbuf[i];
        *(volatile unsigned int *)0x1200 = cfglen; /* KCFG_LEN */
    }
}

/* ---- /GBENCH and /PICS enumeration ------------------------------------------ */

/* enter_assets: at the browse root, descend into GBENCH (system assets) or PICS
   (wallpapers). A flat floppy has neither and is enumerated at root as-is. */
static unsigned char enter_assets(unsigned char pictures)
{
    char *p = gb_dir1();
    while (p) {
        if (gb_isdir()) {
            const char *r = gb_entname();
            if ((!pictures && r[0]=='G' && r[1]=='B' && r[2]=='E' && r[3]=='N'
                 && r[4]=='C' && r[5]=='H' && r[6]==' ') ||
                (pictures && r[0]=='P' && r[1]=='I' && r[2]=='C' && r[3]=='S'
                 && r[4]==' ')) {
                gb_chdir();                  /* positioned on GBENCH/PICS: descend */
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

/* enumerate_boot: fill stems[] with the names of files in the BOOT drive's /GBENCH
   whose extension is `ext`. If min_icons is non-zero (icon sets), drop any .IST with
   fewer icons than that - i.e. the app toolchests, which can't supply every desktop
   slot. */
static void enumerate_boot(const char *ext, unsigned char min_icons)
{
    unsigned char descended, k, i, keep, old_drive;
    unsigned int off;
    char *p;
    unsigned char drive = boot_drive();
    nstem = 0;
    old_drive = gb_get_drive();
    gb_set_drive(drive);
    descended = enter_assets(0);

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
    gb_set_drive(old_drive);
}

/* enumerate_media_drive: append "<drive>:<stem>" entries from one drive's /GBENCH. */
static void enumerate_media_drive(const char *ext, unsigned char drive)
{
    unsigned char descended, k, old_drive;
    unsigned int off;
    char *p;
    old_drive = gb_get_drive();
    gb_set_drive(drive);
    descended = enter_assets((unsigned char)(ext[0] == 'P'));
    p = gb_dir1();
    while (p && nstem < MAXST) {
        if (!gb_isdir()) {
            const char *r = gb_entname();
            if (r[8]==ext[0] && r[9]==ext[1] && r[10]==ext[2]) {
                off = (unsigned int)nstem * STLEN;
                stembuf[off + 0] = drive_letter(drive);
                stembuf[off + 1] = ':';
                for (k = 0; k < 8 && r[k] != ' '; k++) stembuf[off + 2 + k] = r[k];
                stembuf[off + 2 + k] = 0;
                stem_drive[nstem] = drive;
                stems[nstem] = &stembuf[off];
                nstem++;
            }
        }
        p = gb_dirn();
    }
    if (descended) gb_back();
    gb_set_drive(old_drive);
}

static void enumerate_media(const char *ext)
{
    unsigned char mask = gb_drives();
    nstem = 0;
    if (mask & GB_DRV_A) enumerate_media_drive(ext, GB_DRIVE_A);
    if (mask & GB_DRV_B) enumerate_media_drive(ext, GB_DRIVE_B);
    if (mask & GB_DRV_C) enumerate_media_drive(ext, GB_DRIVE_C);
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
    char val[16];
    win_x = gb_wm_x(); win_y = gb_wm_y(); win_w = gb_wm_w(); win_h = gb_wm_h();
    gb_fill(win_x, (unsigned char)(win_y + TITLE_H), win_w,
            (unsigned char)(win_h - TITLE_H), 1);          /* white panel */
    for (r = 0; r < NROWS; r++) {
        gb_textbw((unsigned char)(win_x + 1), row_y(r), rows[r].label);
        cfg_get(rows[r].key, val);
        gb_textbw((unsigned char)(win_x + VAL_COL), row_y(r), val);
        if (rows[r].ext[0] == 'B') {         /* #216: preview the current backdrop tile beside */
            unsigned char sx = (unsigned char)(win_x + 42), sy = row_y(r);  /* keep clear of "A:NAME.BDP" */
            if (*(volatile unsigned char *)BD_SOLID_ADDR)
                gb_fill(sx, sy, 4, 8, 0);    /* SOLID -> a plain pen-0 (desktop) square */
#if defined(GB_MSX2) || defined(GB_PCW)
            else
                gb_backdrop(sx, sy, 4, 8);   /* applies the target's native tile encoding */
#else
            else
                gb_restorerect(sx, sy, 4, 8, (const void *)BD_TILE_ADDR);   /* tile's top 8 rows */
#endif
            gb_frame(sx, sy, 4, 8, 2);       /* outline so it shows on the white panel */
        }
    }
    gb_textbw((unsigned char)(win_x + 1), row_y(COLOUR_ROW), "Colours...");
#ifdef GB_MSX2
    gb_textbw((unsigned char)(win_x + 1), row_y(VIDEO_ROW), "Video mode");
    {
        unsigned int p = cfg_keypos("MSXMODE=");
        const char *mode = (p != 0xFFFF && p < cfglen && cfgbuf[p] == '7') ?
                           "Screen 7" : "Screen 6";
        gb_textbw((unsigned char)(win_x + VAL_COL), row_y(VIDEO_ROW), mode);
    }
#endif
    {
        char sv[16];                          /* #219: the screensaver section */
        gb_textbw((unsigned char)(win_x + 1), row_y(SS_HDR_ROW), "Screensaver");
        ss_module_value(sv);                  /* Module: which .SAV */
        gb_textbw((unsigned char)(win_x + 2),       row_y(SS_MOD_ROW), "Module");
        gb_textbw((unsigned char)(win_x + VAL_COL), row_y(SS_MOD_ROW), sv);
        gb_textbw((unsigned char)(win_x + 2), row_y(SS_CFG_ROW), "Options");
        {
            unsigned char bx = (unsigned char)(win_x + VAL_COL);
            unsigned char by = (unsigned char)(row_y(SS_CFG_ROW) - 1);
            gb_fill(bx, by, 16, 10, 1);
            gb_frame(bx, by, 16, 10, 2);
            gb_textbw((unsigned char)(bx + 1), (unsigned char)(by + 1), "Configure");
        }
        saver_value(sv);                      /* Timeout: idle minutes */
        gb_textbw((unsigned char)(win_x + 2),       row_y(SS_TM_ROW), "Timeout");
        gb_textbw((unsigned char)(win_x + VAL_COL), row_y(SS_TM_ROW), sv);
    }
    gb_textbw((unsigned char)(win_x + 1), (unsigned char)(win_y + win_h - 10),
#ifdef GB_MSX2
              "Mode/font/icons: reboot.");
#else
              "Font/icons: reboot.");
#endif
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
#if defined(GB_MSX2) || defined(GB_PCW)
/* MSX: GB_SETINK (#8006) maps the CPC ink to the V9938 palette (kernel #287).
 * PCW: the CGA2 palette is fixed - the slot is k_noop there, so the preview
 * is safely inert (#331; the CPC arm called firmware the PCW lacks).
 * Called via inline asm - a gb.h/libgb binding would relink and bloat every
 * CPC app past its budget, so only Settings (this app) reaches the slot. */
static void si_call(void) __naked
{
__asm
    ld   a,(_si_ink)
    ld   b,a
    ld   c,a
    ld   a,(_si_pen)
    call 0x8006          ; GB_SETINK (A = pen 0-4, B/C = CPC ink)
    ret
__endasm;
}
#else
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
#endif
static void apply_colour(unsigned char i, unsigned char ink)
{
    si_ink = ink;
#if defined(GB_MSX2) || defined(GB_PCW)
    si_pen = i;                 /* pen 0-3, or 4 = border - GB_SETINK handles both */
    si_call();
#else
    if (i < 4) { si_pen = i; si_call(); }
    else sb_call();
#endif
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

/* colp_swatch: a small colour sample for pens 0-3 (#216). Filled in pen i, so a live
   apply_colour() recolours it automatically - no redraw on -/+. Framed (pen 2) so it shows
   even when the pen equals the white panel. The 5th row (Border) has no on-screen pen to
   match an arbitrary border ink, so it gets no swatch (its colour is the screen edge). */
static void colp_swatch(unsigned char i)
{
    if (i >= 4) return;
    gb_fill((unsigned char)(win_x + 21), colp_y(i), 3, 8, i);
    gb_frame((unsigned char)(win_x + 21), colp_y(i), 3, 8, 2);
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
        colp_swatch(i);                          /* #216: live colour sample (pens 0-3) */
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

/* ---- screensaver: module (SAVER=) + idle timeout (SAVERTIME=, #219) ---------- */

/* ss_module_value: the current SAVER= module/path (the default SQUARES when absent). */
static void ss_module_value(char *dst)
{
    unsigned char i;
    cfg_get("SAVER=", dst);
    if (dst[0] == '-') {                       /* absent -> the default module */
        dst[0]='S'; dst[1]='Q'; dst[2]='U'; dst[3]='A';
        dst[4]='R'; dst[5]='E'; dst[6]='S'; dst[7]=0;
    } else {
        for (i = 0; dst[i] && i < 14; i++) ;
        dst[i] = 0;
    }
}

static unsigned char ss_is_starfield(void)
{
    static const char stem[8] = { 'S','T','A','R','F','L','D',' ' };
    char value[16];
    unsigned char i, p = 0;
    ss_module_value(value);
    if (value[0] && value[1] == ':') p = 2;
    for (i = 0; i < 7; i++)
        if (value[p + i] != stem[i]) return 0;
    p += 7;
    return (unsigned char)(value[p] == 0 || value[p] == '.');
}

/* ss_module_dialog: list the .SAV screensavers in /GBENCH and persist the pick to
   SAVER=. Reboot to apply (the desktop reads SAVER= at boot). */
static void ss_module_dialog(void)
{
    const char *list[MAXST];
    char path[16];
    unsigned char sel, i, n = 0;
    enumerate_media("SAV");
    for (i = 0; i < nstem; i++) list[n++] = stems[i];
    if (n == 0) { gb_alert("No screensavers", "found."); s_draw(); return; }
    sel = gb_popup((unsigned char)(win_x + VAL_COL), row_y(SS_MOD_ROW), list, n);
    gb_curhide();
    if (sel != 0xFF) {
        cfg_path(path, stem_drive[sel], list[sel] + 2, "SAV");
        cfg_set("SAVER=", path);
    }
    s_draw();
    gb_curshow();
}

/* preset choices: a label + the MINUTES written to SAVERTIME= (0 = off). The desktop
   reads SAVERTIME=<minutes> at boot and runs the module after that idle - so a change
   takes effect on the next boot, like Font/Icons. */
static const char *const saver_lbl[5]  = { "Off", "1 min", "2 min", "5 min", "10 min" };
static const unsigned int saver_mins[5] = { 0, 1, 2, 5, 10 };

/* u_dec: write the decimal of v into s (NUL-terminated); 0 -> "0". */
static void u_dec(unsigned int v, char *s)
{
    char tmp[6];
    unsigned char j = 0, k = 0;
    if (v == 0) { s[0] = '0'; s[1] = 0; return; }
    while (v) { tmp[k++] = (char)('0' + v % 10); v /= 10; }
    while (k) s[j++] = tmp[--k];
    s[j] = 0;
}

/* saver_value: the current SAVERTIME= as a friendly label - a preset name if it matches
   one, else "<n> min" (a hand-edited non-preset minute count). */
static void saver_value(char *dst)
{
    char v[10];
    unsigned int mins = 0;
    unsigned char i = 0, k;
    cfg_get("SAVERTIME=", v);
    while (v[i] >= '0' && v[i] <= '9') { mins = mins * 10 + (unsigned int)(v[i] - '0'); i++; }
    for (i = 0; i < 5; i++)
        if (saver_mins[i] == mins) {
            for (k = 0; saver_lbl[i][k]; k++) dst[k] = saver_lbl[i][k];
            dst[k] = 0;
            return;
        }
    u_dec(mins, dst);                        /* non-preset -> "<n> min" */
    for (k = 0; dst[k]; k++) ;
    dst[k] = ' '; dst[k+1] = 'm'; dst[k+2] = 'i'; dst[k+3] = 'n'; dst[k+4] = 0;
}

/* saver_dialog: pick a timeout preset and persist it to SAVERTIME=. Reboot to apply. */
static void saver_dialog(void)
{
    unsigned char sel = gb_popup((unsigned char)(win_x + VAL_COL), row_y(SS_TM_ROW),
                                 saver_lbl, 5);
    gb_curhide();
    if (sel != 0xFF) {
        char s[6];
        u_dec(saver_mins[sel], s);
        cfg_set("SAVERTIME=", s);
    }
    s_draw();
    gb_curshow();
}

/* ---- per-screensaver configuration (#390) ----------------------------------- */

#define SSC_W 42
#define SSC_H 78

static void ss_cfg_number(unsigned char x, unsigned char y, unsigned char value)
{
    char text[6];
    u_dec(value, text);
    gb_fill(x, y, 5, 8, 1);
    gb_textbw(x, y, text);
}

static void ss_cfg_draw(unsigned char x, unsigned char y,
                        unsigned char speed, unsigned char stars)
{
    unsigned char sy = (unsigned char)(y + 23);
    unsigned char ny = (unsigned char)(y + 39);
    unsigned char by = (unsigned char)(y + SSC_H - 13);
    gb_window(x, y, SSC_W, SSC_H, "Starfield");
    gb_textbw((unsigned char)(x + 3), sy, "Speed");
    gb_textbw((unsigned char)(x + 17), sy, "-");
    ss_cfg_number((unsigned char)(x + 21), sy, speed);
    gb_textbw((unsigned char)(x + 29), sy, "+");
    gb_textbw((unsigned char)(x + 3), ny, "Stars");
    gb_textbw((unsigned char)(x + 17), ny, "-");
    ss_cfg_number((unsigned char)(x + 21), ny, stars);
    gb_textbw((unsigned char)(x + 29), ny, "+");
    gb_textbw((unsigned char)(x + 3), by, "Save");
    gb_textbw((unsigned char)(x + 13), by, "Cancel");
}

static void ss_config_dialog(void)
{
    unsigned char x, y, speed, stars, flags = 0, done = 0;
    if (!ss_is_starfield()) {
        gb_alert("No settings", "for this saver.");
        gb_curhide(); s_draw(); gb_curshow();
        return;
    }

    speed = gbcfg_u8_from(cfgbuf, cfglen, GB_STARFLD_SPEED_KEY,
                          GB_STARFLD_SPEED_DEFAULT,
                          GB_STARFLD_SPEED_MIN, GB_STARFLD_SPEED_MAX);
    stars = gbcfg_u8_from(cfgbuf, cfglen, GB_STARFLD_STARS_KEY,
                          GB_STARFLD_STARS_DEFAULT,
                          GB_STARFLD_STARS_MIN, GB_STARFLD_STARS_MAX);
    x = (unsigned char)(win_x + (win_w - SSC_W) / 2);
    y = (unsigned char)(win_y + 37);
    gb_modal_set(1);
    gb_curhide();
    ss_cfg_draw(x, y, speed, stars);
    gb_curshow();

    while (!done) {
        unsigned char mx, my, sy, ny, by;
        flags = gb_poll();
        if (flags & GB_QUIT) break;
        if (!(flags & GB_CLICK)) continue;
        mx = gb_mx(); my = gb_my();
        sy = (unsigned char)(y + 23);
        ny = (unsigned char)(y + 39);
        by = (unsigned char)(y + SSC_H - 13);

        if (my >= y + 2 && my < y + 12 && mx >= x + 1 && mx < x + 3)
            break;                                      /* title-bar close = Cancel */
        if (my >= by && my < by + 8) {
            if (mx >= x + 3 && mx < x + 10) {
                char text[6];
                u_dec(speed, text); cfg_set(GB_STARFLD_SPEED_KEY, text);
                u_dec(stars, text); cfg_set(GB_STARFLD_STARS_KEY, text);
                done = 1;
            } else if (mx >= x + 13 && mx < x + 23) {
                done = 1;
            }
            continue;
        }
        if (my >= sy && my < sy + 8) {
            if (mx >= x + 16 && mx < x + 20 && speed > GB_STARFLD_SPEED_MIN)
                speed--;
            else if (mx >= x + 28 && mx < x + 32 && speed < GB_STARFLD_SPEED_MAX)
                speed++;
            else continue;
            gb_curhide(); ss_cfg_number((unsigned char)(x + 21), sy, speed); gb_curshow();
        } else if (my >= ny && my < ny + 8) {
            if (mx >= x + 16 && mx < x + 20 && stars > GB_STARFLD_STARS_MIN)
                stars = (unsigned char)(stars - GB_STARFLD_STARS_STEP);
            else if (mx >= x + 28 && mx < x + 32 &&
                     stars <= GB_STARFLD_STARS_MAX - GB_STARFLD_STARS_STEP)
                stars = (unsigned char)(stars + GB_STARFLD_STARS_STEP);
            else continue;
            if (stars < GB_STARFLD_STARS_MIN) stars = GB_STARFLD_STARS_MIN;
            gb_curhide(); ss_cfg_number((unsigned char)(x + 21), ny, stars); gb_curshow();
        }
    }
    if (flags & GB_QUIT) while (gb_poll() & GB_QUIT) ;
    gb_modal_set(0);
    gb_curhide(); s_draw(); gb_curshow();
}

/* ---- interaction ------------------------------------------------------------- */

#if !defined(GB_MSX2) && !defined(GB_PCW)
/* CPC keeps canonical Mode-1 BDP bytes unchanged. Its resident kernel cannot
   afford the tiled filler, so Settings loads the selected tile directly for
   the desktop-side renderer. */
static void load_backdrop_live(const char *name, unsigned char drive)
{
    unsigned char old_drive, descended, i;
    char nm[11];
    unsigned int n;

    if (name[0]=='S' && name[1]=='O' && name[2]=='L' &&
        name[3]=='I' && name[4]=='D' && name[5]==0) {
        *(unsigned char *)BD_SOLID_ADDR = 1;
        return;
    }

    for (i = 0; i < 8; i++) nm[i] = ' ';
    for (i = 0; i < 8 && name[i]; i++) nm[i] = name[i];
    nm[8] = 'B'; nm[9] = 'D'; nm[10] = 'P';

    old_drive = gb_get_drive();
    gb_set_drive(drive);
    descended = enter_assets(0);
    gb_set_name(nm);
    n = gb_fs_load(gb_copybuf, 512);
    if (descended) gb_back();
    gb_set_drive(old_drive);
    if (n >= 64) {
        for (i = 0; i < 64; i++)
            ((char *)BD_TILE_ADDR)[i] = gb_copybuf[i];
        *(unsigned char *)BD_SOLID_ADDR = 0;
    } else {
        *(unsigned char *)BD_SOLID_ADDR = 1;
    }
}
#endif

/* live_apply: write the chosen 8.3 name into the kernel transfer area and call
   gb_reload. The desktop re-reads WALLPAPER= when it regains focus after Settings
   closes, so backdrop and wallpaper both apply without a reboot. */
static void live_apply(unsigned char r, const char *name, unsigned char drive)
{
    const char *ext = rows[r].ext;
    unsigned char is_backdrop = (unsigned char)(ext[0] == 'B');
    if (ext[0] == 'P') return;
    if (is_backdrop) {
        *(unsigned char *)BD_DRIVE_ADDR = drive;
        *(unsigned char *)BD_SOLID_ADDR =
            (name[0]=='S' && name[1]=='O' && name[2]=='L' &&
             name[3]=='I' && name[4]=='D' && name[5]==0) ? 1 : 0;
    }
    {
        char *dst = (char *)rows[r].tfr;
        unsigned char i = 0;
        while (i < 8 && name[i]) { dst[i] = name[i]; i++; }
        while (i < 8) dst[i++] = ' ';
        dst[8] = ext[0]; dst[9] = ext[1]; dst[10] = ext[2];
    }
#if !defined(GB_MSX2) && !defined(GB_PCW)
    if (is_backdrop) {
        load_backdrop_live(name, drive);
        return;
    }
#endif
    gb_reload();
}

/* open_picker: list the files for row r and let the user pick one; write it to the
   config and repaint. */
static void open_picker(unsigned char r)
{
    const char *list[MAXST + 1];
    char path[16];
    unsigned char sel, i, n = 0, media = 0, base;
    const char *ext = rows[r].ext;
    if (r == ROW_BACKDROP || r == ROW_WALLPAPER) {
        enumerate_media(ext);
        media = 1;
    } else {
        enumerate_boot(ext, rows[r].min_icons);
    }
    if (ext[0] == 'B') list[n++] = "SOLID";      /* the Backdrop list leads with SOLID (no tile) */
    else if (ext[0] == 'P') list[n++] = "NONE";  /* the Wallpaper list leads with NONE (#212) */
    base = n;
    for (i = 0; i < nstem; i++) list[n++] = stems[i];
    if (n == 0) {
        gb_alert("No files found", "in /GBENCH.");
        s_draw();
        return;
    }
    sel = gb_popup((unsigned char)(win_x + VAL_COL), row_y(r), list, n);
    gb_curhide();
    if (sel != 0xFF) {
        if ((ext[0] == 'B' && list[sel][0] == 'S' && list[sel][1] == 'O' &&
             list[sel][2] == 'L' && list[sel][3] == 'I' && list[sel][4] == 'D' &&
             list[sel][5] == 0) ||
            (ext[0] == 'P' && list[sel][0] == 'N' && list[sel][1] == 'O' &&
             list[sel][2] == 'N' && list[sel][3] == 'E' && list[sel][4] == 0)) {
            cfg_set(rows[r].key, list[sel]); /* SOLID / NONE stay global */
            if (r == ROW_BACKDROP)
                cfg_set("WALLPAPER=", "NONE");   /* backdrop mode: wallpaper must not mask it */
            live_apply(r, list[sel], DRIVE_NONE);
        } else {
            if (media)
                cfg_path(path, stem_drive[sel - base], list[sel] + 2, ext);
            else
                cfg_path(path, boot_drive(), list[sel], ext);
            cfg_set(rows[r].key, path);      /* persist to GEOBENCH.CFG */
            if (r == ROW_BACKDROP)
                cfg_set("WALLPAPER=", "NONE");   /* backdrop choice wins over wallpaper */
            else if (r == ROW_WALLPAPER)
                cfg_set("BACKDROP=", "SOLID");   /* wallpaper overlays the desktop; keep a plain fallback */
            live_apply(r, media ? (list[sel] + 2) : list[sel],
                       media ? stem_drive[sel - base] : boot_drive()); /* ...and apply now, no reboot (#185) */
        }
        /* Do not force a full ancestor repaint from inside the picker callback. A successful
           selection used to re-enter the WM repaint stack while this managed window was still
           unwinding its modal UI path, and that left the desktop's System menu dead afterwards.
           Persist the choice now; the desktop/window stack repaints naturally on close. */
    }
    s_draw();                                /* repaint our content (new font/value) */
    gb_curshow();
}

#ifdef GB_MSX2
static void video_mode_dialog(void)
{
    static const char *const modes[] = { "Screen 6", "Screen 7" };
    unsigned char sel = gb_popup((unsigned char)(win_x + VAL_COL),
                                 row_y(VIDEO_ROW), modes, 2);
    gb_curhide();
    if (sel != 0xFF) cfg_set("MSXMODE=", sel ? "7" : "6");
    s_draw();
    gb_curshow();
}
#endif

/* a content press: which row was clicked? */
static void s_click(void)
{
    unsigned char mx, my, r;
    win_x = gb_wm_x(); win_y = gb_wm_y(); win_w = gb_wm_w(); win_h = gb_wm_h();
    mx = gb_mx(); my = gb_my();
    for (r = 0; r < NROWS; r++) {
        unsigned char ry = row_y(r);
        if (my >= (unsigned char)(ry - 2) && my < (unsigned char)(ry + ROW_H - 2)) {
            open_picker(r);
            return;
        }
    }
    {
        unsigned char ry = row_y(COLOUR_ROW);
        if (my >= (unsigned char)(ry - 2) && my < (unsigned char)(ry + ROW_H - 2)) {
            colours_dialog();
            return;
        }
    }
#ifdef GB_MSX2
    {
        unsigned char ry = row_y(VIDEO_ROW);
        if (my >= (unsigned char)(ry - 2) && my < (unsigned char)(ry + ROW_H - 2)) {
            video_mode_dialog();
            return;
        }
    }
#endif
    {
        unsigned char ry = row_y(SS_MOD_ROW);             /* #219: screensaver module */
        if (my >= (unsigned char)(ry - 2) && my < (unsigned char)(ry + ROW_H - 2)) {
            ss_module_dialog();
            return;
        }
    }
    {
        unsigned char ry = row_y(SS_CFG_ROW);
        if (my >= (unsigned char)(ry - 2) && my < (unsigned char)(ry + ROW_H - 2) &&
            mx >= win_x + VAL_COL && mx < win_x + VAL_COL + 16) {
            ss_config_dialog();
            return;
        }
    }
    {
        unsigned char ry = row_y(SS_TM_ROW);              /* screensaver timeout */
        if (my >= (unsigned char)(ry - 2) && my < (unsigned char)(ry + ROW_H - 2))
            saver_dialog();
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
    sel_boot_root();
    gb_set_name("GEOBENCHCFG");
    cfglen = gb_fs_load(cfgbuf, sizeof(cfgbuf));   /* load the config once (0 if none) */
    for (n = 64; n; n--) if (!gb_getkey()) break;  /* drain the launch keystrokes (#142) */
    gb_restore_parent();                            /* first paint: WM chrome + s_draw */
}
