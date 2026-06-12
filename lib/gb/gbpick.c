/* gbpick.c - the navigable file/folder chooser (#142), an OPT-IN libgb module.
 *
 * A small Open/Save dialog built on the kernel's directory primitives
 * (gb_dir1/dirn/isdir/entname + gb_chdir/back + gb_popup) - this is the file
 * DIALOG, deliberately NOT the File Manager app (the same split every OS makes
 * between an Open/Save panel and the file browser). It lists the current
 * directory's folders + files; ".." goes up, a folder descends, a file is the
 * Open selection. Save navigates the same way, then "[Save here]" picks the
 * current directory as the destination.
 *
 * Shared by any app, not just doc apps: build_capp.sh links it when PICKER=1
 * (DOC=1 implies it). It pulls in gbdlg (gb_popup). The two entry points are
 * gb_pickfile() and gb_pickdir(); both leave the filesystem positioned in the
 * chosen directory, so a following gb_fs_load / gb_fs_save targets it.
 */
#include "gb.h"

#define PICK_MAX  12             /* entries shown per directory (folder nav offsets
                                    the low cap; a scrolling list is a later step) */

static char          store[PICK_MAX][14];   /* display labels: "NAME.EXT" / "NAME/" */
static unsigned char isdir_f[PICK_MAX];     /* parallel: is entry i a directory?    */

/* name_disp: raw 11-byte 8.3 name -> "NAME.EXT" (file) or "NAME/" (folder), into dst. */
static void name_disp(char *dst, const char *raw, unsigned char dir)
{
    unsigned char i, j = 0;
    for (i = 0; i < 8 && raw[i] != ' '; i++) dst[j++] = raw[i];
    if (dir) dst[j++] = '/';
    else if (raw[8] != ' ') { dst[j++] = '.'; for (i = 8; i < 11 && raw[i] != ' '; i++) dst[j++] = raw[i]; }
    dst[j] = 0;
}

/* seek_to: re-position the directory enumerator on entry idx (raw order), so the
 * kernel's "current entry" (fs_ent_*) is that one - for gb_chdir / gb_entname. */
static void seek_to(unsigned char idx)
{
    unsigned char k;
    gb_dir1();
    for (k = 0; k < idx; k++) gb_dirn();
}

/* pick: the shared navigable loop. savemode 0 = Open (a chosen file's raw 8.3 name
 * is copied to out11, 1 returned); savemode 1 = Save (navigate, then "[Save here]"
 * returns 1). 0 = cancelled. Folders descend, ".." goes up; leaves the FS in the
 * chosen directory. out11 may be NULL in save mode. */
static unsigned char pick(unsigned char savemode, char *out11)
{
    const char *labels[PICK_MAX + 2];
    unsigned char nreal, nlab, base, sel, i;
    char *p;
    for (;;) {
        nreal = 0;
        p = gb_dir1();
        while (p && nreal < PICK_MAX) {
            isdir_f[nreal] = gb_isdir();
            name_disp(store[nreal], gb_entname(), isdir_f[nreal]);
            nreal++;
            p = gb_dirn();
        }
        nlab = 0;
        labels[nlab++] = "..";                          /* 0 = up a level */
        if (savemode) labels[nlab++] = "[Save here]";   /* target = current directory */
        base = nlab;
        for (i = 0; i < nreal; i++) labels[nlab++] = store[i];
        sel = gb_popup(10, 18, labels, nlab);
        if (sel == 0xFF) return 0;                      /* cancel / ESC */
        if (sel == 0) { gb_back(); continue; }          /* .. */
        if (savemode && sel == 1) return 1;             /* [Save here] */
        i = (unsigned char)(sel - base);                /* real entry index */
        if (isdir_f[i]) { seek_to(i); gb_chdir(); continue; }   /* descend into folder */
        if (savemode) continue;                         /* a file in Save mode -> ignore */
        seek_to(i);                                     /* Open: select this file */
        if (out11) { p = gb_entname(); for (i = 0; i < 11; i++) out11[i] = p[i]; }
        return 1;
    }
}

/* gb_pickfile: navigable Open dialog. On a pick, fills name11 with the chosen file's
 * raw 11-byte 8.3 name and leaves the FS in its directory; returns 1 (0 = cancel). */
unsigned char gb_pickfile(char *name11) { return pick(0, name11); }

/* gb_pickdir: navigable destination chooser. Navigate, then "[Save here]" leaves the
 * FS in that directory and returns 1 (0 = cancel) - the caller then prompts a name. */
unsigned char gb_pickdir(void) { return pick(1, 0); }
