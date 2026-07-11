/* BRSAVE.APP - transient Browser offline-source writer.
 *
 * BROWSER.APP remains focused on parsing/rendering. This small co-resident
 * worker writes the borrowed source pages selected by File > Save, then closes
 * itself and reports the result through low RAM. */
#include "gb.h"

#define BUI_STAGE       ((char *)0x2B00)
#define BUI_PAGES       ((volatile unsigned char *)0x3900)
#define BUI_NPAGES      (*(volatile unsigned char *)0x3904)
#define BUI_TAIL        (*(volatile unsigned int  *)0x3905)
#define BUI_SAVE_RESULT (*(volatile unsigned char *)0x3913)
#define BUI_SAVE_NAME   ((char *)0x39C2)
#define PIC_PAGE_K      (*(volatile unsigned char *)0x130B)
#define PIC_PAGE2_K     (*(volatile unsigned char *)0x1348)
#define FS_SAVE_LEN_K   (*(volatile unsigned int  *)0x14FD)
#define FS_XFLAGS       (*(volatile unsigned char *)0x144F)

static unsigned char started;

static unsigned char write_source(void)
{
    unsigned char page, first = 1;
    unsigned int off, left, take;
    gb_set_name(BUI_SAVE_NAME);
    for (page = 0; page < BUI_NPAGES; page++) {
        left = page + 1 < BUI_NPAGES ? 0x4000 : BUI_TAIL;
        off = 0;
        while (left) {
            take = left > 512 ? 512 : left;
            PIC_PAGE_K = BUI_PAGES[page]; PIC_PAGE2_K = 0;
            gb_pic_edit_buf = (unsigned int)BUI_STAGE;
            gb_pic_edit_off = off; FS_SAVE_LEN_K = take;
            if (!gb_pic_edit(GB_PICEDIT_CHUNK)) { FS_XFLAGS = 0; return 0; }
            FS_XFLAGS = first ? 0x04 : 0x06;
            if (!gb_fs_save(BUI_STAGE, take)) { FS_XFLAGS = 0; return 0; }
            first = 0; off += take; left -= take;
        }
    }
    FS_XFLAGS = 0;
    return (unsigned char)!first;
}

static void worker_proc(void)
{
    if (gb_msg.type == GB_MSG_DRAW) gb_textbw(21, 92, "Writing .HTM file...");
    else if (gb_msg.type == GB_MSG_FRAME && !started) {
        started = 1;
        BUI_SAVE_RESULT = write_source() ? 1 : 2;
        gb_wm_close();
    } else if (gb_msg.type == GB_MSG_CLOSE) {
        BUI_SAVE_RESULT = 2;
        FS_XFLAGS = 0;
        gb_wm_close();
    }
}

static const gb_mwin_t worker_window = {
    18, 72, 44, 48, 0, 0, worker_proc, "Saving HTML"
};

void main(void)
{
    BUI_SAVE_RESULT = 0;
    gb_wm_managed(&worker_window);
    gb_restore_parent();
}
