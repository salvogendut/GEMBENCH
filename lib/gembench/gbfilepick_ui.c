#include "gbfilepick_ui.h"

static unsigned char fits(const gb_rect_t *r)
{
    return r && r->w >= 64 && r->h >= 148;
}

void gb_filepick_draw(const gb_filepick_t *p, const gb_rect_t *r)
{
    unsigned char i, x, y, max;
    char label[41];
    const char *status;
    if (!p || !fits(r)) return;
    x = r->x + 2; y = r->y + 16;
    gb_fill(r->x + 1, r->y + 14, r->w - 2, r->h - 15, GB_UI_SURFACE);
    max = (r->w - 4) * 2 / 3;
    if (max > 40) max = 40;
    for (i = 0; i < max && p->path[i]; ++i) label[i] = p->path[i];
    label[i] = 0;
    gb_text_semantic(x, y, label, GB_UI_TEXT, GB_UI_SURFACE);
    if (p->state == GB_FILEPICK_READY) {
        for (i = 0; i < p->count; ++i) {
            gb_filepick_label(label, p->rows + i);
            gb_text_semantic(x, y + 14 + i * 10, label, GB_UI_TEXT, GB_UI_SURFACE);
        }
    }
    gb_text_semantic(x, y + 78, "Prev      Next      Up       Cancel", GB_UI_TEXT, GB_UI_SURFACE);
    if (p->mode == GB_FILEPICK_SAVE) {
        gb_text_semantic(x, y + 94, "Name:", GB_UI_TEXT, GB_UI_SURFACE);
        gb_text_semantic(x + 9, y + 94, p->edit, GB_UI_TEXT, GB_UI_SURFACE);
        gb_text_semantic(x, y + 108, "Save here (Enter)", GB_UI_TEXT, GB_UI_SURFACE);
    }
    if (p->state == GB_FILEPICK_DONE) status = "Selected";
    else if (p->state == GB_FILEPICK_CANCELLED) status = "Cancelled";
    else if (p->error == GB_FILEPICK_BAD_NAME) status = "Invalid 8.3 name; edit to correct";
    else if (p->error == GB_FILEPICK_PATH_LIMIT) status = "Path too long";
    else if (p->error || p->state == GB_FILEPICK_ERROR) status = "Storage error; cancel to release";
    else if (p->state == GB_FILEPICK_READY)
        status = p->count ? "Select a file or folder" : "No matching files";
    else status = "Reading directory...";
    gb_text_semantic(x, y + 120, status, GB_UI_TEXT, GB_UI_SURFACE);
}

void gb_filepick_click(gb_filepick_t *p, const gb_rect_t *r,
                       unsigned char x, unsigned char y)
{
    if (!p || !fits(r) || x < r->x + 1 || x >= r->x + r->w - 1 ||
        y < r->y + 14 || y >= r->y + r->h - 1) return;
    x -= r->x + 1; y -= r->y;
    if (y >= 94 && y < 104) {
        if (x < 15) gb_filepick_page(p, 0);
        else if (x < 30) gb_filepick_page(p, 1);
        else if (x < 45) gb_filepick_up(p);
        else gb_filepick_cancel(p);
    } else if (y >= 30 && y < 90) {
        gb_filepick_choose(p, (y - 30) / 10);
    } else if (y >= 124 && y < 134) {
        gb_filepick_submit(p);
    }
}
