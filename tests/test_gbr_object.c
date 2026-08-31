#include <stdio.h>
#include <string.h>

#include "gb.h"
#include "gbr_object.h"
#include "../apps/formref/formref_gbr.h"
#include "../apps/calculator/calculator_gbr.h"

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

static draw_call_t calls[64];
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
    check(calls[2].type == CALL_TEXT && !strcmp(calls[2].text, "Welcome to GEOBE") &&
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
    static const gbr_text_binding_t bindings[1] = {
        { FORMREF_NAME, "GEMBENCH" }
    };

    check(gbr_open(&resource, formref_gbr, FORMREF_GBR_SIZE) == GBR_OK &&
              gbr_find_tree(&resource, "FORMREF", &tree) &&
              gbr_runtime_init(&runtime, &resource, tree, states,
                               FORMREF_OBJECT_COUNT) == GBR_RT_OK,
          "FormRef GBR opens in the target runtime");
    check(gbr_bind_text(&runtime, bindings, 1),
          "FormRef dynamic values bind");
    call_count = 0;
    check(gbr_draw_tree(&runtime, 84, 70) == GBR_RT_OK,
          "FormRef fields and composed controls draw");
    check(call_count == 16 && calls[1].type == CALL_FIELD &&
              !strcmp(calls[1].text, "GEMBENCH"),
          "FormRef dynamic name reaches the shared field widget");
    check(gbr_hit_test(&runtime, 84, 70, 88, 88, &hit) &&
              hit == FORMREF_AUTOSAVE,
          "FormRef checkbox hit comes from resource geometry");
    focus = FORMREF_NAME;
    check(gbr_focus_next(&runtime, focus, 0, &focus) &&
              focus == FORMREF_AUTOSAVE &&
              gbr_focus_next(&runtime, focus, 0, &focus) &&
              focus == FORMREF_LAYOUT_CLASSIC &&
              gbr_focus_next(&runtime, focus, 1, &focus) &&
              focus == FORMREF_AUTOSAVE,
          "FormRef keyboard traversal follows resource preorder");
}

