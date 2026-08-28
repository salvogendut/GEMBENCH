/* FORMREF.APP - development reference for reusable form composition (#420).
 * GEMBENCH/MSX2 draws and hit-tests the dialog from a GBR resource; inherited
 * CPC and PCW builds retain the original reusable-widget implementation. */
#include "gb.h"

#ifdef GB_MSX2
#include "gbr_object.h"
#include "formref_gbr.h"
#endif

#define DEF_X 20
#define WIN_W 42
#define WIN_H 70
#define DEF_Y 42
#define TITLE_H 14

#define FORM_X 18
#define FORM_Y 48
#define FORM_W 46
#define FORM_H 94
#define ROW_X  (FORM_X + 3)
#define ROW_W  40
#define ROW_H  10
#define LABEL_W 11
#define NAME_Y (FORM_Y + 22)
#define STYLE_Y (FORM_Y + 38)
#define LEVEL_Y (FORM_Y + 54)
#define ACTION_Y (FORM_Y + 74)
#define LEVEL_X (ROW_X + LABEL_W)

static unsigned char win_x = DEF_X, win_y = DEF_Y;
static char saved_name[13] = "GEOBENCH";
static char draft_name[13];
static unsigned char saved_style, draft_style, saved_level = 3;
static unsigned char draft_level, focus;
static const char *const styles[3] = { "Classic", "Compact", "Refined" };

#ifndef GB_MSX2
static const gb_action_t actions[2] = {
    { "Save", 8 },
    { "Cancel", 11 }
};
#else
static gbr_resource_t form_resource = {
    formref_gbr,
    FORMREF_GBR_SIZE,
    FORMREF_STRING_COUNT,
    FORMREF_TREE_COUNT,
    FORMREF_OBJECT_COUNT,
    FORMREF_STRING_INDEX,
    FORMREF_TREE_TABLE,
    FORMREF_OBJECT_TABLE,
    FORMREF_STRING_DATA
};
static gbr_runtime_t form_runtime;
static unsigned int form_states[FORMREF_OBJECT_COUNT];
static unsigned char form_tree;
static unsigned char resource_ready;
static char draft_level_text[2];
static gbr_text_binding_t form_bindings[3] = {
    { FORMREF_NAME, draft_name },
    { FORMREF_STYLE, 0 },
    { FORMREF_LEVEL_VALUE, draft_level_text }
};
#endif

static void copy_name(char *dst, const char *src)
{
    unsigned char i = 0;
    while (src[i] && i < 12) { dst[i] = src[i]; i++; }
    dst[i] = 0;
}

static void level_text(char *text, unsigned char level)
{
    text[0] = (char)('0' + level);
    text[1] = 0;
}

#ifdef GB_MSX2
static unsigned char form_resource_open(void)
{
    form_tree = 0;
    return (unsigned char)(form_resource.tree_count == 1);
}

static void form_draw(void)
{
    level_text(draft_level_text, draft_level);
    form_bindings[1].text = styles[draft_style];
    (void)gbr_draw_tree(&form_runtime, (unsigned int)(ROW_X << 2), NAME_Y);
}

static unsigned char activate_object(unsigned char object_index)
{
    if (object_index == FORMREF_STYLE) {
        draft_style = (unsigned char)((draft_style + 1u) % 3u);
        return GB_FORM_REDRAW;
    }
    if (object_index == FORMREF_LEVEL_DEC) {
        draft_level = (unsigned char)(draft_level == 1 ? 9 : draft_level - 1);
        return GB_FORM_REDRAW;
    }
    if (object_index == FORMREF_LEVEL_INC) {
        draft_level = (unsigned char)(draft_level == 9 ? 1 : draft_level + 1);
        return GB_FORM_REDRAW;
    }
    if (object_index == FORMREF_SAVE) {
        /* Commit before the modal runner's single compositor restore. Screen 7
         * executes redraw commands asynchronously, so a second immediate
         * restore after return can tear the stacked desktop. */
        copy_name(saved_name, draft_name);
        saved_style = draft_style;
        saved_level = draft_level;
        return GB_FORM_ACCEPT;
    }
    if (object_index == FORMREF_CANCEL) return GB_FORM_CANCEL;
    return GB_FORM_REDRAW;
}

