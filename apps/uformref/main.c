/* Compile-once FormRef: the complete field/checkbox/radio/action workflow is
 * driven by the same embedded GBR1 bytes on every target. Mutable text, focus
 * and object state remain in the application's primary page. */
#include "gbuniversal.h"
#include "gbr_object.h"
#include "formref_gbr.h"

#define WIN_W 42u
#define WIN_H 70u
#define TITLE_H 14u
#define FORM_X 18u
#define FORM_Y 48u
#define FORM_W 46u
#define FORM_H 94u
#define ROW_X 21u
#define NAME_Y 70u

static char saved_name[13] = "GEOBENCH";
static char draft_name[13];
static unsigned char saved_autosave = 1u;
static unsigned char saved_layout;
static unsigned char focus;
static unsigned char resource_ready;
static gbr_resource_t form_resource = {
    formref_gbr, FORMREF_GBR_SIZE, FORMREF_STRING_COUNT,
    FORMREF_TREE_COUNT, FORMREF_OBJECT_COUNT, FORMREF_STRING_INDEX,
    FORMREF_TREE_TABLE, FORMREF_OBJECT_TABLE, FORMREF_STRING_DATA
};
static gbr_runtime_t form_runtime;
static unsigned int form_states[FORMREF_OBJECT_COUNT];
static const gbr_text_binding_t form_bindings[1] = {
    { FORMREF_NAME, draft_name }
};

static void copy_name(char *destination, const char *source)
{
    unsigned char index = 0;
    while (source[index] && index < 12u) {
        destination[index] = source[index];
        index++;
    }
    destination[index] = 0;
}

static void form_draw(void)
{
    (void)gbr_draw_tree(&form_runtime, (unsigned int)(ROW_X << 2), NAME_Y);
}

static unsigned char activate_object(unsigned char object)
{
    if (object == FORMREF_SAVE) {
        copy_name(saved_name, draft_name);
        saved_autosave = (unsigned char)((gbr_state(&form_runtime,
            FORMREF_AUTOSAVE) & GBR_STATE_CHECKED) != 0);
        saved_layout = (unsigned char)((gbr_state(&form_runtime,
            FORMREF_LAYOUT_REFINED) & GBR_STATE_CHECKED) != 0);
        return GB_FORM_ACCEPT;
    }
    if (object == FORMREF_CANCEL) return GB_FORM_CANCEL;
    return GB_FORM_REDRAW;
}

static unsigned char form_click(unsigned char x, unsigned char y)
{
    unsigned char object;
    unsigned char event = gbr_form_click(&form_runtime,
        (unsigned int)(ROW_X << 2), NAME_Y,
        (unsigned int)(x << 2), y, &object);
    if (!(event & GBR_FORM_HANDLED)) return GB_FORM_STAY;
    focus = object;
    if (event & GBR_FORM_ACTIVATED) return activate_object(object);
    return (event & GBR_FORM_REDRAW) ? GB_FORM_REDRAW : GB_FORM_STAY;
}

static unsigned char form_key(unsigned char key)
{
    unsigned char length = 0;
    unsigned char object;
    unsigned char event;
    if (focus == FORMREF_NAME && key != GBR_KEY_TAB &&
        key != GBR_KEY_BACKTAB &&
        key != GBR_KEY_ENTER && key != GBR_KEY_ESCAPE) {
        while (draft_name[length] && length < 12u) length++;
        if ((key == 0x08u || key == 0x7Fu) && length) {
            draft_name[--length] = 0;
            return GB_FORM_REDRAW;
        }
        if (key >= 32u && key < 127u && length < 12u) {
            draft_name[length++] = (char)key;
            draft_name[length] = 0;
            return GB_FORM_REDRAW;
        }
        return GB_FORM_STAY;
    }
    event = gbr_form_key(&form_runtime, focus,
        key == GBR_KEY_BACKTAB ? GBR_KEY_TAB : key,
        key == GBR_KEY_BACKTAB, &object);
    if (!(event & GBR_FORM_HANDLED)) return GB_FORM_STAY;
    focus = object;
    if (event & GBR_FORM_ACTIVATED) return activate_object(object);
    return (event & GBR_FORM_REDRAW) ? GB_FORM_REDRAW : GB_FORM_STAY;
}

static const gb_form_modal_t form = {
    FORM_X, FORM_Y, FORM_W, FORM_H, "Form Reference",
    form_draw, form_click, form_key, GB_FORM_CLICK_AWAY
};

static void open_form(void)
{
    copy_name(draft_name, saved_name);
    if (!resource_ready ||
        gbr_runtime_init(&form_runtime, &form_resource, 0,
                         form_states, FORMREF_OBJECT_COUNT) != GBR_RT_OK ||
        !gbr_bind_text(&form_runtime, form_bindings, 1))
        return;
    (void)gbr_state_change(&form_runtime, FORMREF_AUTOSAVE,
        saved_autosave ? GBR_STATE_CHECKED : 0,
        saved_autosave ? 0 : GBR_STATE_CHECKED);
    (void)gbr_state_change(&form_runtime, FORMREF_LAYOUT_CLASSIC,
        saved_layout ? 0 : GBR_STATE_CHECKED,
        saved_layout ? GBR_STATE_CHECKED : 0);
    (void)gbr_state_change(&form_runtime, FORMREF_LAYOUT_REFINED,
        saved_layout ? GBR_STATE_CHECKED : 0,
        saved_layout ? 0 : GBR_STATE_CHECKED);
    focus = FORMREF_NAME;
    if (!gbr_focus_set(&form_runtime, focus)) return;
    (void)gb_form_modal_run(&form);
}

static void draw(void)
{
    gb_rect_t rect;
    gb_window_rect(&rect);
    gb_fill((unsigned char)(rect.x + 1u),
            (unsigned char)(rect.y + TITLE_H),
            (unsigned char)(rect.w - 2u),
            (unsigned char)(rect.h - TITLE_H - 1u), GB_UI_SURFACE);
    gb_textbw((unsigned char)(rect.x + 2u),
              (unsigned char)(rect.y + 21u), saved_name);
    gb_textbw((unsigned char)(rect.x + 2u),
              (unsigned char)(rect.y + 32u),
              saved_autosave ? "Autosave on" : "Autosave off");
    gb_textbw((unsigned char)(rect.x + 2u),
              (unsigned char)(rect.y + 43u),
              saved_layout ? "Refined" : "Classic");
    gb_button((unsigned char)(rect.x + 2u),
              (unsigned char)(rect.y + 56u), 18u, 10u, "Open form",
              resource_ready ? 0 : GB_WIDGET_DISABLED);
}

static void click(void)
{
    gb_rect_t rect;
    gb_window_rect(&rect);
    if (resource_ready && gb_button_hit((unsigned char)(rect.x + 2u),
            (unsigned char)(rect.y + 56u), 18u, 10u,
            gb_mx(), gb_my(), 0))
        open_form();
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
    20, 42, WIN_W, WIN_H, 0, 0, window_proc, "Form Reference"
};

void main(void)
{
    if (!gb_universal_ready() || gb_screen_columns() < 80u ||
        gb_screen_lines() < 142u)
        return;
    resource_ready = (unsigned char)(form_resource.tree_count == 1u &&
        form_resource.object_count == FORMREF_OBJECT_COUNT);
    gb_wm_managed(&window);
    gb_restore_parent();
}
