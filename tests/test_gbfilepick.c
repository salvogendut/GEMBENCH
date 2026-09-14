/* Actual chooser, renderer, document I/O and shared FS client; only the storage
 * gate and drawing primitives are fake. No emulator acceptance is implied. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_FSCTX_PLATFORM_HEADER "filepick_client_provider.h"
#include "../lib/gembench/gbfsctx.c"
#include "gbfilepick_ui.h"
#include "gbdocio.h"

unsigned char filepick_request[32], filepick_transfer[512];

static struct { unsigned char live; unsigned int cursor, offset; char path[48], name[11]; } ctx[4];
static unsigned int calls, fail_at, close_fail, total = 19, batch_limit = 4;
static unsigned char failure = GB_FSCTX_ERR_IO;
static const char payload[] = "Notepad chooser readback\r\n";

unsigned char gb_fsctx_call(unsigned char op)
{
    unsigned int k = (F_HANDLE & 255) - 1, n;
    unsigned char *out = (unsigned char *)F_TRANSFER;
    ++calls; F_STATUS = 0;
    if (calls == fail_at || (op == OP_CLOSE && close_fail)) {
        if (op == OP_CLOSE && close_fail) --close_fail;
        return F_STATUS = failure;
    }
    if (op == OP_ALLOC) {
        assert(F_DRIVE == 0 || F_DRIVE == 2);
        for (k = 0; k < 4 && ctx[k].live; ++k) { }
        if (k == 4) return F_STATUS = GB_FSCTX_ERR_FULL;
        memset(ctx + k, 0, sizeof(ctx[k])); ctx[k].live = 1;
        F_HANDLE = 0x0101 + k;
        return 0;
    }
    if (k >= 4 || !ctx[k].live || (F_HANDLE >> 8) != 1)
        return F_STATUS = GB_FSCTX_ERR_STALE;
    switch (op) {
    case OP_CLOSE: ctx[k].live = 0; break;
    case OP_SET_PATH: strcpy(ctx[k].path, (const char *)out); break;
    case OP_SET_NAME: memcpy(ctx[k].name, out, 11); break;
    case OP_ACTIVATE:
        if (!strcmp(ctx[k].path, "/MISSING")) return F_STATUS = GB_FSCTX_ERR_IO;
        break;
    case OP_DIR_BATCH:
        assert(F_LENGTH == 4);
        if (F_FLAGS) ctx[k].cursor = 0;
        n = 0;
        if (!strcmp(ctx[k].path, "/EMPTY")) { F_ACTUAL = 0; break; }
        while (n < batch_limit && ctx[k].cursor < total) {
            unsigned int i = ctx[k].cursor++;
            char raw[12];
            memset(out, 0, 16);
            if (i == 0) { memcpy(out, "DIR     EXT", 11); out[11] = 16; }
            else if (i == 1) memcpy(out, "HIDDEN  BIN", 11);
            else if (i == 2) { memcpy(out, ".          ", 11); out[11] = 16; }
            else if (i == 3) { memcpy(out, "VOLUME     ", 11); out[11] = 8; }
            else {
                snprintf(raw, sizeof(raw), "FILE%04uTXT", i % 10000);
                memcpy(out, raw, 11);
            }
            ++n; out += 16;
        }
        F_ACTUAL = n;
        break;
    case OP_REWIND: ctx[k].offset = 0; break;
    case OP_READ:
        n = sizeof(payload) - 1 - ctx[k].offset;
        if (n > F_LENGTH) n = F_LENGTH;
        memcpy(out, payload + ctx[k].offset, n);
        ctx[k].offset += n; F_ACTUAL = n;
        break;
    default: assert(!"chooser must not write or mutate another document context");
    }
    return F_STATUS;
}

static unsigned int active(void)
{
    unsigned int i, n = 0;
    for (i = 0; i < 4; ++i) n += ctx[i].live;
    return n;
}
static void reset(void)
{
    assert(!active()); calls = fail_at = close_fail = 0;
    total = 19; batch_limit = 4; failure = GB_FSCTX_ERR_IO;
}
static void step(gb_filepick_t *p)
{
    unsigned int before = calls;
    gb_filepick_step(p);
    assert(calls <= before + 1);
}
static void finish(gb_filepick_t *p)
{
    unsigned int guard = 20000;
    while (p->state != GB_FILEPICK_READY && p->state != GB_FILEPICK_DONE &&
           p->state != GB_FILEPICK_ERROR && p->state != GB_FILEPICK_CANCELLED) {
        assert(guard--); step(p);
    }
    { unsigned int before = calls; step(p); assert(calls == before); }
}
static void cancel(gb_filepick_t *p)
{
    unsigned int before = calls;
    gb_filepick_cancel(p); assert(calls == before);
    finish(p); assert(!p->context && p->state == GB_FILEPICK_CANCELLED);
}
static void begin(gb_filepick_t *p, const char *path, unsigned char mode)
{
    unsigned int before = calls;
    assert(gb_filepick_begin(p, 0, path, "TXTBASCFG", mode));
    assert(calls == before); finish(p);
    assert(p->state == GB_FILEPICK_READY);
}

static void browsing(void)
{
    gb_filepick_t p = {0}, other = {0};
    gb_fsctx_t accepted;
    gb_docio_t job = {0};
    char data[128], label[14];
    unsigned int i;
    reset(); begin(&p, "/", GB_FILEPICK_OPEN);
    assert(p.count == 6 && p.more && p.scanned == 7);
    assert(!memcmp(p.rows[1].name, "FILE0004TXT", 11));
    gb_filepick_label(label, p.rows); assert(!strcmp(label, "DIR.EXT/"));
    gb_filepick_page(&p, 1); finish(&p);
    assert(p.offset == 6 && p.count == 6 && p.more);
    assert(!memcmp(p.rows[0].name, "FILE0009TXT", 11));
    gb_filepick_page(&p, 1); finish(&p);
    assert(p.offset == 12 && p.count == 4 && !p.more);
    gb_filepick_page(&p, 1); assert(p.state == GB_FILEPICK_READY && p.offset == 12);
    gb_filepick_page(&p, 0); finish(&p);
    gb_filepick_page(&p, 0); finish(&p);
    gb_filepick_up(&p); assert(p.state == GB_FILEPICK_READY);
    gb_filepick_choose(&p, 0); finish(&p); assert(!strcmp(p.path, "/DIR.EXT"));
    gb_filepick_choose(&p, 0); finish(&p); assert(!strcmp(p.path, "/DIR.EXT/DIR.EXT"));
    gb_filepick_up(&p); finish(&p); assert(!strcmp(p.path, "/DIR.EXT"));
    begin(&other, "/EMPTY", GB_FILEPICK_SAVE);
    assert(!other.count && !other.more && active() == 2);
    assert(!strcmp(ctx[(p.context & 255)-1].path, "/DIR.EXT"));
    gb_filepick_choose(&p, 1); finish(&p);
    assert(p.state == GB_FILEPICK_DONE && !memcmp(p.name, "FILE0004TXT", 11));
    accepted = gb_filepick_take(&p); assert(accepted && !p.context);
    assert(!gb_filepick_take(&p));
    memset(data, 0x55, sizeof(data));
    assert(gb_docio_load(&job, accepted, data, sizeof(data)));
    for (i = 0; gb_docio_busy(&job); ++i) { assert(i < 10); gb_docio_step(&job); }
    assert(job.state == GB_DOCIO_DONE && job.transferred == sizeof(payload)-1);
    assert(!memcmp(data, payload, sizeof(payload)-1) && data[sizeof(payload)-1] == 0x55);
    assert(!gb_fsctx_close(accepted)); cancel(&other); assert(!active());
    /* Partial batches must not become EOF; page counters must exceed 255. */
    reset(); total = 320; batch_limit = 1; begin(&p, "/", GB_FILEPICK_OPEN);
    for (i = 0; i < 50; ++i) { gb_filepick_page(&p, 1); finish(&p); }
    assert(p.offset == 300 && p.count == 6 && p.more);
    cancel(&p); reset();
    /* Path growth rejects overflow without changing the live context/path. */
    begin(&p, "/AAAAAAAA/BBBBBBBB/CCCCCCCC/DDDDDDDD/EEEEEEEE", GB_FILEPICK_OPEN);
    gb_filepick_choose(&p, 0);
    assert(p.error == GB_FILEPICK_PATH_LIMIT && p.state == GB_FILEPICK_READY);
    assert(!strcmp(p.path, ctx[(p.context & 255)-1].path)); cancel(&p);
}

