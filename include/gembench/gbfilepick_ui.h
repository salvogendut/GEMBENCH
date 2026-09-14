#ifndef GEMBENCH_GBFILEPICK_UI_H
#define GEMBENCH_GBFILEPICK_UI_H
#include "gbuniversal.h"
#include "gbfilepick.h"

/* Content panel for a kernel-managed window, minimum 64 columns x 148 lines.
 * No window registration, chrome, polling loop, save-under or FS calls here.
 * Draw only from the normal compositor callback. Caller steps the model from
 * eligible root frames and damages its client rectangle when changed() is set.
 * Window move/resize/focus/occlusion remain entirely kernel-owned. */
void gb_filepick_draw(const gb_filepick_t *p, const gb_rect_t *r);
void gb_filepick_click(gb_filepick_t *p, const gb_rect_t *r,
                       unsigned char x, unsigned char y);
#endif