static unsigned char form_click(unsigned char mx, unsigned char my)
{
    unsigned char object_index;
    if (!gbr_hit_test(&form_runtime, (unsigned int)(ROW_X << 2), NAME_Y,
                      (unsigned int)(mx << 2), my, &object_index))
        return GB_FORM_STAY;
    if (!gbr_focus_set(&form_runtime, object_index)) return GB_FORM_STAY;
    focus = object_index;
    return activate_object(object_index);
}

static unsigned char form_key(unsigned char key)
{
    unsigned char n = 0;
    if (key == 0x09) {
        if (gbr_focus_next(&form_runtime, focus, 0, &focus))
            return GB_FORM_REDRAW;
        return GB_FORM_STAY;
    }
    if (focus == FORMREF_NAME) {
        if (key == 0x0D) return activate_object(FORMREF_SAVE);
        while (draft_name[n] && n < 12) n++;
        if ((key == 0x08 || key == 0x7F) && n) {
            draft_name[--n] = 0;
            return GB_FORM_REDRAW;
        }
        if (key >= 32 && key < 127 && n < 12) {
            draft_name[n++] = (char)key;
            draft_name[n] = 0;
            return GB_FORM_REDRAW;
        }
        return GB_FORM_STAY;
    }
    if (key == 0x0D || key == ' ') return activate_object(focus);
    return GB_FORM_STAY;
}
#else
static void form_draw(void)
{
    char text[2];
    gb_form_field_row(ROW_X, NAME_Y, ROW_W, ROW_H, LABEL_W,
                      "Name", draft_name,
                      focus == 1 ? GB_WIDGET_FOCUSED : 0);
    gb_form_select_row(ROW_X, STYLE_Y, ROW_W, ROW_H, LABEL_W,
                       "Style", styles[draft_style],
                       focus == 2 ? GB_WIDGET_FOCUSED : 0);
    level_text(text, draft_level);
    gb_form_label(ROW_X, LEVEL_Y, ROW_H, "Level");
    gb_stepper(LEVEL_X, LEVEL_Y, 16, ROW_H, text,
               focus == 3 ? GB_WIDGET_FOCUSED : 0);
    gb_actions(ROW_X, ACTION_Y, actions, 2, 2);
}

static unsigned char form_click(unsigned char mx, unsigned char my)
{
    unsigned char action;
    unsigned char part;
    action = gb_actions_hit(ROW_X, ACTION_Y, actions, 2, 2, mx, my);
    if (action == 0) return GB_FORM_ACCEPT;
    if (action == 1) return GB_FORM_CANCEL;
    if (gb_form_row_hit(ROW_X, NAME_Y, ROW_W, ROW_H, LABEL_W, mx, my)) {
        focus = 1;
        return GB_FORM_REDRAW;
    }
    if (gb_form_row_hit(ROW_X, STYLE_Y, ROW_W, ROW_H, LABEL_W, mx, my)) {
        focus = 2;
        draft_style = (unsigned char)((draft_style + 1) % 3);
        return GB_FORM_REDRAW;
    }
    part = gb_stepper_hit(LEVEL_X, LEVEL_Y, 16, ROW_H, mx, my);
    if (part == GB_STEPPER_DEC) {
        draft_level = (unsigned char)(draft_level == 1 ? 9 : draft_level - 1);
        focus = 3;
        return GB_FORM_REDRAW;
    }
    if (part == GB_STEPPER_INC) {
        draft_level = (unsigned char)(draft_level == 9 ? 1 : draft_level + 1);
        focus = 3;
        return GB_FORM_REDRAW;
    }
    return GB_FORM_STAY;
}