static void naming(void)
{
    const char *bad[] = {"", ".TXT", "..", "NAME.", "123456789", "FILE.ABCD", "A/B.TXT",
                        "A\\B.TXT", "A*.TXT", "A?.TXT", "A B.TXT", "A:B.TXT", "A..TXT"};
    gb_filepick_t p = {0};
    unsigned int i, before;
    reset(); begin(&p, "/", GB_FILEPICK_SAVE);
    before = calls;
    for (i = 0; i < sizeof(bad)/sizeof(bad[0]); ++i) {
        p.error = 0; strcpy(p.edit, bad[i]); gb_filepick_submit(&p);
        assert(p.state == GB_FILEPICK_READY && p.error == GB_FILEPICK_BAD_NAME);
        assert(calls == before);
    }
    p.error = 0; memset(p.edit, 'A', sizeof(p.edit)); gb_filepick_submit(&p);
    assert(p.error == GB_FILEPICK_BAD_NAME); p.edit[0] = 0;
    gb_filepick_choose(&p, 1);
    assert(!strcmp(p.edit, "FILE0004.TXT") && p.state == GB_FILEPICK_READY);
    gb_filepick_key(&p, 'x'); assert(p.error == GB_FILEPICK_BAD_NAME);
    gb_filepick_key(&p, 13); assert(p.state == GB_FILEPICK_READY); /* no truncated save */
    gb_filepick_key(&p, 8); gb_filepick_key(&p, 't');
    gb_filepick_key(&p, 13); assert(p.state == GB_FILEPICK_NAME);
    finish(&p); assert(!memcmp(p.name, "FILE0004TXT", 11));
    cancel(&p); begin(&p, "/", GB_FILEPICK_SAVE);
    strcpy(p.edit, "hello.bas"); gb_filepick_submit(&p); finish(&p);
    assert(!memcmp(p.name, "HELLO   BAS", 11)); cancel(&p);
    begin(&p, "/", GB_FILEPICK_SAVE); strcpy(p.edit, "README");
    gb_filepick_submit(&p); finish(&p); assert(!memcmp(p.name, "README     ", 11));
    cancel(&p);
}

