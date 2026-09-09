/* Notepad's buffer/selection/wrap policy, extracted from apps/notepad/main.c.
 * No graphics, firmware, filesystem or fixed-address state. The universal
 * binding uses this actual editor model, not the file-chooser diagnostic.
 * Display rows are 16-bit: 4096 short lines must not wrap at row 255.
 */
#ifndef UNOTEPAD_EDITOR_H
#define UNOTEPAD_EDITOR_H
#include <string.h>
#define NP_MAX 4096u
#define NP_LINE_MAX 85u
typedef struct {
    char text[NP_MAX];
    unsigned int len, cur, first, anchor, sel_a, sel_b;
    unsigned char selected, dirty;
} np_editor_t;

static void np_reset(np_editor_t *e)
{
    e->len = e->cur = e->first = e->anchor = e->sel_a = e->sel_b = 0;
    e->selected = e->dirty = 0;
}

static void np_advance(unsigned char ch, unsigned char wrap,
                       unsigned int *row, unsigned char *col)
{
    if (ch == '\n') { ++*row; *col = 0; }
    else if (ch >= 32 && ++*col == wrap) { ++*row; *col = 0; }
}

static void np_position(const np_editor_t *e, unsigned int index,
                        unsigned char wrap, unsigned int *row,
                        unsigned char *col)
{
    unsigned int i;
    *row = 0; *col = 0;
    if (!wrap) return;
    if (index > e->len) index = e->len;
    for (i = 0; i < index; ++i)
        np_advance((unsigned char)e->text[i], wrap, row, col);
}

static unsigned int np_index(const np_editor_t *e, unsigned int target,
                             unsigned char column, unsigned char wrap)
{
    unsigned int i, row = 0;
    unsigned char col = 0, ch;
    if (!wrap) return 0;
    for (i = 0; i < e->len; ++i) {
        if (row == target && col >= column) return i;
        ch = (unsigned char)e->text[i];
        if (ch == '\n' && row == target) return i;
        np_advance(ch, wrap, &row, &col);
        if (row > target) return i;
    }
    return e->len;
}

static void np_follow(np_editor_t *e, unsigned char wrap, unsigned char rows)
{
    unsigned int row;
    unsigned char col;
    if (!rows) return;
    np_position(e, e->cur, wrap, &row, &col);
    if (row < e->first) e->first = row;
    else if (row - e->first >= rows) e->first = row - rows + 1;
}

static void np_select(np_editor_t *e, unsigned int index)
{
    if (index > e->len) index = e->len;
    e->cur = index;
    e->sel_a = index < e->anchor ? index : e->anchor;
    e->sel_b = index > e->anchor ? index : e->anchor;
    e->selected = e->sel_a != e->sel_b;
}

static void np_all(np_editor_t *e)
{
    e->anchor = 0;
    np_select(e, e->len);
}

/* Replacement is all-or-nothing. The input must not alias e->text; clipboard
 * reads are staged before mutation so a failed read never deletes selection. */
static unsigned char np_replace(np_editor_t *e, const char *data,
                                 unsigned int count)
{
    unsigned int a = e->cur, b = e->cur, tail;
    if (e->selected) { a = e->sel_a; b = e->sel_b; }
    if (count > NP_MAX - e->len + b - a || (!data && count)) return 0;
    if (a == b && !count) return 0;
    tail = e->len - b;
    memmove(e->text + a + count, e->text + b, tail);
    if (count) memcpy(e->text + a, data, count);
    e->len = e->len - (b - a) + count;
    e->cur = a + count;
    e->selected = 0; e->dirty = 1;
    return 1;
}

static unsigned char np_key(np_editor_t *e, unsigned char key)
{
    char ch;
    if (key == 8 || key == 127) {
        if (!e->selected) {
            if (!e->cur) return 0;
            e->sel_a = e->cur - 1; e->sel_b = e->cur; e->selected = 1;
        }
        return np_replace(e, 0, 0);
    }
    if (key == 9) return np_replace(e, "    ", 4);
    if (key == 13) key = '\n';
    else if (key < 32 || key >= 127) return 0;
    ch = (char)key;
    return np_replace(e, &ch, 1);
}

/* Commit only a complete load; caller retains the old editor until then.
 * BASIC normalization matches native Notepad: strip every CR on input. */
static unsigned char np_loaded(np_editor_t *e, const char *data,
                                unsigned int length, unsigned char basic)
{
    unsigned int i, n = 0;
    if (length > NP_MAX || (!data && length)) return 0;
    for (i = 0; i < length; ++i)
        if (!basic || data[i] != '\r') e->text[n++] = data[i];
    np_reset(e); e->len = n;
    return 1;
}

/* Stream BASIC's CRLF expansion without rewriting the editor. Even a full
 * 4 KiB document can be saved correctly; unlike the old in-place expansion,
 * this never silently falls back to LF when the expanded form is too large.
 * phase: 0 normal, 1 pending LF, 2 final CR, 3 final LF, 4 complete.
 */
typedef struct { unsigned int offset; unsigned char phase; } np_bas_t;
static unsigned int np_bas_chunk(const np_editor_t *e, np_bas_t *s,
                                 char *out, unsigned int capacity)
{
    unsigned int n = 0;
    unsigned char ch;
    while (n < capacity && s->phase != 4) {
        if (s->phase == 1 || s->phase == 3) {
            out[n++] = '\n';
            s->phase = s->phase == 3 ? 4 : 0;
        } else if (s->phase == 2) {
            out[n++] = '\r'; s->phase = 3;
        } else if (s->offset == e->len) {
            s->phase = !e->len || e->text[e->len - 1] != '\n' ? 2 : 4;
        } else {
            ch = (unsigned char)e->text[s->offset++];
            if (ch == '\n') { out[n++] = '\r'; s->phase = 1; }
            else out[n++] = (char)ch;
        }
    }
    return n;
}
#endif
