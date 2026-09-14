#include "gbfilepick.h"
#include <string.h>

static unsigned char name_char(unsigned char c)
{
    return (unsigned char)((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
        (c && strchr("!#$%&'()-@^_`{}~", c) != 0));
}

static void scan(gb_filepick_t *p)
{
    p->scanned = 0;
    p->count = p->more = p->error = 0;
    p->first = p->changed = 1;
    p->state = GB_FILEPICK_SCAN;
}

static void end(gb_filepick_t *p, unsigned char state)
{
    p->ending = state;
    p->state = p->context ? GB_FILEPICK_CLOSING : state;
    p->changed = 1;
}

static void fail(gb_filepick_t *p, unsigned char error)
{
    p->error = error;
    end(p, GB_FILEPICK_ERROR);
}

unsigned char gb_filepick_begin(gb_filepick_t *p, unsigned char drive,
                                const char *path, const char *extensions,
                                unsigned char mode)
{
    unsigned char i;
    if (!p || p->context || (p->state && p->state != GB_FILEPICK_DONE &&
        p->state != GB_FILEPICK_CANCELLED && p->state != GB_FILEPICK_ERROR) ||
        !path || path[0] != '/' || mode > GB_FILEPICK_SAVE) return 0;
    for (i = 0; i < 48 && path[i]; ++i) { }
    if (i == 48 || (i > 1 && path[i - 1] == '/')) return 0;
    if (extensions) {
        for (i = 0; i < 22 && extensions[i]; ++i)
            if (!((extensions[i] >= 'A' && extensions[i] <= 'Z') ||
                  (extensions[i] >= '0' && extensions[i] <= '9'))) return 0;
        if (i > 21 || i % 3) return 0;
    }
    /* Copy before clearing other state: path may be this object's last path. */
    memmove(p->path, path, strlen(path) + 1);
    p->extensions = extensions;
    p->mode = mode; p->drive = drive;
    p->offset = p->scanned = 0;
    p->count = p->more = p->error = p->ending = 0;
    p->name[0] = p->edit[0] = 0;
    p->state = GB_FILEPICK_ALLOC;
    p->changed = 1;
    return 1;
}

static unsigned char shown(const gb_filepick_t *p, const unsigned char *entry)
{
    const char *ext = p->extensions;
    /* Dot entries are represented by our Up action. Volume labels are not files. */
    if (!entry[0] || entry[0] == '.' || entry[0] == ' ' || (entry[11] & 8)) return 0;
    if ((entry[11] & GB_FSCTX_ATTR_DIRECTORY) || !ext || !*ext) return 1;
    while (*ext) {
        if (!memcmp(entry + 8, ext, 3)) return 1;
        ext += 3;
    }
    return 0;
}

unsigned char gb_filepick_step(gb_filepick_t *p)
{
    unsigned char status = 0, n, i;
    const unsigned char *entry;
    if (!p) return GB_FILEPICK_IDLE;
    switch (p->state) {
    case GB_FILEPICK_ALLOC:
        p->context = gb_fsctx_open(p->drive);
        if (!p->context) { fail(p, gb_fsctx_status()); break; }
        p->state = GB_FILEPICK_PATH;
        break;
    case GB_FILEPICK_PATH:
        status = gb_fsctx_set_path(p->context, p->path);
        if (!status) p->state = GB_FILEPICK_ACTIVATE;
        break;
    case GB_FILEPICK_ACTIVATE:
        status = gb_fsctx_activate(p->context);
        if (!status) scan(p);
        break;
    case GB_FILEPICK_SCAN:
        n = gb_fsctx_dir_batch(p->context, p->first);
        p->first = 0;
        status = gb_fsctx_status();
        if (status) break;
        if (n > GB_FSCTX_DIRECTORY_BATCH) { status = GB_FSCTX_ERR_BADARG; break; }
        /* Packed wire records are 16 bytes even with a host's wider long/int. */
        entry = (const unsigned char *)gb_fsctx_batch_entries();
        for (i = 0; i < n; ++i, entry += 16) {
            if (!shown(p, entry)) continue;
            if (p->scanned == 65535u) { status = GB_FILEPICK_DIRECTORY_LIMIT; break; }
            if (p->scanned++ < p->offset) continue;
            if (p->count == GB_FILEPICK_ROWS) {
                p->more = 1;
                p->state = GB_FILEPICK_READY;
                break;
            }
            memcpy(p->rows[p->count].name, entry, 11);
            p->rows[p->count++].directory = (entry[11] & GB_FSCTX_ATTR_DIRECTORY) != 0;
        }
        if (!n) p->state = GB_FILEPICK_READY;
        /* Partial batches are not EOF; the next frame asks for more. */
        if (p->state == GB_FILEPICK_READY) p->changed = 1;
        break;
    case GB_FILEPICK_NAME:
        status = gb_fsctx_set_name(p->context, p->name);
        if (!status) { p->state = GB_FILEPICK_DONE; p->changed = 1; }
        break;
    case GB_FILEPICK_CLOSING:
        status = gb_fsctx_close(p->context);
        if (!status || status == GB_FSCTX_ERR_STALE || status == GB_FSCTX_ERR_OWNER)
            p->context = 0;
        p->state = status ? GB_FILEPICK_ERROR : p->ending;
        if (status && !p->error) p->error = status;
        p->changed = 1;
        return p->state;
    default:
        return p->state;
    }
    if (status) fail(p, status);
    return p->state;
}

void gb_filepick_cancel(gb_filepick_t *p)
{
    if (p) end(p, GB_FILEPICK_CANCELLED);
}

gb_fsctx_t gb_filepick_take(gb_filepick_t *p)
{
    gb_fsctx_t result;
    if (!p || p->state != GB_FILEPICK_DONE) return 0;
    result = p->context;
    p->context = 0;
    return result;
}

unsigned char gb_filepick_changed(gb_filepick_t *p)
{
    unsigned char changed;
    if (!p) return 0;
    changed = p->changed; p->changed = 0;
    return changed;
}

void gb_filepick_page(gb_filepick_t *p, unsigned char next)
{
    if (!p || p->state != GB_FILEPICK_READY) return;
    if (next) {
        if (!p->more || p->offset > 65535u - GB_FILEPICK_ROWS) return;
        p->offset += GB_FILEPICK_ROWS;
    } else {
        if (!p->offset) return;
        p->offset -= GB_FILEPICK_ROWS;
    }
    scan(p);
}

static void path_changed(gb_filepick_t *p)
{
    p->offset = 0;
    p->count = p->more = p->error = 0;
    p->state = GB_FILEPICK_PATH;
    p->changed = 1;
}

void gb_filepick_up(gb_filepick_t *p)
{
    unsigned char i;
    if (!p || p->state != GB_FILEPICK_READY) return;
    i = (unsigned char)strlen(p->path);
    if (i <= 1) return;
    while (i > 1 && p->path[i - 1] != '/') --i;
    if (i > 1) --i;
    p->path[i] = 0;
    path_changed(p);
}

void gb_filepick_label(char *out, const gb_filepick_row_t *row)
{
    unsigned char i, j = 0;
    for (i = 0; i < 8 && row->name[i] != ' '; ++i) out[j++] = row->name[i];
    if (row->name[8] != ' ') {
        out[j++] = '.';
        for (i = 8; i < 11 && row->name[i] != ' '; ++i) out[j++] = row->name[i];
    }
    if (row->directory) out[j++] = '/';
    out[j] = 0;
}

void gb_filepick_choose(gb_filepick_t *p, unsigned char row)
{
    unsigned char i, n;
    char name[14];
    if (!p || p->state != GB_FILEPICK_READY || row >= p->count) return;
    gb_filepick_label(name, p->rows + row);
    p->changed = 1; p->error = 0;
    if (p->rows[row].directory) {
        i = (unsigned char)strlen(p->path);
        n = (unsigned char)strlen(name) - 1; /* omit trailing slash */
        if ((unsigned int)i + (i > 1) + n > GB_FSCTX_PATH_MAX) {
            p->error = GB_FILEPICK_PATH_LIMIT;
            return;
        }
        if (i > 1) p->path[i++] = '/';
        memcpy(p->path + i, name, n);
        p->path[i + n] = 0;
        path_changed(p);
    } else if (p->mode == GB_FILEPICK_SAVE) {
        strcpy(p->edit, name);
    } else {
        memcpy(p->name, p->rows[row].name, 11);
        p->state = GB_FILEPICK_NAME;
    }
}

void gb_filepick_submit(gb_filepick_t *p)
{
    unsigned char i, base = 0, ext = 0, dot = 0, c;
    char name[11];
    if (!p || p->state != GB_FILEPICK_READY || p->mode != GB_FILEPICK_SAVE) return;
    if (p->error == GB_FILEPICK_BAD_NAME) return; /* rejected key needs correction */
    memset(name, ' ', 11);
    for (i = 0; i < 13 && (c = (unsigned char)p->edit[i]) != 0; ++i) {
        if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
        if (c == '.' && base && !dot) { dot = 1; continue; }
        if (!name_char(c) || (!dot && base == 8) || (dot && ext == 3)) break;
        if (dot) name[8 + ext++] = c;
        else name[base++] = c;
    }
    p->changed = 1;
    if (i == 13 || p->edit[i] || !base || (dot && !ext)) {
        p->error = GB_FILEPICK_BAD_NAME;
        return;
    }
    memcpy(p->name, name, 11);
    p->error = 0;
    p->state = GB_FILEPICK_NAME;
}

void gb_filepick_key(gb_filepick_t *p, unsigned char key)
{
    unsigned char n;
    if (!p) return;
    if (key == 27) { gb_filepick_cancel(p); return; }
    if (p->state != GB_FILEPICK_READY || p->mode != GB_FILEPICK_SAVE) return;
    if (key == 13) { gb_filepick_submit(p); return; }
    n = (unsigned char)strlen(p->edit);
    if (key == 8 || key == 127) { if (n) p->edit[--n] = 0; }
    else {
        if (key >= 'a' && key <= 'z') key -= 'a' - 'A';
        if ((!name_char(key) && key != '.') || n == 12) {
            p->error = GB_FILEPICK_BAD_NAME; p->changed = 1; return;
        }
        p->edit[n++] = key; p->edit[n] = 0;
    }
    p->error = 0; p->changed = 1;
}
