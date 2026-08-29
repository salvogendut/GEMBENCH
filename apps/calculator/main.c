/* CALC.APP - compact fixed-point desktop calculator (#437). */
#include "gb.h"
#include "calc_core.h"
#ifdef GB_MSX2
#include "gbr_object.h"
#include "calculator_gbr.h"
#include "gbshell.h"
#include "gbdesk_catalog.h"
#endif

#define DEF_X       ((GB_COLS - WIN_W) / 2)
#define DEF_Y       24
#define WIN_W       31
#define WIN_H       144
#define TITLE_H     14
#define DISPLAY_X   2
#define DISPLAY_Y   17
#define DISPLAY_W   27
#define DISPLAY_H   20
#define BUTTON_X    2
#define BUTTON_Y    42
#define BUTTON_W    6
#define BUTTON_H    18
#define BUTTON_XGAP 1
#define BUTTON_YGAP 2
#define BUTTONS     20

static unsigned char win_x = DEF_X, win_y = DEF_Y;
static long value, accumulator;
static unsigned char pending_op;
static unsigned char new_entry = 1;
static unsigned char operand_ready = 1;
static unsigned char entry_mode;
static unsigned char decimal_entered;
static unsigned char fraction_digits;
static unsigned char negative_entry;
static const char *error_text;
static char display_text[16];

#ifdef GB_MSX2
static gbr_resource_t calculator_resource = {
    calculator_gbr,
    CALCULATOR_GBR_SIZE,
    CALCULATOR_STRING_COUNT,
    CALCULATOR_TREE_COUNT,
    CALCULATOR_OBJECT_COUNT,
    CALCULATOR_STRING_INDEX,
    CALCULATOR_TREE_TABLE,
    CALCULATOR_OBJECT_TABLE,
    CALCULATOR_STRING_DATA
};
static gbr_runtime_t calculator_runtime;
static unsigned int calculator_states[CALCULATOR_OBJECT_COUNT];
static unsigned char resource_ready;
#endif

static const char *const button_labels[BUTTONS] = {
    "C", "SQR", "%", "/",
    "7", "8", "9", "x",
    "4", "5", "6", "-",
    "1", "2", "3", "+",
    "0", ".", "+/-", "="
};
static const unsigned char button_keys[BUTTONS] = {
    'c', 'r', '%', '/',
    '7', '8', '9', '*',
    '4', '5', '6', '-',
    '1', '2', '3', '+',
    '0', '.', 'n', '='
};

static void text_red(unsigned char col, unsigned char line,
                     const char *text) __naked
{
    (void)col; (void)line; (void)text;
__asm
    ld   b,a
    ld   c,l
    ld   d,#3
    ld   e,#2
    pop  hl
    ex   (sp),hl
    call #0x800C
    ret
__endasm;
}

static unsigned char text_width(const char *text)
{
    unsigned char n = 0;
    while (text[n]) n++;
    return (unsigned char)((n * 6 + 3) >> 2);
}

static void clear_calculator(void)
{
    value = accumulator = 0;
    pending_op = 0;
    new_entry = operand_ready = 1;
    entry_mode = decimal_entered = fraction_digits = negative_entry = 0;
    error_text = 0;
}

static void set_error(unsigned char error)
{
    if (error == CALC_ERR_DIV_ZERO) error_text = "DIV ZERO";
    else if (error == CALC_ERR_NEG_ROOT) error_text = "NEG ROOT";
    else error_text = "OVERFLOW";
    pending_op = 0;
    new_entry = 1;
    operand_ready = 0;
    entry_mode = 0;
}

static void begin_entry(void)
{
    value = 0;
    new_entry = 0;
    operand_ready = entry_mode = 1;
    decimal_entered = fraction_digits = negative_entry = 0;
}

static void set_entry_magnitude(unsigned long magnitude)
{
    value = negative_entry ? -(long)magnitude : (long)magnitude;
}

static void input_digit(unsigned char digit)
{
    unsigned long magnitude;
    unsigned long add;

    if (error_text) clear_calculator();
    if (new_entry) begin_entry();
    magnitude = calc_magnitude(value);
    if (decimal_entered) {
        if (fraction_digits >= 2) return;
        add = fraction_digits ? digit : (unsigned long)digit * 10;
        magnitude += add;
        fraction_digits++;
    } else {
        add = (unsigned long)digit * (unsigned long)CALC_SCALE;
        if (magnitude > ((unsigned long)CALC_MAX - add) / 10) {
            set_error(CALC_ERR_OVERFLOW);
            return;
        }
        magnitude = magnitude * 10 + add;
    }
    set_entry_magnitude(magnitude);
}

