#include <stdio.h>
#include <string.h>

#include "gb.h"
#include "gbr_object.h"
#include "../apps/formref/formref_gbr.h"

static const unsigned char golden[] = {
#include "fixtures/hello-dialog.gbr.inc"
};

#define CALL_FILL    1
#define CALL_FRAME   2
#define CALL_TEXT    3
#define CALL_REVERSE 4
#define CALL_BUTTON  5
#define CALL_FIELD   6

typedef struct draw_call {
    unsigned char type, x, y, w, h, value;
    char text[32];
} draw_call_t;

static draw_call_t calls[16];
static unsigned char call_count;
static int failures;

static void record(unsigned char type, unsigned char x, unsigned char y,
                   unsigned char w, unsigned char h, unsigned char value,
                   const char *text)
{
    draw_call_t *call = &calls[call_count++];
    call->type = type;
    call->x = x;
    call->y = y;
    call->w = w;
    call->h = h;
    call->value = value;
    if (text) {
        strncpy(call->text, text, sizeof(call->text) - 1u);
        call->text[sizeof(call->text) - 1u] = 0;
    } else call->text[0] = 0;
}

void gb_fill(unsigned char x, unsigned char y, unsigned char w,
             unsigned char h, unsigned char pen)
{
    record(CALL_FILL, x, y, w, h, pen, 0);
}

void gb_frame(unsigned char x, unsigned char y, unsigned char w,
              unsigned char h, unsigned char pen)
{
    record(CALL_FRAME, x, y, w, h, pen, 0);
}

void gb_textbw(unsigned char x, unsigned char y, const char *text)
{
    record(CALL_TEXT, x, y, 0, 0, 0, text);
}

void gb_textrev(unsigned char x, unsigned char y, const char *text)
{
    record(CALL_REVERSE, x, y, 0, 0, 0, text);
}

void gb_button(unsigned char x, unsigned char y, unsigned char w,
               unsigned char h, const char *text, unsigned char flags)
{
    record(CALL_BUTTON, x, y, w, h, flags, text);
}

void gb_field(unsigned char x, unsigned char y, unsigned char w,
              unsigned char h, const char *text, unsigned char flags)
{
    record(CALL_FIELD, x, y, w, h, flags, text);
}

static void check(int ok, const char *name)
{
    if (ok) printf("ok   %s\n", name);
    else {
        printf("FAIL %s\n", name);
        failures++;
    }
}

static void fix_checksum(unsigned char *data, unsigned int size)
{
    unsigned int index;
    unsigned int checksum = 0;
    data[GBR_H_CHECKSUM] = 0;
    data[GBR_H_CHECKSUM + 1u] = 0;
    for (index = 0; index < size; index++)
        checksum = (unsigned int)((checksum + data[index]) & 0xffffu);
    data[GBR_H_CHECKSUM] = (unsigned char)checksum;
    data[GBR_H_CHECKSUM + 1u] = (unsigned char)(checksum >> 8);
}

static unsigned char open_runtime(const unsigned char *data,
                                  gbr_resource_t *resource,
                                  gbr_runtime_t *runtime,
                                  unsigned int *states)
{
    unsigned char tree;
    if (gbr_open(resource, data, sizeof(golden)) != GBR_OK) return 0;
    if (!gbr_find_tree(resource, "HELLO", &tree)) return 0;
    return (unsigned char)(gbr_runtime_init(runtime, resource, tree, states, 3) ==
                           GBR_RT_OK);
}

