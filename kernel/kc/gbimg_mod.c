/* GBIMG.MOD - bounded Browser inline-image cache helper.
 *
 * The Browser keeps page records and one converted GBPC image in a borrowed
 * 16K bank. This paged helper performs the infrequent bank copies, validation,
 * visible-image lookup, and clipped blit so that code does not consume the
 * PCW Browser app bank. */
#include "gb.h"

#define UI_OP           (*(volatile unsigned char *)0x1700)
#define UI_RES          (*(volatile unsigned char *)0x1704)
#define BUI_STAGE       ((char *)0x2B00)
#define BUI_STAGE_LEN   (*(volatile unsigned int  *)0x3907)
#define BUI_RESOURCE_TAIL (*(volatile unsigned int *)0x3AAD)
#define BUI_IMAGE_URL   (*(volatile unsigned int  *)0x3AB3)
#define BUI_IMAGE_REL   (*(volatile unsigned char *)0x3AB5)
#define BUI_IMAGE_LEN   (*(volatile unsigned int  *)0x3AB6)
#define BUI_IMAGE_WB    (*(volatile unsigned char *)0x3AB9)
#define BUI_IMAGE_H     (*(volatile unsigned char *)0x3ABA)
#define BUI_IMAGE_READY (*(volatile unsigned char *)0x3ABB)
#define BUI_IMAGE_FAILED (*(volatile unsigned int *)0x3ABD)
#define BUI_CACHE_PAGE  (*(volatile unsigned char *)0x3ABF)
#define BUI_HIST_COUNT  (*(volatile unsigned char *)0x3AC0)
#define BUI_VIEW_TOP    (*(volatile unsigned char *)0x3AC1)
#define BUI_LINE_SIZE   (*(volatile unsigned char *)0x3AC2)
#define BUI_VIEW_ROWS   (*(volatile unsigned char *)0x3AC3)
#define BUI_TEXT_X      (*(volatile unsigned char *)0x3AC4)
#define BUI_CONTENT_Y   (*(volatile unsigned char *)0x3AC5)
#define BUI_SCREEN_COLS (*(volatile unsigned char *)0x3AC6)
#define BUI_IMAGE_PAGE  (*(volatile unsigned char *)0x3ADC)
#define BUI_IMAGE_MODE  (*(volatile unsigned char *)0x3ADD)
#define BUI_IMAGE_STRIDE (*(volatile unsigned char *)0x3ADE)

#define BROWSER_LINE    ((char *)0x3300)
#define BROWSER_LINK    ((char *)0x34F0)
#define PIC_PAGE_K      (*(volatile unsigned char *)0x130B)
#define PIC_WB_K        (*(volatile unsigned char *)0x130C)
#define PIC_H_K         (*(volatile unsigned int  *)0x130D)
#define PIC_OFF_K       (*(volatile unsigned char *)0x130F)
#define PIC_PAGE2_K     (*(volatile unsigned char *)0x1348)
#ifdef GB_MSX2
#define PIC_PAGE3_K     (*(volatile unsigned char *)0x1291)
#define PIC_PAGE4_K     (*(volatile unsigned char *)0x1292)
#define PIC_MODE_K      (*(volatile unsigned char *)0x1293)
#define PIC_STRIDE_K    (*(volatile unsigned int  *)0x1294)
#endif
#define FS_SAVE_LEN_K   (*(volatile unsigned int  *)0x14FD)

#define LINK_MAX        47
#define IMAGE_MARK      4
#define IMAGE_CONT_MARK 5
#define INVALID_OFFSET  0xFFFF
#define CACHE_DATA_END  0x27D0
#define IMAGE_SLOT_OFS  0x30F2
#define IMAGE_SLOT_SIZE 3854
#define IMAGE_PAGE_SIZE 7694
#define IMAGE_HEADER_SIZE 14
#define IMAGE_ROWS      12

static unsigned char bank_read(unsigned int off, char *dst, unsigned int len)
{
    PIC_PAGE_K = BUI_CACHE_PAGE;
    PIC_PAGE2_K = 0;
    gb_pic_edit_buf = (unsigned int)dst;
    gb_pic_edit_off = off;
    FS_SAVE_LEN_K = len;
    return gb_pic_edit(GB_PICEDIT_CHUNK);
}

