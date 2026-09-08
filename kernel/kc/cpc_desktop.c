/* Native Desktop leaves only. Shared source owns the menus/icons/activation. */
#include "gb.h"
#include GB_DESKTOP_BINDINGS
void desktop_open_app(const char *name);

unsigned char desktop_capacity(void)
{
    return FILEMGR_WINDOW_COUNT >= FILEMGR_WINDOW_LIMIT || !FILEMGR_FREE_PAGES;
}

void desktop_open_disk(unsigned char drive)
{
    (void)drive;
#if DESKTOP_FILEMGR_READY
    if (drive) { gb_alert("Disk unavailable", "Only Disk C is supported"); return; }
    desktop_open_app("FILEMGR BIN");
#else
    /* Native File Manager has a checked link, not a qualified package/loader.
       Make the gate visible instead of pretending the directory was opened. */
    gb_alert("Disk browsing unavailable", "File Manager integration pending");
#endif
}

void desktop_open_app(const char *name)
{
    unsigned char focus = FILEMGR_FOCUS;
    gb_wm_open(name);
    if (focus == FILEMGR_FOCUS)
        gb_alert("Application not opened", "Missing, invalid or no RAM");
}
