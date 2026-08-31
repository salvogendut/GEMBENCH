/* GBRDEMO.APP - MSX2 proof that visible UI geometry and state come from a
 * validated external GEOBENCH resource rather than application drawing code. */
#include "gb.h"
#include "gbr_object.h"

#define WIN_X 29
#define WIN_Y 34
#define WIN_W 70
#define WIN_H 132
#define TITLE_H 14
#define ROOT_INSET_COLS 1
#define RESOURCE_MAX 512
#define STATE_MAX 8

static unsigned char resource_data[RESOURCE_MAX];
static unsigned int object_states[STATE_MAX];
static gbr_resource_t resource;
static gbr_runtime_t runtime;
static unsigned char ready;
static unsigned char win_x = WIN_X;
static unsigned char win_y = WIN_Y;

static unsigned int root_x(void)
{
    return (unsigned int)((unsigned int)(win_x + ROOT_INSET_COLS) << 2);
}

static unsigned int root_y(void)
{
    return (unsigned int)(win_y + TITLE_H);
}

static unsigned char load_resource(void)
{
    unsigned int length;
    unsigned char tree_index;
    unsigned char result;
    length = gb_fs_load((char *)resource_data, RESOURCE_MAX);
    if (length == 0) return 0;
    result = gbr_open(&resource, resource_data, length);
    if (result != GBR_OK || resource.object_count > STATE_MAX) return 0;
    if (!gbr_find_tree(&resource, "HELLO", &tree_index)) return 0;
    result = gbr_runtime_init(&runtime, &resource, tree_index,
                              object_states, STATE_MAX);
    return (unsigned char)(result == GBR_RT_OK);
}

static void app_draw(void)
{
    unsigned char result;
    win_x = gb_wm_x();
    win_y = gb_wm_y();
    if (ready) {
        result = gbr_draw_tree(&runtime, root_x(), root_y());
        if (result == GBR_RT_OK) return;
        ready = 0;
    }
    gb_fill((unsigned char)(win_x + 1), (unsigned char)(win_y + TITLE_H),
            (unsigned char)(WIN_W - 2), (unsigned char)(WIN_H - TITLE_H - 1), 1);
    gb_textbw((unsigned char)(win_x + 3), (unsigned char)(win_y + TITLE_H + 8),
              "Cannot open HELLO.GBR");
}

static void app_click(void)
{
    unsigned char object_index;
    unsigned int state;
    if (!ready || !gbr_hit_test(&runtime, root_x(), root_y(), gb_mxp(), gb_my(),
                                &object_index))
        return;
    state = gbr_state(&runtime, object_index);
    if (state & GBR_STATE_SELECTED)
        (void)gbr_state_change(&runtime, object_index, 0, GBR_STATE_SELECTED);
    else
        (void)gbr_state_change(&runtime, object_index, GBR_STATE_SELECTED, 0);
    gb_restore_parent();
}

static void app_drag(void)
{
    win_x = gb_wm_x();
    win_y = gb_wm_y();
    if (gb_drag_window(&win_x, &win_y, gb_wm_w(), gb_wm_h())) {
        gb_wm_setpos(win_x, win_y);
        gb_restore_parent();
    }
}

static void app_proc(void)
{
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  app_draw();    break;
        case GB_MSG_CLICK: app_click();   break;
        case GB_MSG_CLOSE: gb_wm_close(); break;
        case GB_MSG_DRAG:  app_drag();    break;
    }
}

static const gb_mwin_t appwin = {
    WIN_X, WIN_Y, WIN_W, WIN_H, 0, 0, app_proc, "GBR Resource"
};

void main(void)
{
    unsigned char n;
    /* Registration attaches File Manager's launch argument to this window.
       Only then can gb_fs_load resolve the external .GBR document. */
    gb_wm_managed(&appwin);
    ready = load_resource();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    gb_restore_parent();
}