static void failures(void)
{
    gb_filepick_t p = {0}, saved;
    unsigned char e;
    unsigned int at, before;
    reset();
    assert(!gb_filepick_begin(0, 0, "/", 0, 0));
    assert(!gb_filepick_begin(&p, 0, "relative", 0, 0));
    assert(!gb_filepick_begin(&p, 0, "/TRAIL/", 0, 0));
    assert(!gb_filepick_begin(&p, 0, "/", "TX", 0));
    assert(!gb_filepick_begin(&p, 0, "/", "txt", 0));
    assert(!gb_filepick_begin(&p, 0, "/", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", 0));
    assert(!gb_filepick_begin(&p, 0, "/", 0, 2));
    assert(!calls);
    begin(&p, "/", 0); memcpy(&saved, &p, sizeof(p));
    assert(!gb_filepick_begin(&p, 0, "/EMPTY", 0, 0));
    assert(!memcmp(&saved, &p, sizeof(p)));
    assert(!gb_filepick_take(&p)); cancel(&p);
    for (e = 1; e <= 7; ++e) {
        for (at = 1; at <= 6; ++at) {
            reset(); failure = e; fail_at = at;
            assert(gb_filepick_begin(&p, 0, "/", "TXT", 0)); finish(&p);
            assert(p.state == GB_FILEPICK_ERROR && p.error == e && !p.context && !active());
            before = calls; step(&p); assert(calls == before);
        }
    }
    reset(); begin(&p, "/", 0); fail_at = calls+1;
    gb_filepick_choose(&p, 1); finish(&p);
    assert(p.state == GB_FILEPICK_ERROR && !active());
    reset(); begin(&p, "/", 0); close_fail = 1;
    gb_filepick_cancel(&p); finish(&p);
    assert(p.state == GB_FILEPICK_ERROR && p.context && active() == 1);
    before = calls; step(&p); assert(calls == before); cancel(&p); assert(!active());
    reset();
    assert(gb_filepick_begin(&p, 0, "/", "TXT", 0));
    gb_filepick_cancel(&p); finish(&p); assert(!calls && !active());
    assert(gb_filepick_begin(&p, 0, "/", "TXT", 0)); step(&p);
    gb_filepick_cancel(&p); finish(&p); assert(calls == 2 && !active());
}

static gb_rect_t painted;
static unsigned int draws;
void gb_fill(unsigned char x, unsigned char y, unsigned char w, unsigned char h, unsigned char pen)
{
    (void)pen;
    assert(x > painted.x && y >= painted.y + 14);
    assert(x + w < painted.x + painted.w && y + h < painted.y + painted.h);
    ++draws;
}
void gb_text_semantic(unsigned char x, unsigned char y, const char *text,
                      unsigned char pen, unsigned char paper)
{
    (void)pen; (void)paper;
    assert(x > painted.x && y >= painted.y + 14);
    assert(x + (strlen(text) * 6 + 3)/4 < painted.x + painted.w);
    assert(y + 8 < painted.y + painted.h); ++draws;
}
static void panel(void)
{
    gb_filepick_t p = {0}; unsigned int before;
    reset(); begin(&p, "/", 0);
    painted.x = 4; painted.y = 20; painted.w = 64; painted.h = 148;
    before = calls; gb_filepick_draw(&p, &painted); assert(draws && calls == before);
    assert(gb_filepick_changed(&p)); assert(!gb_filepick_changed(&p));
    gb_filepick_click(&p, &painted, 26, 115); finish(&p); assert(p.offset == 6);
    gb_filepick_click(&p, &painted, 11, 115); finish(&p); assert(p.offset == 0);
    gb_filepick_click(&p, &painted, 11, 50); finish(&p); assert(!strcmp(p.path, "/DIR.EXT"));
    gb_filepick_click(&p, &painted, 38, 115); finish(&p); assert(!strcmp(p.path, "/"));
    gb_filepick_click(&p, &painted, 11, 25); assert(p.state == GB_FILEPICK_READY); /* chrome ignored */
    gb_filepick_click(&p, &painted, 56, 115); finish(&p); assert(p.state == GB_FILEPICK_CANCELLED);
    begin(&p, "/", 1); gb_filepick_draw(&p, &painted);
    p.error = GB_FILEPICK_BAD_NAME; gb_filepick_draw(&p, &painted);
    p.error = GB_FILEPICK_PATH_LIMIT; gb_filepick_draw(&p, &painted);
    p.error = 0; strcpy(p.edit, "SAFE.TXT");
    gb_filepick_click(&p, &painted, 11, 146); finish(&p); assert(p.state == GB_FILEPICK_DONE);
    gb_filepick_draw(&p, &painted); cancel(&p);
    assert(!active());
}

int main(void)
{
    browsing(); naming(); failures(); panel();
    puts("portable chooser: navigation, paging, filters, naming, ownership, faults, bounded work and client-only drawing PASS");
    return 0;
}
