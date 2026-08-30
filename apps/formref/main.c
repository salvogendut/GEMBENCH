/* FORMREF.APP - development reference for reusable form composition (#420).
 * GEMBENCH/MSX2 draws and hit-tests the dialog from a GBR resource; inherited
 * CPC and PCW builds retain the original reusable-widget implementation. */
#include "gb.h"

#ifdef GB_MSX2
#include "gbr_object.h"
#ifdef GB_SECONDARY_RUNTIME
#include "gbsecondary.h"
#include "secondary.h"
#endif
#ifdef GBR_BANKED
#include "gbr_bank.h"
#endif
#ifdef GBR_M7_LEGACY_FORMS
#include "formref_m7_gbr.h"
#else
#include "formref_gbr.h"
#endif
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
#if !defined(GB_MSX2) || defined(GBR_M7_LEGACY_FORMS)
static unsigned char saved_style, draft_style, saved_level = 3;
static unsigned char draft_level;
static const char *const styles[3] = { "Classic", "Compact", "Refined" };
#endif
static unsigned char focus;
#if defined(GB_MSX2) && !defined(GBR_M7_LEGACY_FORMS)
static unsigned char saved_autosave = 1, saved_layout;
#endif

#ifndef GB_MSX2
static const gb_action_t actions[2] = {
    { "Save", 8 },
    { "Cancel", 11 }
};
#else
#ifdef GBR_BANKED
static gbr_resource_t form_resource;
static unsigned char form_segment;
static const char form_resource_name[11] = {
    'F', 'O', 'R', 'M', 'R', 'E', 'F', ' ', 'G', 'B', 'R'
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
#endif
static gbr_runtime_t form_runtime;
static unsigned int form_states[FORMREF_OBJECT_COUNT];
static unsigned char form_tree;
static unsigned char resource_ready;
#ifdef GB_SECONDARY_RUNTIME
gb_secondary_t form_secondary;
#endif
#ifdef GBR_M7_LEGACY_FORMS
static char draft_level_text[2];
static gbr_text_binding_t form_bindings[3] = {
    { FORMREF_NAME, draft_name },
    { FORMREF_STYLE, 0 },
    { FORMREF_LEVEL_VALUE, draft_level_text }
};
#else
static const gbr_text_binding_t form_bindings[1] = {
    { FORMREF_NAME, draft_name }
};
#endif
#endif

static void copy_name(char *dst, const char *src)
{
    unsigned char i = 0;
    while (src[i] && i < 12) { dst[i] = src[i]; i++; }
    dst[i] = 0;
}

#if !defined(GB_MSX2) || defined(GBR_M7_LEGACY_FORMS)
static void level_text(char *text, unsigned char level)
{
    text[0] = (char)('0' + level);
    text[1] = 0;
}
#endif

#ifdef GB_MSX2
static unsigned char form_resource_open(void)
{
#ifdef GBR_BANKED
    unsigned int size;
    form_segment = gbr_segment_load(form_resource_name, &size);
    if (form_segment == 0) return 0;
    if (gbr_open_segment(&form_resource, form_segment, size) != GBR_OK) {
        gbr_segment_free(form_segment);
        form_segment = 0;
        return 0;
    }
#endif
    form_tree = 0;
    return (unsigned char)(form_resource.tree_count == 1);
}

static void form_resource_close(void)
{
#ifdef GBR_BANKED
    if (form_segment != 0) {
        gbr_segment_free(form_segment);
        form_segment = 0;
    }
#endif
}

static void form_draw(void)
{
#ifdef GBR_M7_LEGACY_FORMS
    level_text(draft_level_text, draft_level);
    form_bindings[1].text = styles[draft_style];
#endif
    (void)gbr_draw_tree(&form_runtime, (unsigned int)(ROW_X << 2), NAME_Y);
}

static unsigned char activate_object(unsigned char object_index)
{
#if !defined(GBR_FORM_ENGINE) && !defined(GBR_M7_LEGACY_FORMS)
    if (object_index == FORMREF_AUTOSAVE) {
        (void)gbr_state_change(&form_runtime, object_index,
            (gbr_state(&form_runtime, object_index) & GBR_STATE_CHECKED) ? 0 :
                GBR_STATE_CHECKED,
            (gbr_state(&form_runtime, object_index) & GBR_STATE_CHECKED) ?
                GBR_STATE_CHECKED : 0);
        return GB_FORM_REDRAW;
    }
    if (object_index == FORMREF_LAYOUT_CLASSIC ||
        object_index == FORMREF_LAYOUT_REFINED) {
        (void)gbr_state_change(&form_runtime, FORMREF_LAYOUT_CLASSIC,
            object_index == FORMREF_LAYOUT_CLASSIC ? GBR_STATE_CHECKED : 0,
            object_index == FORMREF_LAYOUT_CLASSIC ? 0 : GBR_STATE_CHECKED);
        (void)gbr_state_change(&form_runtime, FORMREF_LAYOUT_REFINED,
            object_index == FORMREF_LAYOUT_REFINED ? GBR_STATE_CHECKED : 0,
            object_index == FORMREF_LAYOUT_REFINED ? 0 : GBR_STATE_CHECKED);
        return GB_FORM_REDRAW;
    }
#endif
#ifdef GBR_M7_LEGACY_FORMS
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
#endif
    if (object_index == FORMREF_SAVE) {
        /* Commit before the modal runner's single compositor restore. Screen 7
         * executes redraw commands asynchronously, so a second immediate
         * restore after return can tear the stacked desktop. */
        copy_name(saved_name, draft_name);
#ifdef GBR_M7_LEGACY_FORMS
        saved_style = draft_style;
        saved_level = draft_level;
#else
        saved_autosave = (unsigned char)((gbr_state(&form_runtime,
                                      FORMREF_AUTOSAVE) & GBR_STATE_CHECKED) != 0);
        saved_layout = (unsigned char)((gbr_state(&form_runtime,
                                  FORMREF_LAYOUT_REFINED) & GBR_STATE_CHECKED) != 0);
#endif
        return GB_FORM_ACCEPT;
    }
    if (object_index == FORMREF_CANCEL) return GB_FORM_CANCEL;
    return GB_FORM_REDRAW;
}

static unsigned char form_click(unsigned char mx, unsigned char my)
{
    unsigned char object_index;
#ifdef GBR_FORM_ENGINE
    unsigned char event = gbr_form_click(&form_runtime,
                         (unsigned int)(ROW_X << 2), NAME_Y,
                         (unsigned int)(mx << 2), my, &object_index);
    if (!(event & GBR_FORM_HANDLED))
        return GB_FORM_STAY;
    focus = object_index;
    if (event & GBR_FORM_ACTIVATED) return activate_object(object_index);
    return (event & GBR_FORM_REDRAW) ? GB_FORM_REDRAW : GB_FORM_STAY;
#else
    if (!gbr_hit_test(&form_runtime, (unsigned int)(ROW_X << 2), NAME_Y,
                      (unsigned int)(mx << 2), my, &object_index))
        return GB_FORM_STAY;
    if (!gbr_focus_set(&form_runtime, object_index)) return GB_FORM_STAY;
    focus = object_index;
    return activate_object(object_index);
#endif
}

static unsigned char form_key(unsigned char key)
{
    unsigned char n = 0;
#ifdef GBR_FORM_ENGINE
    unsigned char object_index;
    unsigned char event;
#else
    if (key == GBR_KEY_TAB) {
        if (gbr_focus_next(&form_runtime, focus, 0, &focus))
            return GB_FORM_REDRAW;
        return GB_FORM_STAY;
    }
#endif
    if (focus == FORMREF_NAME && key != GBR_KEY_TAB &&
        key != GBR_KEY_ENTER && key != GBR_KEY_ESCAPE) {
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
#ifdef GBR_FORM_ENGINE
    event = gbr_form_key(&form_runtime, focus, key, 0, &object_index);
    if (!(event & GBR_FORM_HANDLED)) return GB_FORM_STAY;
    focus = object_index;
    if (event & GBR_FORM_ACTIVATED) return activate_object(object_index);
    return (event & GBR_FORM_REDRAW) ? GB_FORM_REDRAW : GB_FORM_STAY;
#else
    if (key == GBR_KEY_ENTER) return activate_object(FORMREF_SAVE);
    if (key == ' ') return activate_object(focus);
    return GB_FORM_STAY;
#endif
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
#ifndef GB_MSX2
    unsigned char result;
#endif
    copy_name(draft_name, saved_name);
#if !defined(GB_MSX2) || defined(GBR_M7_LEGACY_FORMS)
    draft_style = saved_style;
    draft_level = saved_level;
#endif
#ifdef GB_MSX2
    if (!resource_ready ||
        gbr_runtime_init(&form_runtime, &form_resource, form_tree,
                         form_states, FORMREF_OBJECT_COUNT) != GBR_RT_OK)
        return;
#ifdef GBR_M7_LEGACY_FORMS
    level_text(draft_level_text, draft_level);
    form_bindings[1].text = styles[draft_style];
    if (!gbr_bind_text(&form_runtime, form_bindings, 3)) return;
#else
    if (!gbr_bind_text(&form_runtime, form_bindings, 1)) return;
    (void)gbr_state_change(&form_runtime, FORMREF_AUTOSAVE,
                           saved_autosave ? GBR_STATE_CHECKED : 0,
                           saved_autosave ? 0 : GBR_STATE_CHECKED);
    (void)gbr_state_change(&form_runtime, FORMREF_LAYOUT_CLASSIC,
                           saved_layout ? 0 : GBR_STATE_CHECKED,
                           saved_layout ? GBR_STATE_CHECKED : 0);
    (void)gbr_state_change(&form_runtime, FORMREF_LAYOUT_REFINED,
                           saved_layout ? GBR_STATE_CHECKED : 0,
                           saved_layout ? 0 : GBR_STATE_CHECKED);
#endif
    focus = FORMREF_NAME;
    if (!gbr_focus_set(&form_runtime, focus)) return;
#else
    focus = 1;
#endif
#ifdef GB_MSX2
    (void)gb_form_modal_run(&form);
#else
    result = gb_form_modal_run(&form);
    if (result == GB_FORM_ACCEPT) {
        copy_name(saved_name, draft_name);
        saved_style = draft_style;
        saved_level = draft_level;
        gb_restore_parent();
    }
#endif
}

static void app_draw(void)
{
#ifdef GB_SECONDARY_RUNTIME
    volatile unsigned char *transfer = gb_secondary_transfer();
    unsigned char n;
    win_x = gb_wm_x(); win_y = gb_wm_y();
    transfer[0] = win_x;
    transfer[1] = win_y;
    transfer[2] = saved_autosave;
    transfer[3] = saved_layout;
    transfer[4] = resource_ready;
    for (n = 0; n < 13; n++) transfer[5 + n] = (unsigned char)saved_name[n];
    (void)gb_secondary_call(&form_secondary, FORMREF_SECONDARY_DRAW);
#else
#if !defined(GB_MSX2) || defined(GBR_M7_LEGACY_FORMS)
    char level[8] = "Level ";
#endif
    win_x = gb_wm_x(); win_y = gb_wm_y();
    gb_fill(win_x, (unsigned char)(win_y + TITLE_H), WIN_W,
            (unsigned char)(WIN_H - TITLE_H), GB_UI_SURFACE);
    gb_textbw((unsigned char)(win_x + 2), (unsigned char)(win_y + 21), saved_name);
#if !defined(GB_MSX2) || defined(GBR_M7_LEGACY_FORMS)
    gb_textbw((unsigned char)(win_x + 2), (unsigned char)(win_y + 32),
              styles[saved_style]);
    level[6] = (char)('0' + saved_level);
    level[7] = 0;
    gb_textbw((unsigned char)(win_x + 2), (unsigned char)(win_y + 43), level);
#else
    gb_textbw((unsigned char)(win_x + 2), (unsigned char)(win_y + 32),
              saved_autosave ? "Autosave on" : "Autosave off");
    gb_textbw((unsigned char)(win_x + 2), (unsigned char)(win_y + 43),
              saved_layout ? "Refined" : "Classic");
#endif
    gb_button((unsigned char)(win_x + 2), (unsigned char)(win_y + 56),
              18, 10, "Open form",
#ifdef GB_MSX2
              resource_ready ? 0 : GB_WIDGET_DISABLED
#else
              0
#endif
    );
#endif
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
#ifdef GB_SECONDARY_RUNTIME
    if (gb_window_drag() == GB_APP_OK) {
        win_x = gb_wm_x(); win_y = gb_wm_y();
        gb_restore_parent();
    }
#else
    win_x = gb_wm_x(); win_y = gb_wm_y();
    if (gb_drag_window(&win_x, &win_y, gb_wm_w(), gb_wm_h())) {
        gb_wm_setpos(win_x, win_y);
        gb_restore_parent();
    }
#endif
}

static void app_proc(void)
{
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  app_draw();      break;
        case GB_MSG_CLICK: app_click();     break;
        case GB_MSG_CLOSE:
#ifdef GB_MSX2
            form_resource_close();
#endif
            gb_wm_close();
            break;
        case GB_MSG_DRAG:  app_drag();      break;
    }
}

static const gb_mwin_t appwin = {
    DEF_X, DEF_Y, WIN_W, WIN_H, 0, 0, app_proc, "Form Reference"
};

void main(void)
{
    unsigned char n;
#ifdef GB_SECONDARY_RUNTIME
    if (gb_secondary_open(&form_secondary) != GB_SECONDARY_OK) return;
#endif
#ifdef GB_MSX2
    resource_ready = form_resource_open();
#endif
    gb_wm_managed(&appwin);
    for (n = 64; n; n--) if (!gb_getkey()) break;
    gb_restore_parent();
}
