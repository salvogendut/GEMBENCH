/* Compile-once GBRDEMO: validate and render the exact resource selected by the
 * Desktop/File Manager handoff. Resource bytes and mutable state stay owned by
 * this application; target storage and drawing remain behind portable calls. */
#include "gbuniversal.h"
#include "gbfsctx.h"
#include "gbr_object.h"

#define WIN_W 70u
#define WIN_H 132u
#define TITLE_H 14u
#define RESOURCE_MAX 512u
#define STATE_MAX 8u

static unsigned char resource_data[RESOURCE_MAX];
static unsigned int object_states[STATE_MAX];
static gbr_resource_t resource;
static gbr_runtime_t runtime;
static unsigned char ready;
static unsigned char resource_extra;

static unsigned char load_resource(void)
{
    gb_fsctx_t source;
    unsigned int length = 0;
    unsigned int count;
    unsigned char tree;

    source = gb_fsctx_adopt_launch();
    if (!source) return 0;
    while (length < RESOURCE_MAX) {
        count = gb_fsctx_read(source, (char *)resource_data + length,
                              (unsigned int)(RESOURCE_MAX - length));
        if (!count) {
            if (gb_fsctx_status()) {
                (void)gb_fsctx_close(source);
                return 0;
            }
            break;
        }
        length = (unsigned int)(length + count);
    }
    if (length == RESOURCE_MAX) {
        count = gb_fsctx_read(source, (char *)&resource_extra, 1u);
        if (count || gb_fsctx_status()) {
            (void)gb_fsctx_close(source);
            return 0;
        }
    }
    if (gb_fsctx_close(source) || !length ||
        gbr_open(&resource, resource_data, length) != GBR_OK ||
        resource.object_count > STATE_MAX ||
        !gbr_find_tree(&resource, "HELLO", &tree) ||
        gbr_runtime_init(&runtime, &resource, tree,
                         object_states, STATE_MAX) != GBR_RT_OK)
        return 0;
    return 1;
}

static void draw(void)
{
    gb_rect_t rect;
    gb_window_rect(&rect);
    if (ready &&
        gbr_draw_tree(&runtime, (unsigned int)(rect.x + 1u) << 2,
                      (unsigned int)(rect.y + TITLE_H)) == GBR_RT_OK)
        return;
    ready = 0;
    gb_fill((unsigned char)(rect.x + 1u),
            (unsigned char)(rect.y + TITLE_H),
            (unsigned char)(rect.w - 2u),
            (unsigned char)(rect.h - TITLE_H - 1u), GB_UI_SURFACE);
    gb_textbw((unsigned char)(rect.x + 3u),
              (unsigned char)(rect.y + TITLE_H + 8u),
              "Cannot open HELLO.GBR");
}

static void click(void)
{
    gb_rect_t rect;
    unsigned char object;
    unsigned int state;
    gb_window_rect(&rect);
    if (!ready ||
        !gbr_hit_test(&runtime, (unsigned int)(rect.x + 1u) << 2,
                      (unsigned int)(rect.y + TITLE_H), gb_mxp(), gb_my(),
                      &object))
        return;
    state = gbr_state(&runtime, object);
    if (state & GBR_STATE_SELECTED)
        (void)gbr_state_change(&runtime, object, 0, GBR_STATE_SELECTED);
    else
        (void)gbr_state_change(&runtime, object, GBR_STATE_SELECTED, 0);
    gb_wm_damage((unsigned char)(rect.x + 1u),
                 (unsigned char)(rect.y + TITLE_H),
                 (unsigned char)(rect.w - 2u),
                 (unsigned char)(rect.h - TITLE_H - 1u));
    gb_restore_parent();
}

static void window_proc(void)
{
    gb_msg_t message;
    gb_message_read(&message);
    switch (message.type) {
        case GB_MSG_DRAW: draw(); break;
        case GB_MSG_CLICK: click(); break;
        case GB_MSG_DRAG:
            if (gb_window_drag() == GB_APP_OK) gb_restore_parent();
            break;
        case GB_MSG_CLOSE: gb_wm_close(); break;
    }
}

static gb_mwin_t window = {
    0, 0, WIN_W, WIN_H, 0, 0, window_proc, "GBR Resource"
};

void main(void)
{
    unsigned char columns;
    unsigned char lines;
    if (!gb_universal_ready() ||
        gb_universal_sysinfo()->filesystem_api_version <
            GB_FSCTX_HANDOFF_API_VERSION)
        return;
    columns = gb_screen_columns();
    lines = gb_screen_lines();
    if (columns < WIN_W || lines < WIN_H) return;
    window.x = (unsigned char)((columns - WIN_W) >> 1);
    window.y = (unsigned char)((lines - WIN_H) >> 1);
    ready = load_resource();
    gb_wm_managed(&window);
    gb_restore_parent();
}
