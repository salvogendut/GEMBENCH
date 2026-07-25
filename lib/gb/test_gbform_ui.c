#include <stdio.h>
#include <string.h>

#include "gb.h"

typedef struct {
    unsigned char x, y, w, h, pen;
} rect_call_t;

static int failures;
static rect_call_t last_fill, last_frame;
static unsigned char text_x[8], text_y[8], text_count;
static const char *text_value[8];
static unsigned char poll_values[8], poll_count, poll_pos;
static unsigned char mouse_x, mouse_y;
static unsigned char window_count, draw_count, click_count;
static unsigned char hide_count, show_count, restore_count;
unsigned char gb_form_modal_latch;

static void check(int ok, const char *name)
{
    if (ok) printf("ok   %s\n", name);
    else { printf("FAIL %s\n", name); failures++; }
}

void gb_fill(unsigned char x, unsigned char y, unsigned char w,
             unsigned char h, unsigned char pen)
{
    last_fill.x = x; last_fill.y = y; last_fill.w = w;
    last_fill.h = h; last_fill.pen = pen;
}

void gb_frame(unsigned char x, unsigned char y, unsigned char w,
              unsigned char h, unsigned char pen)
{
    last_frame.x = x; last_frame.y = y; last_frame.w = w;
    last_frame.h = h; last_frame.pen = pen;
}

void gb_textbw(unsigned char x, unsigned char y, const char *value)
{
    if (text_count < 8) {
        text_x[text_count] = x;
        text_y[text_count] = y;
        text_value[text_count] = value;
        text_count++;
    }
}

void gb_window(unsigned char x, unsigned char y, unsigned char w,
               unsigned char h, const char *title)
{
    (void)x; (void)y; (void)w; (void)h; (void)title;
    window_count++;
}

void gb_curhide(void) { hide_count++; }
void gb_curshow(void) { show_count++; }
void gb_restore_parent(void) { restore_count++; }

unsigned char gb_poll(void)
{
    if (poll_pos < poll_count) return poll_values[poll_pos++];
    return 0;
}

unsigned char gb_getkey(void) { return 0; }
unsigned char gb_mx(void) { return mouse_x; }
unsigned char gb_my(void) { return mouse_y; }

static void reset_draws(void)
{
    memset(&last_fill, 0, sizeof(last_fill));
    memset(&last_frame, 0, sizeof(last_frame));
    text_count = 0;
}

static void test_rows(void)
{
    reset_draws();
    gb_form_field_row(5, 10, 30, 10, 9, "Name", "Ada",
                      GB_WIDGET_FOCUSED);
    check(text_count == 2 && text_x[0] == 5 && text_y[0] == 11 &&
              !strcmp(text_value[0], "Name"),
          "field row aligns its label");
    check(last_fill.x == 14 && last_fill.y == 10 &&
              last_fill.w == 21 && last_fill.h == 10,
          "field row assigns the remaining width to its field");
    check(last_frame.pen == 3 && !strcmp(text_value[1], "Ada"),
          "field row forwards focus and value");
    check(gb_form_row_hit(5, 10, 30, 10, 9, 14, 10) &&
              !gb_form_row_hit(5, 10, 30, 10, 9, 13, 10),
          "row hit testing excludes the label");

    reset_draws();
    gb_form_select_row(3, 20, 28, 10, 8, "Mode", "Compact",
                       GB_WIDGET_FOCUSED);
    check(last_fill.x == 11 && last_fill.w == 20 &&
              last_frame.pen == 3,
          "selector row assigns geometry and focus");
}

static void test_actions(void)
{
    static const gb_form_action_t actions[3] = {
        { "Save", 8, 0 },
        { "Delete", 10, GB_WIDGET_DISABLED },
        { "Cancel", 11, 0 }
    };
    check(gb_form_actions_hit(5, 40, 10, actions, 3, 2, 6, 42) == 0,
          "action row identifies an enabled action");
    check(gb_form_actions_hit(5, 40, 10, actions, 3, 2, 16, 42) ==
              GB_FORM_NO_ACTION,
          "action row rejects a disabled action");
    check(gb_form_actions_hit(5, 40, 10, actions, 3, 2, 28, 42) == 2,
          "action row accounts for widths and gaps");
}

static void modal_draw_cb(void) { draw_count++; }

static unsigned char modal_click_accept(unsigned char x, unsigned char y)
{
    (void)x; (void)y;
    click_count++;
    return GB_FORM_ACCEPT;
}

static void set_click(unsigned char x, unsigned char y)
{
    poll_values[0] = 0;
    poll_values[1] = GB_CLICK;
    poll_values[2] = 0;
    poll_count = 3;
    poll_pos = 0;
    mouse_x = x;
    mouse_y = y;
}

static void reset_modal(void)
{
    window_count = draw_count = click_count = 0;
    hide_count = show_count = restore_count = 0;
    gb_form_modal_latch = 0;
}

static void test_modal_lifecycle(void)
{
    static const gb_form_modal_t modal = {
        8, 20, 40, 50, "Test",
        modal_draw_cb, modal_click_accept, 0, GB_FORM_CLICK_AWAY
    };
    unsigned char result;

    reset_modal();
    set_click(20, 45);
    result = gb_form_modal_run(&modal);
    check(result == GB_FORM_ACCEPT && click_count == 1,
          "modal accepts the callback result");
    check(window_count == 1 && draw_count == 1 &&
              hide_count == 1 && show_count == 1,
          "modal draws its window and contents once");
    check(!gb_form_modal_latch && restore_count == 1,
          "modal clears its latch and restores its parent");

    reset_modal();
    set_click(9, 23);
    result = gb_form_modal_run(&modal);
    check(result == GB_FORM_CANCEL && click_count == 0,
          "title close cancels before app click handling");
    check(!gb_form_modal_latch && restore_count == 1,
          "cancel follows the same cleanup lifecycle");
}

int main(void)
{
    test_rows();
    test_actions();
    test_modal_lifecycle();
    if (failures) {
        printf("\n%d reusable form test(s) FAILED\n", failures);
        return 1;
    }
    puts("\nall reusable form tests passed");
    return 0;
}
