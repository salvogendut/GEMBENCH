/* FORMREF.APP - development reference for reusable form composition (#420). */
#include "gb.h"

#define DEF_X 20
#define DEF_Y 42
#define WIN_W 42
#define WIN_H 70
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
static const gb_action_t actions[2] = {
    { "Save", 8 },
    { "Cancel", 11 }
};

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
    focus = 1;
    result = gb_form_modal_run(&form);
    if (result == GB_FORM_ACCEPT) {
        copy_name(saved_name, draft_name);
        saved_style = draft_style;
        saved_level = draft_level;
        gb_restore_parent();
    }
}

static void app_draw(void)
{
    char level[8] = "Level ";
    win_x = gb_wm_x(); win_y = gb_wm_y();
    gb_fill(win_x, (unsigned char)(win_y + TITLE_H), WIN_W,
            (unsigned char)(WIN_H - TITLE_H), 1);
    gb_textbw((unsigned char)(win_x + 2), (unsigned char)(win_y + 21), saved_name);
    gb_textbw((unsigned char)(win_x + 2), (unsigned char)(win_y + 32),
              styles[saved_style]);
    level[6] = (char)('0' + saved_level);
    level[7] = 0;
    gb_textbw((unsigned char)(win_x + 2), (unsigned char)(win_y + 43), level);
    gb_button((unsigned char)(win_x + 2), (unsigned char)(win_y + 56),
              18, 10, "Open form", 0);
}

static void app_click(void)
{
    unsigned char mx = gb_mx(), my = gb_my();
    win_x = gb_wm_x(); win_y = gb_wm_y();
    if (gb_button_hit((unsigned char)(win_x + 2),
                      (unsigned char)(win_y + 56),
                      18, 10, mx, my, 0))
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
    gb_wm_managed(&appwin);
    for (n = 64; n; n--) if (!gb_getkey()) break;
    gb_restore_parent();
}
