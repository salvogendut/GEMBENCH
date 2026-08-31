/* Compile-once Calculator: one GBAP v4 image for every GEOBENCH-2 runtime. */
#include "gbuniversal.h"
#include "gbdefer.h"
#include "gbshell.h"
#include "../calculator/calc_core.h"

#define WIN_W       31u
#define WIN_H       144u
#define TITLE_H     14u
#define DISPLAY_X   2u
#define DISPLAY_Y   17u
#define DISPLAY_W   27u
#define DISPLAY_H   20u
#define BUTTON_X    2u
#define BUTTON_Y    42u
#define BUTTON_W    6u
#define BUTTON_H    18u
#define BUTTON_XGAP 1u
#define BUTTON_YGAP 2u
#define BUTTONS     20u
#define ACCESSORY_ID 2u

static long value, accumulator;
static unsigned char pending_op;
static unsigned char new_entry = 1u;
static unsigned char operand_ready = 1u;
static unsigned char entry_mode, decimal_entered, fraction_digits, negative_entry;
static const char *error_text;
static char display_text[16];
static unsigned char pending_menu;

#define EDIT_COL 10u
static const unsigned char calculator_menu[] = {
    1u, EDIT_COL, 'E', 'd', 'i', 't', 0u, 0u, 0u, 0u
};
static const char *const edit_items[] = { "Clear" };

static const char *const button_labels[BUTTONS] = {
    "C", "SQR", "%", "/", "7", "8", "9", "x", "4", "5", "6", "-",
    "1", "2", "3", "+", "0", ".", "+/-", "="
};
static const unsigned char button_keys[BUTTONS] = {
    'c', 'r', '%', '/', '7', '8', '9', '*', '4', '5', '6', '-',
    '1', '2', '3', '+', '0', '.', 'n', '='
};

static unsigned char text_width(const char *text)
{
    unsigned char n = 0u;
    while (text[n]) ++n;
    return (unsigned char)((n * 6u + 3u) >> 2);
}

static void clear_calculator(void)
{
    value = accumulator = 0;
    pending_op = 0u;
    new_entry = operand_ready = 1u;
    entry_mode = decimal_entered = fraction_digits = negative_entry = 0u;
    error_text = 0;
}

static void set_error(unsigned char error)
{
    if (error == CALC_ERR_DIV_ZERO) error_text = "DIV ZERO";
    else if (error == CALC_ERR_NEG_ROOT) error_text = "NEG ROOT";
    else error_text = "OVERFLOW";
    pending_op = 0u;
    new_entry = 1u;
    operand_ready = entry_mode = 0u;
}

static void begin_entry(void)
{
    value = 0;
    new_entry = 0u;
    operand_ready = entry_mode = 1u;
    decimal_entered = fraction_digits = negative_entry = 0u;
}

static void set_entry_magnitude(unsigned long magnitude)
{
    value = negative_entry ? -(long)magnitude : (long)magnitude;
}

static void input_digit(unsigned char digit)
{
    unsigned long magnitude, add;
    if (error_text) clear_calculator();
    if (new_entry) begin_entry();
    magnitude = calc_magnitude(value);
    if (decimal_entered) {
        if (fraction_digits >= 2u) return;
        add = fraction_digits ? digit : (unsigned long)digit * 10u;
        magnitude += add;
        ++fraction_digits;
    } else {
        add = (unsigned long)digit * (unsigned long)CALC_SCALE;
        if (magnitude > ((unsigned long)CALC_MAX - add) / 10u) {
            set_error(CALC_ERR_OVERFLOW);
            return;
        }
        magnitude = magnitude * 10u + add;
    }
    set_entry_magnitude(magnitude);
}

static void input_decimal(void)
{
    if (error_text) clear_calculator();
    if (new_entry) begin_entry();
    decimal_entered = 1u;
}

static unsigned char apply_pending(void)
{
    unsigned char error;
    long result = calc_binary(accumulator, value, pending_op, &error);
    if (error) { set_error(error); return 0u; }
    value = result;
    return 1u;
}

static void input_operator(unsigned char op)
{
    if (error_text) return;
    if (pending_op && operand_ready) {
        if (!apply_pending()) return;
    } else if (!pending_op) accumulator = value;
    accumulator = value;
    pending_op = op;
    new_entry = 1u;
    operand_ready = entry_mode = 0u;
    decimal_entered = fraction_digits = negative_entry = 0u;
}