static void test_geometry_and_draw(void)
{
    gbr_resource_t resource;
    gbr_runtime_t runtime;
    gbr_rect_t rect;
    unsigned int states[3];

    check(open_runtime(golden, &resource, &runtime, states),
          "object runtime opens the golden tree");
    check(gbr_object_rect(&runtime, 0, 120, 54, &rect) &&
              rect.x == 120 && rect.y == 54 && rect.w == 272 && rect.h == 104,
          "root placement is caller controlled");
    check(gbr_object_rect(&runtime, 1, 120, 54, &rect) &&
              rect.x == 136 && rect.y == 74 && rect.w == 240 && rect.h == 16,
          "child geometry is relative to its parent");
    check(gbr_object_rect(&runtime, 2, 120, 54, &rect) &&
              rect.x == 216 && rect.y == 118 && rect.w == 80 && rect.h == 24,
          "button geometry is resolved in Screen 7 pixels");
    check(!gbr_object_rect(&runtime, 2, 65530u, 54, &rect),
          "coordinate overflow is rejected");

    call_count = 0;
    check(gbr_draw_tree(&runtime, 120, 54) == GBR_RT_OK,
          "box, text, and button tree draws");
    check(call_count == 5 && calls[0].type == CALL_FILL && calls[0].x == 30 &&
              calls[0].y == 54 && calls[0].w == 68 && calls[0].h == 104 &&
              calls[0].value == 1,
          "root box converts pixels to four-pixel columns");
    check(calls[1].type == CALL_FRAME && calls[1].value == 2,
          "ordinary box uses the edge role");
    check(calls[2].type == CALL_TEXT && !strcmp(calls[2].text, "Welcome to GEMBE") &&
              calls[3].type == CALL_TEXT && !strcmp(calls[3].text, "NCH"),
          "length-prefixed text draws in bounded chunks");
    check(calls[4].type == CALL_BUTTON && calls[4].x == 54 && calls[4].y == 118 &&
              calls[4].w == 20 && calls[4].h == 24 &&
              calls[4].value == GB_WIDGET_FOCUSED && !strcmp(calls[4].text, "OK"),
          "outlined button maps to the shared focused widget");
}

static void test_hit_and_state(void)
{
    gbr_resource_t resource;
    gbr_runtime_t runtime;
    unsigned int states[3];
    unsigned char hit;

    check(open_runtime(golden, &resource, &runtime, states),
          "hit-test runtime opens");
    check(gbr_hit_test(&runtime, 120, 54, 220, 120, &hit) && hit == 2,
          "deepest selectable object is returned");
    check(!gbr_hit_test(&runtime, 120, 54, 140, 76, &hit) &&
              hit == GBR_HIT_NONE,
          "non-selectable text is ignored");
    check(gbr_state_change(&runtime, 2, GBR_STATE_SELECTED, 0) &&
              (gbr_state(&runtime, 2) & GBR_STATE_SELECTED),
          "selected state is set in the caller overlay");
    call_count = 0;
    check(gbr_draw_tree(&runtime, 120, 54) == GBR_RT_OK &&
              calls[4].value == (GB_WIDGET_FOCUSED | GB_WIDGET_PRESSED),
          "selected button maps to pressed rendering");
    check(gbr_state_change(&runtime, 2, GBR_STATE_DISABLED, 0) &&
              !gbr_hit_test(&runtime, 120, 54, 220, 120, &hit),
          "disabled object is not selectable");
    check(!gbr_state_change(&runtime, 2, 0x8000u, 0),
          "unknown state bits are rejected");
}

static void test_text_binding_and_focus(void)
{
    gbr_resource_t resource;
    gbr_runtime_t runtime;
    unsigned int states[3];
    unsigned char focus;
    static const gbr_text_binding_t binding = { 2, "Proceed" };
    static const gbr_text_binding_t duplicate[2] = {
        { 2, "First" }, { 2, "Second" }
    };

    check(open_runtime(golden, &resource, &runtime, states),
          "binding runtime opens");
    check(gbr_bind_text(&runtime, &binding, 1),
          "caller-owned text binding is accepted");
    call_count = 0;
    check(gbr_draw_tree(&runtime, 120, 54) == GBR_RT_OK &&
              calls[4].type == CALL_BUTTON &&
              !strcmp(calls[4].text, "Proceed"),
          "dynamic text replaces an immutable resource string");
    check(!gbr_bind_text(&runtime, duplicate, 2),
          "duplicate text bindings are rejected");
    check(gbr_focus_next(&runtime, GBR_HIT_NONE, 0, &focus) && focus == 2 &&
              (gbr_state(&runtime, 2) & GBR_STATE_OUTLINED),
          "focus traversal selects the first selectable object");
    check(gbr_focus_next(&runtime, focus, 1, &focus) && focus == 2,
          "focus traversal wraps in reverse");
    check(gbr_state_change(&runtime, 2, GBR_STATE_DISABLED, 0) &&
              !gbr_focus_next(&runtime, focus, 0, &focus) &&
              focus == GBR_HIT_NONE,
          "focus traversal skips disabled objects");
}

