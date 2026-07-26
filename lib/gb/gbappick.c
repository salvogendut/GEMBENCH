/* gbappick.c - ICONED's paged Open dialog.
 *
 * .IST and .SPR files are listed immediately. Embedded APP icons have their own
 * row because validating every APP before drawing the first dialog is painfully
 * slow on floppy media. Inside that view an .APP is listed only when its preamble
 * contains an optional GBAP v1/v2 icon. Probing a file can disturb a backend's
 * directory enumerator, so the scan resumes by name after each probe.
 */
#include "gb.h"

#define PICK_MAX       12
#define APPICON_OFF    16
#define APPICON_WB     8
#define APPICON_H      32

#if defined(GB_MSX2) || defined(GB_PCW)
#define APP_PROBE_MAX  512
#define FS_LOAD_OFS ((volatile unsigned char *)0x144C)
#else
#define APP_PROBE_MAX  0x1C00
#endif
#define FS_XFLAGS   (*(volatile unsigned char *)0x144F)
#define PROBE_BUF   ((unsigned char *)0x2200)

static char          store[PICK_MAX][14];
static char          rawname[PICK_MAX][11];
static unsigned char isdir_f[PICK_MAX];
static char          saved_name[11];

static void copy11(char *dst, const char *src)
{
    unsigned char i;
    for (i = 0; i < 11; i++) dst[i] = src[i];
}

static unsigned char same11(const char *a, const char *b)
{
    unsigned char i;
    for (i = 0; i < 11; i++) if (a[i] != b[i]) return 0;
    return 1;
}

static unsigned char ext_is(const char *raw, const char *ext)
{
    return (unsigned char)(raw[8] == ext[0] && raw[9] == ext[1] &&
                           raw[10] == ext[2]);
}

static void name_disp(char *dst, const char *raw, unsigned char dir)
{
    unsigned char i, j = 0;
    for (i = 0; i < 8 && raw[i] != ' '; i++) dst[j++] = raw[i];
    if (dir) dst[j++] = '/';
    else if (raw[8] != ' ') {
        dst[j++] = '.';
        for (i = 8; i < 11 && raw[i] != ' '; i++) dst[j++] = raw[i];
    }
    dst[j] = 0;
}

static unsigned char has_gbap(const char *raw)
{
    unsigned char version;
#if defined(GB_MSX2) || defined(GB_PCW)
    unsigned int got;
#endif

    gb_set_name(raw);
#if defined(GB_MSX2) || defined(GB_PCW)
    FS_LOAD_OFS[0] = 0;
    FS_LOAD_OFS[1] = 0;
    FS_LOAD_OFS[2] = 0;
    FS_XFLAGS = 1;
    got = gb_fs_load((char *)PROBE_BUF, APP_PROBE_MAX);
    FS_XFLAGS = 0;
    if (got < APPICON_OFF) return 0;
#else
    /* A CPC chunk read loads another PAGE_DATA module over this picker.
     * Use the ordinary loader within the low-RAM module-data area instead. */
    PROBE_BUF[0] = 0;
    FS_XFLAGS = 0;
    (void)gb_fs_load((char *)PROBE_BUF, APP_PROBE_MAX);
#endif

    if (PROBE_BUF[0] != 0xC3 || PROBE_BUF[3] != 'G'
        || PROBE_BUF[4] != 'B' || PROBE_BUF[5] != 'A'
        || PROBE_BUF[6] != 'P') return 0;
    version = PROBE_BUF[7];
    if (version == 1)
        return (unsigned char)(PROBE_BUF[8] == 1
            && PROBE_BUF[9] == APPICON_WB && PROBE_BUF[10] == APPICON_H);
    /* GBAP v2 requires the portable fallback in resource slot zero. */
    return (unsigned char)(version == 2 && PROBE_BUF[8]
        && PROBE_BUF[APPICON_OFF] == 1
        && PROBE_BUF[APPICON_OFF + 1] == APPICON_WB
        && PROBE_BUF[APPICON_OFF + 2] == APPICON_H);
}

/* Reposition after a probe or popup changed the backend directory cursor.
 * advance=1 returns the entry after raw; 0 leaves raw positioned for chdir. */
static char *seek_raw(const char *raw, unsigned char advance)
{
    char *p = gb_dir1();
    while (p) {
        if (same11(gb_entname(), raw)) return advance ? gb_dirn() : p;
        p = gb_dirn();
    }
    return 0;
}

/* PCW has two flat floppy drives. CPC floppy dialogs use the same A/B toggle;
 * card-based CPC and MSX dialogs remain on C. */
static void next_drive(void) __naked
{
__asm
    call 0x8084
    or a
    ret z
    xor a,#0x03
    jp 0x8081
__endasm;
}

unsigned char gb_pickappicon(char *out11)
{
    const char *labels[PICK_MAX + 3];
    char candidate[11];
    char *p;
    unsigned char nreal, sel, i, dir, accept, app, app_only = 0;

    for (;;) {
        nreal = 0;
        p = gb_dir1();
        while (p && nreal < PICK_MAX) {
            dir = gb_isdir();
            copy11(candidate, gb_entname());
            app = (unsigned char)(!dir && ext_is(candidate, "APP"));
            accept = app_only
                ? app
                : (unsigned char)(dir || ext_is(candidate, "IST") ||
                                  ext_is(candidate, "SPR"));
            if (app_only && app) {
                accept = has_gbap(candidate);
                p = seek_raw(candidate, 1);
            } else {
                p = gb_dirn();
            }
            if (accept) {
                isdir_f[nreal] = dir;
                copy11(rawname[nreal], candidate);
                name_disp(store[nreal], candidate, dir);
                nreal++;
            }
        }
        if (app_only) gb_set_name(saved_name);

        labels[0] = "..";
        labels[1] = "[Next drive]";
        labels[2] = app_only ? "[Files]" : "[APP icons]";
        for (i = 0; i < nreal; i++) labels[i + 3] = store[i];
        sel = gb_popup(10, 18, labels, (unsigned char)(nreal + 3));
        if (sel == 0xFF) return 0;
        if (sel == 0) {
            gb_back();
            continue;
        }
        if (sel == 1) {
            next_drive();
            continue;
        }
        if (sel == 2) {
            app_only = (unsigned char)!app_only;
            if (app_only) gb_get_name(saved_name);
            continue;
        }
        i = (unsigned char)(sel - 3);
        if (i >= nreal) continue;
        if (isdir_f[i]) {
            if (seek_raw(rawname[i], 0)) gb_chdir();
            continue;
        }
        copy11(out11, rawname[i]);
        return 1;
    }
}
