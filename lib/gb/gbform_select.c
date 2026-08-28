/* gbform_select.c - opt-in selector row for the form composer. */
#include "gb.h"

void gb_form_select_row(unsigned char x, unsigned char y,
                        unsigned char w, unsigned char h,
                        unsigned char label_w, const char *label,
                        const char *value, unsigned char flags)
{
    gb_form_label(x, y, h, label);
    if (label_w >= w) return;
    gb_select((unsigned char)(x + label_w), y,
              (unsigned char)(w - label_w), h, value, flags);
}