static unsigned int image_base(void)
{
    return BUI_IMAGE_MODE == 7 ? 0 : IMAGE_SLOT_OFS;
}

static unsigned char image_bank_read(unsigned int off, char *dst,
                                     unsigned int len)
{
    PIC_PAGE_K = BUI_IMAGE_MODE == 7 ? BUI_IMAGE_PAGE : BUI_CACHE_PAGE;
    PIC_PAGE2_K = 0;
#ifdef GB_MSX2
    PIC_PAGE3_K = PIC_PAGE4_K = 0;
#endif
    gb_pic_edit_buf = (unsigned int)dst;
    gb_pic_edit_off = image_base() + off;
    FS_SAVE_LEN_K = len;
    return gb_pic_edit(GB_PICEDIT_CHUNK);
}

static unsigned char read_line(unsigned char rel)
{
    return bank_read((unsigned int)rel * BUI_LINE_SIZE,
                     BROWSER_LINE, BUI_LINE_SIZE);
}

static unsigned char load_resource(unsigned int off)
{
    if (off < CACHE_DATA_END || off >= BUI_RESOURCE_TAIL) return 0;
    if (!bank_read(off, BROWSER_LINK, LINK_MAX + 1)) return 0;
    BROWSER_LINK[LINK_MAX] = 0;
    return 1;
}

static unsigned char flush_image(void)
{
    unsigned int next, limit;
    if (!BUI_STAGE_LEN) return 1;
    if (!BUI_IMAGE_MODE) {
        BUI_IMAGE_MODE = (unsigned char)(BUI_IMAGE_PAGE && BUI_STAGE_LEN >= 6 &&
            BUI_STAGE[0] == 'G' && BUI_STAGE[1] == 'B' &&
            BUI_STAGE[2] == 'P' && BUI_STAGE[3] == 'C' &&
            BUI_STAGE[4] == 2 && BUI_STAGE[5] == 7 ? 7 : 1);
    }
    next = BUI_IMAGE_LEN + BUI_STAGE_LEN;
    limit = BUI_IMAGE_MODE == 7 ? IMAGE_PAGE_SIZE : IMAGE_SLOT_SIZE;
    if (next > limit) return 0;
    PIC_PAGE_K = BUI_IMAGE_MODE == 7 ? BUI_IMAGE_PAGE : BUI_CACHE_PAGE;
    PIC_PAGE2_K = 0;
#ifdef GB_MSX2
    PIC_PAGE3_K = PIC_PAGE4_K = 0;
#endif
    gb_pic_edit_buf = (unsigned int)BUI_STAGE;
    gb_pic_edit_off = image_base() + BUI_IMAGE_LEN;
    FS_SAVE_LEN_K = BUI_STAGE_LEN;
    if (!gb_pic_edit(GB_PICEDIT_WRITE)) return 0;
    BUI_IMAGE_LEN = next;
    BUI_STAGE_LEN = 0;
    return 1;
}

static unsigned char validate_image(void)
{
    unsigned int expected = IMAGE_HEADER_SIZE;
    unsigned char mode, width, rows;
    if (!flush_image() || BUI_IMAGE_LEN < IMAGE_HEADER_SIZE ||
        !image_bank_read(0, BROWSER_LINE, IMAGE_HEADER_SIZE)) return 0;
    if (BROWSER_LINE[0] != 'G' || BROWSER_LINE[1] != 'B' ||
        BROWSER_LINE[2] != 'P' || BROWSER_LINE[3] != 'C' ||
        BROWSER_LINE[4] != 2 || BROWSER_LINE[7] || BROWSER_LINE[9]) return 0;
    mode = (unsigned char)BROWSER_LINE[5];
    width = (unsigned char)BROWSER_LINE[6];
    BUI_IMAGE_H = (unsigned char)BROWSER_LINE[8];
    if (!width || width > 160 || !BUI_IMAGE_H || BUI_IMAGE_H > 96) return 0;
    if (mode == 1) {
        BUI_IMAGE_WB = (unsigned char)((width + 3) >> 2);
        BUI_IMAGE_STRIDE = BUI_IMAGE_WB;
    }
#ifdef GB_MSX2
    else if (mode == 7 && BUI_IMAGE_PAGE && BUI_IMAGE_MODE == 7 &&
             !(width & 3)) {
        BUI_IMAGE_WB = (unsigned char)(width >> 2);
        BUI_IMAGE_STRIDE = (unsigned char)(width >> 1);
    }
#endif
    else return 0;
    rows = BUI_IMAGE_H;
    while (rows--) expected += BUI_IMAGE_STRIDE;
    if (mode == 7) return (unsigned char)(expected == BUI_IMAGE_LEN);
    return (unsigned char)(expected <= BUI_IMAGE_LEN);
}