static void input_equals(void)
{
    if (error_text || !pending_op || !operand_ready || !apply_pending()) return;
    pending_op = 0u;
    new_entry = 1u;
    operand_ready = entry_mode = 0u;
    decimal_entered = fraction_digits = negative_entry = 0u;
}

static void input_percent(void)
{
    if (error_text) return;
    value /= 100L;
    new_entry = operand_ready = 1u;
    entry_mode = decimal_entered = fraction_digits = negative_entry = 0u;
}

static void input_square_root(void)
{
    unsigned char error;
    long result;
    if (error_text) return;
    result = calc_square_root(value, &error);
    if (error) { set_error(error); return; }
    value = result;
    new_entry = operand_ready = 1u;
    entry_mode = decimal_entered = fraction_digits = negative_entry = 0u;
}

static void input_sign(void)
{
    if (error_text) return;
    if (new_entry && pending_op && !operand_ready) {
        begin_entry();
        negative_entry = 1u;
        return;
    }
    value = -value;
    negative_entry = (unsigned char)!negative_entry;
    operand_ready = 1u;
}

static unsigned char process_key(unsigned char key)
{
    if (key >= '0' && key <= '9') input_digit((unsigned char)(key - '0'));
    else if (key == '.') input_decimal();
    else if (key == '+' || key == '-' || key == '*' || key == '/') input_operator(key);
    else if (key == 'x' || key == 'X') input_operator('*');
    else if (key == '=' || key == 0x0Du) input_equals();
    else if (key == '%') input_percent();
    else if (key == 'r' || key == 'R' || key == 's' || key == 'S') input_square_root();
    else if (key == 'n' || key == 'N') input_sign();
    else if (key == 'c' || key == 'C') clear_calculator();
    else return 0u;
    return 1u;
}

static void format_value(void)
{
    unsigned long magnitude = calc_magnitude(value);
    unsigned long integer = magnitude / (unsigned long)CALC_SCALE;
    unsigned char fraction = (unsigned char)(magnitude % CALC_SCALE);
    char reverse[8];
    unsigned char rn = 0u, n = 0u;
    if (value < 0 || (entry_mode && negative_entry)) display_text[n++] = '-';
    do {
        reverse[rn++] = (char)('0' + integer % 10u);
        integer /= 10u;
    } while (integer);
    while (rn) display_text[n++] = reverse[--rn];
    if (entry_mode && decimal_entered) {
        display_text[n++] = '.';
        if (fraction_digits) display_text[n++] = (char)('0' + fraction / 10u);
        if (fraction_digits > 1u) display_text[n++] = (char)('0' + fraction % 10u);
    } else if (fraction) {
        display_text[n++] = '.';
        display_text[n++] = (char)('0' + fraction / 10u);
        if (fraction % 10u) display_text[n++] = (char)('0' + fraction % 10u);
    }
    display_text[n] = 0;
}

static void draw_display(unsigned char x, unsigned char y)
{
    unsigned char width;
    const char *text = error_text;
    x = (unsigned char)(x + DISPLAY_X);
    y = (unsigned char)(y + DISPLAY_Y);
    if (!text) { format_value(); text = display_text; }
    width = text_width(text);
    gb_fill(x, y, DISPLAY_W, DISPLAY_H, GB_UI_EDGE);
    gb_frame(x, y, DISPLAY_W, DISPLAY_H, GB_UI_ACCENT);
    gb_text_semantic((unsigned char)(x + DISPLAY_W - width - 1u),
                     (unsigned char)(y + 6u), text,
                     GB_UI_ACCENT, GB_UI_EDGE);
}

static unsigned char button_x(unsigned char x, unsigned char index)
{
    return (unsigned char)(x + BUTTON_X +
        (index & 3u) * (BUTTON_W + BUTTON_XGAP));
}

static unsigned char button_y(unsigned char y, unsigned char index)
{
    return (unsigned char)(y + BUTTON_Y +
        (index >> 2) * (BUTTON_H + BUTTON_YGAP));
}

