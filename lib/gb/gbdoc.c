/* gbdoc.c - the document-app framework (#142), an OPT-IN libgb module.
 *
 * ONE File menu for every app. An app registers a gb_doc_t (buffer + new/open/save
 * hooks) and gets a standard top-bar "File" menu (New / Load / Save / Save As) that
 * the framework renders and runs - so the app carries no menu or file-dialog code.
 * Apps add their own titles with gb_menu_add. Linked only when build_capp.sh sets
 * DOC=1; it pulls in gbdlg (gb_popup) and gbprompt (gb_prompt).
 *
 * Step 1a: the render is still gb_popup (libgb). The API (gb_doc/gb_menu_add) is
 * stable, so a later step can move the render into a system service unchanged.
 *
 * Recipe (see gb.h): gb_doc(&doc) before gb_wm_run; in on_event call gb_doc_event()
 * first; in on_frame call gb_doc_frame() and repaint your window if it returns 1.
 */
#include "gb.h"

#define DOC_MAXTITLES 4              /* File + up to 3 app titles */
#define DOC_MAXFILES  24             /* entries shown in the Load picker */

static const gb_doc_t *g_doc;
static unsigned char   g_dirty;
static unsigned char   g_want;       /* 0 = none, else (title index + 1) to drop */

static const char     *g_label[DOC_MAXTITLES];
static const char *const *g_items[DOC_MAXTITLES];
static unsigned char   g_nitems[DOC_MAXTITLES];
static void          (*g_handler[DOC_MAXTITLES])(unsigned char);
static unsigned char   g_col[DOC_MAXTITLES];     /* each title's byte column */
static unsigned char   g_ntitles;
static unsigned char   g_def[1 + DOC_MAXTITLES * 9];   /* MENU_DEF: count, {col,label[8]}* */

static const char *const file_items[] = { "New", "Load", "Save", "Save As" };
static const char *const confirm_items[] = { "Save", "Don't Save", "Cancel" };

static unsigned char slen(const char *s) { unsigned char n = 0; while (s[n]) n++; return n; }

/* to_83: "NAME.EXT" (or "NAME") -> an 11-byte space-padded 8.3 name (no dot) for
 * gb_set_name. */
static char name83[11];
static void to_83(const char *src)
{
    unsigned char i = 0, j;
    for (j = 0; j < 11; j++) name83[j] = ' ';
    for (j = 0; j < 8 && src[i] && src[i] != '.'; j++) name83[j] = src[i++];
    while (src[i] && src[i] != '.') i++;          /* skip any over-long name tail */
    if (src[i] == '.') {
        i++;
        for (j = 0; j < 3 && src[i]; j++) name83[8 + j] = src[i++];
    }
}

/* (re)build the kernel MENU_DEF from the registered titles, auto-placing columns,
 * and hand it to the bar. */
static void rebuild(void)
{
    unsigned char i, j, col = 10, *p = g_def;
    *p++ = g_ntitles;
    for (i = 0; i < g_ntitles; i++) {
        unsigned char len = slen(g_label[i]);
        g_col[i] = col;
        *p++ = col;
        for (j = 0; j < 8; j++) *p++ = (j < len) ? g_label[i][j] : 0;
        col = (unsigned char)(col + (len * 6 + 3) / 4 + 1);   /* next title's column */
    }
    gb_menu(g_def);
}

void gb_doc(const gb_doc_t *d)
{
    g_doc = d;
    g_dirty = 0;
    g_want = 0;
    g_label[0]   = "File";
    g_items[0]   = file_items;
    g_nitems[0]  = 4;
    g_handler[0] = 0;                 /* File is handled internally */
    g_ntitles    = 1;
    rebuild();
}

void gb_menu_add(const char *title, const char *const *items, unsigned char n,
                 void (*on_select)(unsigned char item))
{
    unsigned char i = g_ntitles;
    if (i >= DOC_MAXTITLES) return;
    g_label[i]   = title;
    g_items[i]   = items;
    g_nitems[i]  = n;
    g_handler[i] = on_select;
    g_ntitles++;
    rebuild();
}

void gb_doc_dirty(void) { g_dirty = 1; }
unsigned char gb_doc_modified(void) { return g_dirty; }