static void input_decimal(void)
{
    if (error_text) clear_calculator();
    if (new_entry) begin_entry();
    decimal_entered = 1;
}

static unsigned char apply_pending(void)
{
    unsigned char error;
    long result = calc_binary(accumulator, value, pending_op, &error);
    if (error) {
        set_error(error);
        return 0;
    }
    value = result;
    return 1;
}

static void input_operator(unsigned char op)
{
    if (error_text) return;
    if (pending_op && operand_ready) {
        if (!apply_pending()) return;
    } else if (!pending_op) {
        accumulator = value;
    }
    accumulator = value;
    pending_op = op;
    new_entry = 1;
    operand_ready = entry_mode = 0;
    decimal_entered = fraction_digits = negative_entry = 0;
}

static void input_equals(void)
{
    if (error_text || !pending_op || !operand_ready) return;
    if (!apply_pending()) return;
    pending_op = 0;
    new_entry = 1;
    operand_ready = entry_mode = 0;
    decimal_entered = fraction_digits = negative_entry = 0;
}

static void input_percent(void)
{
    if (error_text) return;
    value /= 100L;
    new_entry = 1;
    operand_ready = 1;
    entry_mode = decimal_entered = fraction_digits = negative_entry = 0;
}

static void input_square_root(void)
{
    unsigned char error;
    long result;
    if (error_text) return;
    result = calc_square_root(value, &error);
    if (error) {
        set_error(error);
        return;
    }
    value = result;
    new_entry = 1;
    operand_ready = 1;
    entry_mode = decimal_entered = fraction_digits = negative_entry = 0;
}

static void input_sign(void)
{
    if (error_text) return;
    if (new_entry && pending_op && !operand_ready) {
        begin_entry();
        negative_entry = 1;
        return;
    }
    value = -value;
    negative_entry = (unsigned char)!negative_entry;
    operand_ready = 1;
}

static void format_value(void)
{
    unsigned long magnitude = calc_magnitude(value);
    unsigned long integer = magnitude / (unsigned long)CALC_SCALE;
    unsigned char fraction = (unsigned char)(magnitude % CALC_SCALE);
    char reverse[8];
    unsigned char rn = 0, n = 0;

    if (value < 0 || (entry_mode && negative_entry)) display_text[n++] = '-';
    do {
        reverse[rn++] = (char)('0' + integer % 10);
        integer /= 10;
    } while (integer);
    while (rn) display_text[n++] = reverse[--rn];
    if (entry_mode && decimal_entered) {
        display_text[n++] = '.';
        if (fraction_digits) display_text[n++] = (char)('0' + fraction / 10);
        if (fraction_digits > 1) display_text[n++] = (char)('0' + fraction % 10);
    } else if (fraction) {
        display_text[n++] = '.';
        display_text[n++] = (char)('0' + fraction / 10);
        if (fraction % 10) display_text[n++] = (char)('0' + fraction % 10);
    }
    display_text[n] = 0;
}

static void draw_display(void)
{
    unsigned char x = (unsigned char)(win_x + DISPLAY_X);
    unsigned char y = (unsigned char)(win_y + DISPLAY_Y);
    unsigned char width;
    const char *text;

    text = error_text;
    if (!text) {
        format_value();
        text = display_text;
    }
    width = text_width(text);
    gb_fill(x, y, DISPLAY_W, DISPLAY_H, 2);
    gb_frame(x, y, DISPLAY_W, DISPLAY_H, 3);
    text_red((unsigned char)(x + DISPLAY_W - width - 1),
             (unsigned char)(y + 6), text);
}

static unsigned char button_x(unsigned char index)
{
    return (unsigned char)(win_x + BUTTON_X +
        (index & 3) * (BUTTON_W + BUTTON_XGAP));
}

static unsigned char button_y(unsigned char index)
{
    return (unsigned char)(win_y + BUTTON_Y +
        (index >> 2) * (BUTTON_H + BUTTON_YGAP));
}

static void draw_buttons(void)
{
    unsigned char i;
#ifdef GB_MSX2
    if (resource_ready) {
        (void)gbr_draw_tree(&calculator_runtime,
                            (unsigned int)(win_x << 2), win_y);
        return;
    }
#endif
    for (i = 0; i < BUTTONS; i++)
        gb_button(button_x(i), button_y(i), BUTTON_W, BUTTON_H,
                  button_labels[i], 0);
}