static unsigned char form_key(unsigned char key)
{
    unsigned char n = 0;
    if (key == 0x0D) return GB_FORM_ACCEPT;
    if (key == 0x09) {
        focus = (unsigned char)(focus == 3 ? 1 : focus + 1);
        return GB_FORM_REDRAW;
    }
    if (focus != 1) return GB_FORM_STAY;
    while (draft_name[n] && n < 12) n++;
    if ((key == 0x08 || key == 0x7F) && n) {
        draft_name[--n] = 0;
        return GB_FORM_REDRAW;
    }
    if (key >= 32 && key < 127 && n < 12) {
        draft_name[n++] = (char)key;
        draft_name[n] = 0;
        return GB_FORM_REDRAW;
    }
    return GB_FORM_STAY;
}
#endif

static const gb_form_modal_t form = {
    FORM_X, FORM_Y, FORM_W, FORM_H, "Form Reference",
    form_draw, form_click, form_key, GB_FORM_CLICK_AWAY
};

static void open_form(void)
{
    unsigned char result;
    copy_name(draft_name, saved_name);
    draft_style = saved_style;
    draft_level = saved_level;
#ifdef GB_MSX2
    if (!resource_ready ||
        gbr_runtime_init(&form_runtime, &form_resource, form_tree,
                         form_states, FORMREF_OBJECT_COUNT) != GBR_RT_OK)
        return;
    level_text(draft_level_text, draft_level);
    form_bindings[1].text = styles[draft_style];
    if (!gbr_bind_text(&form_runtime, form_bindings, 3)) return;
    focus = FORMREF_NAME;
    if (!gbr_focus_set(&form_runtime, focus)) return;
#else
    focus = 1;
#endif
    result = gb_form_modal_run(&form);
#ifndef GB_MSX2
    if (result == GB_FORM_ACCEPT) {
        copy_name(saved_name, draft_name);
        saved_style = draft_style;
        saved_level = draft_level;
        gb_restore_parent();
    }
#else
    (void)result;
#endif
}

static void app_draw(void)
{
    char level[8] = "Level ";
    win_x = gb_wm_x(); win_y = gb_wm_y();
    gb_fill(win_x, (unsigned char)(win_y + TITLE_H), WIN_W,
            (unsigned char)(WIN_H - TITLE_H), GB_UI_SURFACE);
    gb_textbw((unsigned char)(win_x + 2), (unsigned char)(win_y + 21), saved_name);
    gb_textbw((unsigned char)(win_x + 2), (unsigned char)(win_y + 32),
              styles[saved_style]);
    level[6] = (char)('0' + saved_level);
    level[7] = 0;
    gb_textbw((unsigned char)(win_x + 2), (unsigned char)(win_y + 43), level);
    gb_button((unsigned char)(win_x + 2), (unsigned char)(win_y + 56),
              18, 10, "Open form",
#ifdef GB_MSX2
              resource_ready ? 0 : GB_WIDGET_DISABLED
#else
              0
#endif
    );
}

static void app_click(void)
{
    unsigned char mx = gb_mx(), my = gb_my();
    win_x = gb_wm_x(); win_y = gb_wm_y();
    if (gb_button_hit((unsigned char)(win_x + 2),
                      (unsigned char)(win_y + 56),
                      18, 10, mx, my, 0))
#ifdef GB_MSX2
        if (resource_ready)
#endif
            open_form();
}

static void app_drag(void)
{
    win_x = gb_wm_x(); win_y = gb_wm_y();
    if (gb_drag_window(&win_x, &win_y, gb_wm_w(), gb_wm_h())) {
        gb_wm_setpos(win_x, win_y);
        gb_restore_parent();
    }
}

static void app_proc(void)
{
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  app_draw();      break;
        case GB_MSG_CLICK: app_click();     break;
        case GB_MSG_CLOSE: gb_wm_close();   break;
        case GB_MSG_DRAG:  app_drag();      break;
    }
}

static const gb_mwin_t appwin = {
    DEF_X, DEF_Y, WIN_W, WIN_H, 0, 0, app_proc, "Form Reference"
};

void main(void)
{
    unsigned char n;
#ifdef GB_MSX2
    resource_ready = form_resource_open();
#endif
    gb_wm_managed(&appwin);
    for (n = 64; n; n--) if (!gb_getkey()) break;
    gb_restore_parent();
}