static void test_formref_resource(void)
{
    gbr_resource_t resource;
    gbr_runtime_t runtime;
    unsigned int states[FORMREF_OBJECT_COUNT];
    unsigned char tree;
    unsigned char focus;
    unsigned char hit;
    static const gbr_text_binding_t bindings[3] = {
        { FORMREF_NAME, "GEMBENCH" },
        { FORMREF_STYLE, "Refined" },
        { FORMREF_LEVEL_VALUE, "9" }
    };

    check(gbr_open(&resource, formref_gbr, FORMREF_GBR_SIZE) == GBR_OK &&
              gbr_find_tree(&resource, "FORMREF", &tree) &&
              gbr_runtime_init(&runtime, &resource, tree, states,
                               FORMREF_OBJECT_COUNT) == GBR_RT_OK,
          "FormRef GBR opens in the target runtime");
    check(gbr_bind_text(&runtime, bindings, 3),
          "FormRef dynamic values bind");
    call_count = 0;
    check(gbr_draw_tree(&runtime, 84, 70) == GBR_RT_OK,
          "FormRef fields and composed controls draw");
    check(call_count == 11 && calls[1].type == CALL_FIELD &&
              !strcmp(calls[1].text, "GEMBENCH") &&
              calls[3].type == CALL_FIELD &&
              !strcmp(calls[3].text, "Refined") &&
              calls[7].type == CALL_FIELD && !strcmp(calls[7].text, "9"),
          "FormRef dynamic field text reaches shared widgets");
    check(gbr_hit_test(&runtime, 84, 70, 130, 88, &hit) &&
              hit == FORMREF_STYLE,
          "FormRef style hit comes from resource geometry");
    focus = FORMREF_NAME;
    check(gbr_focus_next(&runtime, focus, 0, &focus) &&
              focus == FORMREF_STYLE &&
              gbr_focus_next(&runtime, focus, 0, &focus) &&
              focus == FORMREF_LEVEL_DEC &&
              gbr_focus_next(&runtime, focus, 1, &focus) &&
              focus == FORMREF_STYLE,
          "FormRef keyboard traversal follows resource preorder");
}

static void test_unsupported_preflight(void)
{
    unsigned char data[sizeof(golden)];
    gbr_resource_t resource;
    gbr_runtime_t runtime;
    unsigned int states[3];
    memcpy(data, golden, sizeof(data));
    data[0x32 + GBR_O_TYPE] = GBR_TYPE_CHECKBOX;
    fix_checksum(data, sizeof(data));
    check(open_runtime(data, &resource, &runtime, states),
          "valid future object type opens");
    call_count = 0;
    check(gbr_draw_tree(&runtime, 120, 54) == GBR_RT_ERR_UNSUPPORTED &&
              call_count == 0,
          "unsupported visible type fails before partial drawing");
}

int main(void)
{
    test_geometry_and_draw();
    test_hit_and_state();
    test_text_binding_and_focus();
    test_formref_resource();
    test_unsupported_preflight();
    if (failures) {
        printf("\n%d GBR object test(s) FAILED\n", failures);
        return 1;
    }
    printf("\nall GBR object tests passed\n");
    return 0;
}