static void test_form_semantics(void)
{
    gbr_resource_t resource;
    gbr_runtime_t runtime;
    unsigned int states[FORMREF_OBJECT_COUNT];
    unsigned char tree;
    unsigned char object;
    unsigned char event;

    check(gbr_open(&resource, formref_gbr, FORMREF_GBR_SIZE) == GBR_OK &&
              gbr_find_tree(&resource, "FORMREF", &tree) &&
              gbr_runtime_init(&runtime, &resource, tree, states,
                               FORMREF_OBJECT_COUNT) == GBR_RT_OK,
          "form semantics open the FormRef resource");
    check((gbr_state(&runtime, FORMREF_AUTOSAVE) & GBR_STATE_CHECKED) &&
              (gbr_state(&runtime, FORMREF_LAYOUT_CLASSIC) & GBR_STATE_CHECKED) &&
              !(gbr_state(&runtime, FORMREF_LAYOUT_REFINED) & GBR_STATE_CHECKED),
          "declared checkbox and radio state initializes in the overlay");

    event = gbr_form_click(&runtime, 84, 70, 88, 88, &object);
    check(object == FORMREF_AUTOSAVE &&
              (event & (GBR_FORM_HANDLED | GBR_FORM_REDRAW |
                        GBR_FORM_ACTIVATED)) ==
                  (GBR_FORM_HANDLED | GBR_FORM_REDRAW | GBR_FORM_ACTIVATED) &&
              !(gbr_state(&runtime, FORMREF_AUTOSAVE) & GBR_STATE_CHECKED),
          "checkbox click focuses, activates, and toggles state");

    event = gbr_form_click(&runtime, 84, 70, 164, 102, &object);
    check(object == FORMREF_LAYOUT_REFINED &&
              (event & GBR_FORM_ACTIVATED) &&
              !(gbr_state(&runtime, FORMREF_LAYOUT_CLASSIC) & GBR_STATE_CHECKED) &&
              (gbr_state(&runtime, FORMREF_LAYOUT_REFINED) & GBR_STATE_CHECKED),
          "radio click selects exactly one sibling in its group");

    event = gbr_form_key(&runtime, FORMREF_LAYOUT_REFINED,
                         GBR_KEY_LEFT, 0, &object);
    check(object == FORMREF_LAYOUT_CLASSIC && (event & GBR_FORM_ACTIVATED) &&
              (gbr_state(&runtime, FORMREF_LAYOUT_CLASSIC) & GBR_STATE_CHECKED) &&
              !(gbr_state(&runtime, FORMREF_LAYOUT_REFINED) & GBR_STATE_CHECKED),
          "radio cursor navigation wraps selection through the group");

    event = gbr_form_key(&runtime, FORMREF_AUTOSAVE,
                         GBR_KEY_TAB, 1, &object);
    check(object == FORMREF_NAME &&
              event == (GBR_FORM_HANDLED | GBR_FORM_REDRAW),
          "reverse Tab uses shared focus traversal");
    event = gbr_form_key(&runtime, FORMREF_NAME, GBR_KEY_ENTER, 0, &object);
    check(object == FORMREF_SAVE && (event & GBR_FORM_EXIT),
          "Enter activates the enabled default exit object");
    event = gbr_form_key(&runtime, FORMREF_AUTOSAVE,
                         GBR_KEY_ENTER, 0, &object);
    check(object == FORMREF_AUTOSAVE && (event & GBR_FORM_ACTIVATED) &&
              (gbr_state(&runtime, FORMREF_AUTOSAVE) & GBR_STATE_CHECKED),
          "Enter activates a focused checkbox instead of the default");
    event = gbr_form_key(&runtime, FORMREF_NAME, GBR_KEY_ESCAPE, 0, &object);
    check(object == FORMREF_CANCEL && (event & GBR_FORM_EXIT),
          "Escape activates the non-default exit object");
}

static void test_calculator_resource(void)
{
    gbr_resource_t resource;
    gbr_runtime_t runtime;
    unsigned int states[CALCULATOR_OBJECT_COUNT];
    unsigned char hit;

    check(gbr_open(&resource, calculator_gbr, CALCULATOR_GBR_SIZE) == GBR_OK &&
              gbr_runtime_init(&runtime, &resource, 0, states,
                               CALCULATOR_OBJECT_COUNT) == GBR_RT_OK,
          "Calculator production panel opens from its GBR resource");
    call_count = 0;
    check(gbr_draw_tree(&runtime, 80, 20) == GBR_RT_OK && call_count == 20,
          "Calculator draws all twenty buttons from the resource tree");
    check(calls[0].type == CALL_BUTTON && calls[0].x == 22 &&
              calls[0].y == 62 && !strcmp(calls[0].text, "C") &&
              calls[19].type == CALL_BUTTON && calls[19].x == 43 &&
              calls[19].y == 142 && !strcmp(calls[19].text, "=") &&
              (calls[19].value & GB_WIDGET_FOCUSED),
          "Calculator resource preserves geometry and marks the default key");
    check(gbr_hit_test(&runtime, 80, 20, 174, 145, &hit) &&
              hit == CALCULATOR_EQUALS,
          "Calculator pointer routing returns the resource object identity");
}

static void test_unsupported_preflight(void)
{
    unsigned char data[sizeof(golden)];
    gbr_resource_t resource;
    gbr_runtime_t runtime;
    unsigned int states[3];
    memcpy(data, golden, sizeof(data));
    data[0x32 + GBR_O_TYPE] = GBR_TYPE_ICON;
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
    test_form_semantics();
    test_calculator_resource();
    test_unsupported_preflight();
    if (failures) {
        printf("\n%d GBR object test(s) FAILED\n", failures);
        return 1;
    }
    printf("\nall GBR object tests passed\n");
    return 0;
}