/* g_name: the current file's 11-byte 8.3 name, kept so the app can read it (title,
 * extension checks) after Load/Save As changed it. set_name keeps it in step with
 * the kernel's current file. */
static char g_name[11];
const char *gb_doc_name(void) { return g_name; }
static void set_name(const char *n11)
{
    unsigned char i;
    for (i = 0; i < 11; i++) g_name[i] = n11[i];
    gb_set_name(g_name);
}

/* on_event: a top-bar title was clicked -> arm its menu. Returns 1 if it was one
 * of ours (so the app's on_event stops). */
unsigned char gb_doc_event(void)
{
    unsigned char i, col;
    if (gb_msg.type != GB_MSG_MENU) return 0;
    col = gb_msg.p0;
    for (i = 0; i < g_ntitles; i++) {
        unsigned char w = (unsigned char)((slen(g_label[i]) * 6 + 3) / 4);
        if (col >= g_col[i] && col < (unsigned char)(g_col[i] + w)) { g_want = (unsigned char)(i + 1); return 1; }
    }
    return 0;
}

/* --- the standard File actions ------------------------------------------- */

static void do_save(void);

/* confirm_save: if the document is dirty, ask. -> 1 = go ahead (saved or
 * discarded), 0 = cancel the operation. */
static unsigned char confirm_save(void)
{
    unsigned char sel;
    if (!g_dirty) return 1;
    sel = gb_popup(28, 90, confirm_items, 3);
    if (sel == 0) { do_save(); return 1; }           /* Save */
    if (sel == 1) return 1;                          /* Don't Save */
    return 0;                                        /* Cancel / ESC */
}

static void do_new(void)
{
    if (!confirm_save()) return;
    set_name("UNTITLED   ");
    if (g_doc->on_new) g_doc->on_new();
    g_dirty = 0;
}

/* do_load: list the current directory's files in a picker and open the choice. */
static char store[DOC_MAXFILES][14];
static void do_load(void)
{
    const char *names[DOC_MAXFILES];
    char *p;
    unsigned char n = 0, i, sel;
    unsigned int len;

    if (!confirm_save()) return;
    p = gb_dir1();
    while (p && n < DOC_MAXFILES) {
        if (!gb_isdir()) {                           /* files only, no folders */
            for (i = 0; i < 13 && p[i]; i++) store[n][i] = p[i];
            store[n][i] = 0;
            names[n] = store[n];
            n++;
        }
        p = gb_dirn();
    }
    if (!n) return;
    sel = gb_popup(10, 18, names, n);
    if (sel == 0xFF) return;
    to_83(store[sel]);
    set_name(name83);                              /* picker name -> current file */
    len = gb_fs_load(g_doc->buf, g_doc->bufmax);
    if (g_doc->on_open) g_doc->on_open(len);
    g_dirty = 0;
}

static void do_save(void)
{
    unsigned int n  = g_doc->on_save();
    unsigned char ok = gb_fs_save(g_doc->buf, n);
    if (g_doc->on_saved) g_doc->on_saved();          /* restore buf if on_save transformed it */
    if (ok) g_dirty = 0;
}

static char namebuf[16];
static void do_saveas(void)
{
    if (!gb_prompt("Save as:", namebuf, 12)) return;
    to_83(namebuf);
    set_name(name83);
    do_save();
}

static void file_action(unsigned char sel)
{
    if      (sel == 0) do_new();
    else if (sel == 1) do_load();
    else if (sel == 2) do_save();
    else if (sel == 3) do_saveas();
}

/* on_frame: drop a pending menu and dispatch it. Returns 1 if a menu ran (the
 * app should repaint its window, since the popup erased a hole in it). */
unsigned char gb_doc_frame(void)
{
    unsigned char t, sel;
    if (!g_want) return 0;
    t = (unsigned char)(g_want - 1);
    g_want = 0;
    sel = gb_popup(g_col[t], 8, g_items[t], g_nitems[t]);
    if (sel != 0xFF) {
        if (t == 0) file_action(sel);                /* File (built-in) */
        else if (g_handler[t]) g_handler[t](sel);    /* app menu -> its handler */
    }
    return 1;
}

/* gb_doc_close: the window close gadget was hit - offer to save first. 1 = go
 * ahead and close, 0 = stay open (user cancelled). */
unsigned char gb_doc_close(void) { return confirm_save(); }
