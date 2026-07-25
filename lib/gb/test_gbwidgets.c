#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gb.h"

typedef struct {
    unsigned char x, y, w, h, pen;
} fill_call_t;

static fill_call_t fills[8];
static fill_call_t frames[8];
static unsigned char nfill, nframe, text_x, text_y;
static const char *text_value;

void gb_fill(unsigned char x, unsigned char y, unsigned char w,
             unsigned char h, unsigned char pen)
{
    fills[nfill++] = (fill_call_t){x, y, w, h, pen};
}

void gb_frame(unsigned char x, unsigned char y, unsigned char w,
              unsigned char h, unsigned char pen)
{
    frames[nframe++] = (fill_call_t){x, y, w, h, pen};
}

void gb_textbw(unsigned char x, unsigned char y, const char *text)
{
    text_x = x;
    text_y = y;
    text_value = text;
}

static void reset_calls(void)
{
    nfill = nframe = 0;
    text_x = text_y = 0;
    text_value = 0;
}

static void check(int ok, const char *name)
{
    if (!ok) {
        fprintf(stderr, "FAIL %s\n", name);
        exit(1);
    }
    printf("ok   %s\n", name);
}

int main(void)
{
    reset_calls();
    gb_button(10, 20, 20, 15, "Go", 0);
    check(nfill == 1 && fills[0].pen == 1, "button surface");
    check(nframe == 1 && frames[0].pen == 2, "button edge");
    check(text_x == 18 && text_y == 24 && !strcmp(text_value, "Go"),
          "button centred label");

    reset_calls();
    gb_field(2, 8, 30, 13, "URL", GB_WIDGET_FOCUSED);
    check(nframe == 1 && frames[0].pen == 3, "focused field accent");
    check(text_x == 3 && text_y == 11, "field text inset");

    check(gb_widget_hit(4, 5, 10, 8, 4, 5), "widget includes top-left");
    check(!gb_widget_hit(4, 5, 10, 8, 14, 12), "widget excludes right edge");

    check(gb_vscroll_hit(1, 10, 3, 80, 10, 40, 8, 2, 12,
                         GB_WIDGET_ARROWS) == GB_SCROLL_UP,
          "scroll up arrow");
    check(gb_vscroll_hit(1, 10, 3, 80, 10, 40, 8, 2, 88,
                         GB_WIDGET_ARROWS) == GB_SCROLL_DOWN,
          "scroll down arrow");
    check(gb_vscroll_hit(1, 10, 3, 80, 10, 40, 8, 2, 20,
                         GB_WIDGET_ARROWS) == GB_SCROLL_PAGE_UP,
          "scroll page up");
    check(gb_vscroll_hit(1, 10, 3, 80, 10, 40, 8, 2, 70,
                         GB_WIDGET_ARROWS) == GB_SCROLL_PAGE_DOWN,
          "scroll page down");

    reset_calls();
    gb_vscroll(1, 10, 3, 80, 10, 40, 8, GB_WIDGET_ARROWS);
    check(nfill == 4 && !strcmp(text_value, GLYPH_TRI_DOWN),
          "scrollbar track thumb and arrows");
    return 0;
}