static void draw_button(unsigned char x, unsigned char y, unsigned char index)
{
    const char *label = button_labels[index];
    unsigned char width = text_width(label);
    x = button_x(x, index);
    y = button_y(y, index);
    gb_fill(x, y, BUTTON_W, BUTTON_H, GB_UI_SURFACE);
    gb_frame(x, y, BUTTON_W, BUTTON_H, GB_UI_EDGE);
    gb_text_semantic((unsigned char)(x + (BUTTON_W - width) / 2u),
                     (unsigned char)(y + 5u), label,
                     GB_UI_TEXT, GB_UI_SURFACE);
}

static void draw(void)
{
    gb_rect_t rect;
    unsigned char i;
    gb_window_rect(&rect);
    /* Keep the one-column side/bottom frame painted by the compositor. */
    gb_fill((unsigned char)(rect.x + 1u),
            (unsigned char)(rect.y + TITLE_H),
            (unsigned char)(WIN_W - 2u),
            (unsigned char)(WIN_H - TITLE_H - 1u), GB_UI_SURFACE);
    draw_display(rect.x, rect.y);
    for (i = 0u; i != BUTTONS; ++i) draw_button(rect.x, rect.y, i);
}

static void damage_display(void)
{
    gb_rect_t rect;
    gb_window_rect(&rect);
    gb_wm_damage((unsigned char)(rect.x + DISPLAY_X),
                 (unsigned char)(rect.y + DISPLAY_Y), DISPLAY_W, DISPLAY_H);
    gb_restore_parent();
}

static unsigned char hit(unsigned char x, unsigned char y,
                         unsigned char w, unsigned char h,
                         unsigned char mx, unsigned char my)
{
    return (unsigned char)(mx >= x && mx < (unsigned char)(x + w) &&
                           my >= y && my < (unsigned char)(y + h));
}

static void click(void)
{
    gb_rect_t rect;
    unsigned char i, mx = gb_mx(), my = gb_my();
    gb_window_rect(&rect);
    for (i = 0u; i != BUTTONS; ++i) {
        if (hit(button_x(rect.x, i), button_y(rect.y, i),
                BUTTON_W, BUTTON_H, mx, my)) {
            (void)process_key(button_keys[i]);
            damage_display();
            return;
        }
    }
}

static void frame(void)
{
    unsigned char key, changed = 0u;
    if (pending_menu) {
        unsigned char selected;
        pending_menu = 0u;
        selected = gb_universal_popup(EDIT_COL, edit_items, 1u);
        if (selected == 0u) {
            clear_calculator();
            damage_display();
        }
        return;
    }
    while ((key = gb_getkey()) != 0u) changed |= process_key(key);
    if (changed) damage_display();
}

static void window_proc(void)
{
    gb_msg_t message;
    gb_message_read(&message);
    if (message.type == GB_MSG_DEFER) {
        const gb_defer_message_t *deferred = gb_defer_current();
        if (deferred && deferred->type == GB_DEFER_SHELL && deferred->p0 == 2u)
            gb_message_set_p2(1u);
        return;
    }
    switch (message.type) {
        case GB_MSG_DRAW:  draw();        break;
        case GB_MSG_CLICK: click();       break;
        case GB_MSG_FRAME: frame();       break;
        case GB_MSG_MENU:
            if (gb_universal_popup_active()) gb_universal_popup_close();
            else if (message.p0 >= EDIT_COL && message.p0 < 16u)
                pending_menu = 1u;
            break;
        case GB_MSG_CLOSE: gb_wm_close(); break;
    }
}

static gb_mwin_kind_t calculator_window = {
    { 0u, 24u, WIN_W, WIN_H, 0u, 0u, window_proc, "Calculator", 0 },
    GB_WK_TITLE | GB_WK_CLOSE | GB_WK_MOVE
};

void main(void)
{
    unsigned char columns;
    if (!gb_universal_ready()) return;
    columns = gb_screen_columns();
    if (columns < WIN_W || gb_screen_lines() < WIN_H) return;
    calculator_window.window.x = (unsigned char)((columns - WIN_W) >> 1);
    clear_calculator();
    gb_wm_managed_kind(&calculator_window);
    gb_menu(calculator_menu);
    (void)gb_shell_register_accessory(ACCESSORY_ID);
    (void)gb_defer_register(window_proc);
    gb_restore_parent();
}