static void calculator_draw(void)
{
    win_x = gb_wm_x();
    win_y = gb_wm_y();
    gb_fill(win_x, (unsigned char)(win_y + TITLE_H), WIN_W,
            (unsigned char)(WIN_H - TITLE_H), 1);
    draw_display();
    draw_buttons();
}

static unsigned char process_key(unsigned char key)
{
    if (key >= '0' && key <= '9') input_digit((unsigned char)(key - '0'));
    else if (key == '.') input_decimal();
    else if (key == '+' || key == '-' || key == '*' || key == '/')
        input_operator(key);
    else if (key == 'x' || key == 'X') input_operator('*');
    else if (key == '=' || key == 0x0D) input_equals();
    else if (key == '%') input_percent();
    else if (key == 'r' || key == 'R' || key == 's' || key == 'S')
        input_square_root();
    else if (key == 'n' || key == 'N') input_sign();
    else if (key == 'c' || key == 'C') clear_calculator();
    else return 0;
    return 1;
}

static void calculator_click(void)
{
    unsigned char i;
    unsigned char mx = gb_mx(), my = gb_my();
#ifdef GB_MSX2
    unsigned char object_index;
    if (resource_ready &&
        gbr_hit_test(&calculator_runtime, (unsigned int)(win_x << 2), win_y,
                     (unsigned int)(mx << 2), my, &object_index) &&
        object_index >= CALCULATOR_CLEAR &&
        object_index <= CALCULATOR_EQUALS) {
        gb_curhide();
        process_key(button_keys[object_index - CALCULATOR_CLEAR]);
        draw_display();
        gb_curshow();
        return;
    }
#endif
    for (i = 0; i < BUTTONS; i++) {
        if (gb_button_hit(button_x(i), button_y(i), BUTTON_W, BUTTON_H,
                          mx, my, 0)) {
            gb_curhide();
            process_key(button_keys[i]);
            draw_display();
            gb_curshow();
            return;
        }
    }
}

static void calculator_frame(void)
{
    unsigned char key;
    unsigned char changed = 0;
    while ((key = gb_getkey()) != 0)
        if (process_key(key)) changed = 1;
    if (changed) {
        gb_curhide();
        draw_display();
        gb_curshow();
    }
}

static void calculator_drag(void)
{
    win_x = gb_wm_x();
    win_y = gb_wm_y();
    if (gb_drag_window(&win_x, &win_y, WIN_W, WIN_H)) {
        gb_wm_setpos(win_x, win_y);
        gb_restore_parent();
    }
}

static void calculator_proc(void)
{
#ifdef GB_MSX2
    if (gb_msg.type == GB_MSG_SHELL) {
        if (gb_msg.p0 == GB_SHELL_ACTIVATE) {
            gb_msg.p1 = GB_SHELL_OK;
        } else if (gb_msg.p0 == GB_SHELL_CLOSE || gb_msg.p0 == GB_SHELL_QUIT) {
            gb_msg.p1 = GB_SHELL_OK;
            gb_wm_close();
        } else {
            gb_msg.p1 = GB_SHELL_BAD_REQUEST;
        }
        return;
    }
#endif
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  calculator_draw();  break;
        case GB_MSG_CLICK: calculator_click(); break;
        case GB_MSG_FRAME: calculator_frame(); break;
        case GB_MSG_CLOSE: gb_wm_close();      break;
        case GB_MSG_DRAG:  calculator_drag();  break;
    }
}

static const gb_mwin_t calculator_window = {
    DEF_X, DEF_Y, WIN_W, WIN_H, 0, 0, calculator_proc, "Calculator", 0
};

void main(void)
{
    unsigned char n;
    clear_calculator();
#ifdef GB_MSX2
    resource_ready = (unsigned char)(gbr_runtime_init(
        &calculator_runtime, &calculator_resource, 0, calculator_states,
        CALCULATOR_OBJECT_COUNT) == GBR_RT_OK);
#endif
    gb_wm_managed(&calculator_window);
#ifdef GB_MSX2
    (void)gb_shell_register_accessory(GB_DESK_ACCESSORY_CALCULATOR_ID);
#endif
    for (n = 64; n; n--) if (!gb_getkey()) break;
    gb_restore_parent();
}