static unsigned char find_visible(void)
{
    unsigned char row, rel, parent, mark;
    unsigned int off;
    for (row = 0; row < BUI_VIEW_ROWS; row++) {
        rel = (unsigned char)(BUI_VIEW_TOP + row);
        if (rel >= BUI_HIST_COUNT || !read_line(rel)) return 0;
        mark = (unsigned char)BROWSER_LINE[0];
        parent = rel;
        if (mark == IMAGE_CONT_MARK) {
            parent = (unsigned char)BROWSER_LINE[1];
            if (!read_line(parent)) return 0;
            mark = (unsigned char)BROWSER_LINE[0];
        }
        if (mark != IMAGE_MARK) continue;
        off = (unsigned char)BROWSER_LINE[1] |
              ((unsigned int)(unsigned char)BROWSER_LINE[2] << 8);
        if (off == BUI_IMAGE_FAILED) continue;
        if (BUI_IMAGE_READY && off == BUI_IMAGE_URL) return 0;
        if (!load_resource(off)) continue;
        BUI_IMAGE_URL = off;
        BUI_IMAGE_REL = parent;
        BUI_IMAGE_LEN = BUI_STAGE_LEN = 0;
        BUI_IMAGE_MODE = BUI_IMAGE_STRIDE = 0;
        BUI_IMAGE_READY = 0;
        return 1;
    }
    return 0;
}

static void draw_visible(void)
{
    unsigned char first, last, block, rows, x, y;
    unsigned int src;
    if (!BUI_IMAGE_READY) return;
    first = BUI_IMAGE_REL > BUI_VIEW_TOP ? BUI_IMAGE_REL : BUI_VIEW_TOP;
    last = (unsigned char)(BUI_IMAGE_REL + IMAGE_ROWS);
    if (last > BUI_VIEW_TOP + BUI_VIEW_ROWS)
        last = (unsigned char)(BUI_VIEW_TOP + BUI_VIEW_ROWS);
    if (first >= last) return;
    block = (unsigned char)((first - BUI_IMAGE_REL) * 8);
    if (block >= BUI_IMAGE_H) return;
    rows = (unsigned char)((last - first) * 8);
    if (rows > BUI_IMAGE_H - block) rows = (unsigned char)(BUI_IMAGE_H - block);
    x = (unsigned char)(BUI_TEXT_X +
        (BUI_SCREEN_COLS - BUI_TEXT_X - BUI_IMAGE_WB) / 2);
    y = (unsigned char)(BUI_CONTENT_Y + (first - BUI_VIEW_TOP) * 8);
    src = image_base() + IMAGE_HEADER_SIZE +
          (unsigned int)block * BUI_IMAGE_STRIDE;
    PIC_PAGE_K = BUI_IMAGE_MODE == 7 ? BUI_IMAGE_PAGE : BUI_CACHE_PAGE;
    PIC_PAGE2_K = 0;
#ifdef GB_MSX2
    PIC_PAGE3_K = PIC_PAGE4_K = 0;
    PIC_MODE_K = BUI_IMAGE_MODE;
    PIC_STRIDE_K = BUI_IMAGE_STRIDE;
#endif
    PIC_WB_K = BUI_IMAGE_WB;
    PIC_H_K = BUI_IMAGE_H;
    PIC_OFF_K = IMAGE_HEADER_SIZE;
    gb_pic_blit(x, y, BUI_IMAGE_WB, rows, src);
}

void main(void)
{
    UI_RES = 0;
    if (!BUI_CACHE_PAGE) return;
    if (UI_OP == 20) UI_RES = flush_image();
    else if (UI_OP == 21) UI_RES = validate_image();
    else if (UI_OP == 22) UI_RES = find_visible();
    else if (UI_OP == 23) { draw_visible(); UI_RES = 1; }
}
