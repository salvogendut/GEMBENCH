/* Unified Notepad integration, based on apps/notepad/main.c.
 * NOT a delivery target yet: the complete link must pass the primary-memory
 * gate before any emulator image is staged. Shell handoff/configuration reload
 * still need portable service contracts; no private mailbox/cache access here.
 */
#include "gbfilepick_ui.h"
#include "gbdocio.h"
#include "gbscrap.h"
#include "editor.h"

enum { EDIT, PICK, CONFIRM, LOAD, SAVE, BAS_REWIND, BAS_WRITE, ERROR, EXIT, OVERWRITE };
enum { NONE, NEW, OPEN, CLOSE };
static np_editor_t editor;
/* Exclusive phase scratch. A complete load is staged before replacing text;
 * clipboard and BASIC chunks borrow it only outside the chooser/load phases.
 * This explicit primary allocation exposes the real memory requirement. It
 * must become owned page storage, not a private address, if the link won't fit.
 */
static union { gb_filepick_t picker; char bytes[NP_MAX]; } scratch;
#define picker scratch.picker
static gb_docio_t job;
static np_bas_t basic;
static gb_fsctx_t document, candidate, retired;
static char name[11], path[48], next_name[11], next_path[48];
static char title[18], line[NP_LINE_MAX];
static unsigned char drive, next_drive, mode, action, menu_request, cooldown;
static unsigned char full, dragging, blink, caret, refresh, title_changed;
static gb_rect_t rect;
static unsigned char wrap, rows;
static const char *problem;
static const unsigned char menus[] = {
    3,10,'F','i','l','e',0,0,0,0,
    18,'E','d','i','t',0,0,0,0,
    26,'V','i','e','w',0,0,0,0
};
static const char *const file_items[] = {"New", "Load", "Save", "Save As"};
static const char *const edit_items[] = {"Select All", "Copy", "Paste"};
static const char *const view_items[] = {"Fullscreen"};

static void geometry(void)
{
    gb_window_rect(&rect);
    wrap = (rect.w - 7) * 2 / 3;
    if (wrap >= NP_LINE_MAX) wrap = NP_LINE_MAX - 1;
    rows = (rect.h - 29) / 10;
}

static unsigned char is_basic(const char *n)
{
    return n[8] == 'B' && n[9] == 'A' && n[10] == 'S';
}

static void update_title(void)
{
    unsigned char i, n = 0;
    for (i = 0; i < 8 && name[i] != ' '; ++i) title[n++] = name[i];
    if (name[8] != ' ') {
        title[n++] = '.';
        for (i = 8; i < 11 && name[i] != ' '; ++i) title[n++] = name[i];
    }
    if (editor.dirty) { title[n++] = ' '; title[n++] = '*'; }
    title[n] = 0;
}

static void repaint(void)
{
    geometry();
    if (title_changed) {
        update_title(); title_changed = 0;
        gb_wm_damage(rect.x, rect.y, rect.w, rect.h);
    } else gb_wm_damage(rect.x+1, rect.y+14, rect.w-2, rect.h-15);
    refresh = 0;
    gb_restore_parent();
}

static void say(unsigned char y, const char *text)
{
    /* Clip to the live client width before crossing the semantic text API. */
    unsigned char n = 0, max = (rect.w-4)*2/3;
    if (max >= NP_LINE_MAX) max = NP_LINE_MAX-1;
    while (n < max && text[n]) { line[n] = text[n]; ++n; }
    line[n] = 0;
    gb_text_semantic(rect.x+2, rect.y+y, line, GB_UI_TEXT, GB_UI_SURFACE);
}

static void draw(void)
{
    unsigned int i, row = 0, c_row, total;
    unsigned char col = 0, n = 0, c_col, screen, ty, ch;
    char one[2];
    geometry();
    if (mode == PICK && rect.w >= 64 && rect.h >= 148) {
        gb_filepick_draw(&picker, &rect); return;
    }
    gb_fill(rect.x+1, rect.y+14, rect.w-2, rect.h-15, GB_UI_SURFACE);
    if (mode != EDIT) {
        if (mode == CONFIRM) {
            say(20,"Save changes?"); say(40,"Save  Discard  Cancel");
            say(54,"S / D / Esc");
        } else if (mode == OVERWRITE) {
            say(20,"Save to selected file?"); say(30,"Existing contents will be replaced");
            say(40,"Save         Cancel"); say(54,"S / Esc");
        } else if (mode == ERROR) {
            say(20,problem); say(40,"Enter / click to return");
        } else if (mode == PICK) say(20,"Enlarge window for file chooser");
        else if (mode == LOAD) say(20,"Loading; old document retained");
        else say(20,"Saving; please wait");
        return;
    }
    /* Same row walk for layout, rendering and hit-testing. Buffer counts and
     * display rows are 16-bit, screen coordinates alone are byte-sized. */
    for (i = 0; i <= editor.len; ++i) {
        ch = i < editor.len ? (unsigned char)editor.text[i] : '\n';
        if (ch == '\n' || i == editor.len) {
            if (row >= editor.first && row-editor.first < rows) {
                line[n] = 0;
                gb_text_semantic(rect.x+5,rect.y+16+(row-editor.first)*10,
                                 line,GB_UI_TEXT,GB_UI_SURFACE);
            }
            n = 0;
        } else if (ch >= 32 && row >= editor.first && row-editor.first < rows)
            line[n++] = (char)ch;
        if (i == editor.len) break;
        if (ch >= 32 && col+1 == wrap) {
            if (row >= editor.first && row-editor.first < rows) {
                line[n] = 0;
                gb_text_semantic(rect.x+5,rect.y+16+(row-editor.first)*10,
                                 line,GB_UI_TEXT,GB_UI_SURFACE);
            }
            n = 0;
        }
        np_advance(ch,wrap,&row,&col);
    }
    total = row;
    if (editor.selected) {
        row = 0; col = 0; one[1] = 0;
        for (i = 0; i < editor.sel_b; ++i) {
            ch = (unsigned char)editor.text[i];
            if (i >= editor.sel_a && ch >= 32 && row >= editor.first &&
                row-editor.first < rows) {
                one[0] = (char)ch;
                gb_text_semantic(rect.x+5+col*3/2,rect.y+16+(row-editor.first)*10,
                                 one,GB_UI_SURFACE,GB_UI_TEXT);
            }
            np_advance(ch,wrap,&row,&col);
        }
    }
    gb_fill(rect.x+1,rect.y+16,3,rows*10,GB_UI_SURFACE);
    gb_text_semantic(rect.x+2,rect.y+16,GLYPH_TRI_UP,GB_UI_TEXT,GB_UI_SURFACE);
    gb_text_semantic(rect.x+2,rect.y+16+rows*10-8,GLYPH_TRI_DOWN,GB_UI_TEXT,GB_UI_SURFACE);
    ty = rect.y+24;
    if (editor.first) ty = editor.first+rows > total ?
        rect.y+16+rows*10-16 : rect.y+16+rows*5-4;
    gb_fill(rect.x+1,ty,3,8,GB_UI_ACCENT);
    say(rect.h-11,"Click text; Ctrl-Q=quit");
    np_position(&editor,editor.cur,wrap,&c_row,&c_col);
    if (caret && c_row >= editor.first && c_row-editor.first < rows) {
        screen = (unsigned char)(c_row-editor.first);
        gb_fill(rect.x+5+c_col*3/2,rect.y+24+screen*10,2,2,GB_UI_ACCENT);
    }
}

static void fail(const char *message)
{
    if (mode == SAVE || mode == BAS_REWIND || mode == BAS_WRITE) {
        editor.dirty = 1; title_changed = 1;
    }
    problem = message; mode = ERROR; action = NONE; refresh = 1;
}

/* One release per frame. A close error retains ownership for an explicit retry;
 * stale/foreign handles are discarded without trying to free another owner. */
static unsigned char release(gb_fsctx_t *handle)
{
    unsigned char result;
    if (!*handle) return 1;
    result = gb_fsctx_close(*handle);
    if (!result || result == GB_FSCTX_ERR_STALE || result == GB_FSCTX_ERR_OWNER) {
        *handle = 0; return 1;
    }
    fail("Close failed; Enter retries");
    return 0;
}

static void choose(unsigned char saving)
{
    memset(&scratch,0,sizeof(gb_filepick_t));
    if (!gb_filepick_begin(&picker,drive,path,"TXTBASCFG",saving)) {
        fail("Cannot start file chooser"); return;
    }
    mode = PICK; refresh = 1;
    geometry();
    if (rect.w < 64 || rect.h < 148) {
        gb_wm_setpos(2,14);
        gb_wm_setsize(rect.w < 64 ? 64 : rect.w,rect.h < 148 ? 148 : rect.h);
    }
}

static void perform(void)
{
    unsigned char requested = action;
    action = NONE;
    if (requested == OPEN) choose(GB_FILEPICK_OPEN);
    else if (requested == CLOSE) mode = EXIT;
    else if (requested == NEW) {
        retired = document; document = 0;
        np_reset(&editor); memcpy(name,"UNTITLEDTXT",11);
        mode = EDIT; refresh = title_changed = 1;
    }
}

static void request(unsigned char requested)
{
    if (mode != EDIT || retired || candidate) return;
    action = requested;
    dragging = 0;
    if (editor.dirty) { mode = CONFIRM; refresh = 1; }
    else perform();
}

static void start_save(void)
{
    gb_fsctx_t target = candidate ? candidate : document;
    memset(&job,0,sizeof(job));
    if (is_basic(candidate ? next_name : name)) {
        basic.offset = 0; basic.phase = 0; mode = BAS_REWIND;
    } else {
        gb_docio_save(&job,target,editor.text,editor.len); mode = SAVE;
    }
    refresh = 1;
}

static void save(unsigned char as)
{
    if (as || !document) choose(GB_FILEPICK_SAVE);
    else start_save();
}

static void confirm(unsigned char choice)
{
    if (mode == OVERWRITE) {
        if (choice == 's' || choice == 'S') start_save();
        else if (choice == 27) {
            retired = candidate; candidate = 0; action = NONE; mode = EDIT; refresh = 1;
        }
        return;
    }
    if (choice == 's' || choice == 'S') save(0);
    else if (choice == 'd' || choice == 'D') perform();
    else if (choice == 27) { action = NONE; mode = EDIT; refresh = 1; }
}

static void promote(void)
{
    if (candidate) {
        retired = document; document = candidate; candidate = 0;
        memcpy(name,next_name,11); strcpy(path,next_path); drive = next_drive;
    }
    editor.dirty = 0; mode = EDIT; refresh = title_changed = 1;
}

static void saved(void)
{
    promote();
    /* Cleanup the old context before a deferred New/Load/Close can run. */
}

static void storage(void)
{
    unsigned int amount;
    unsigned char result;
    if (retired) { release(&retired); return; }
    if (mode == EXIT) {
        if (candidate) { release(&candidate); return; }
        if (document) { release(&document); return; }
        gb_wm_close(); return;
    }
    if (mode == PICK) {
        gb_filepick_step(&picker);
        if (picker.state == GB_FILEPICK_DONE) {
            memcpy(next_name,picker.name,11); strcpy(next_path,picker.path);
            next_drive = picker.drive; result = picker.mode;
            candidate = gb_filepick_take(&picker);
            if (result == GB_FILEPICK_SAVE) { mode = OVERWRITE; refresh = 1; }
            else {
                memset(&job,0,sizeof(job));
                gb_docio_load(&job,candidate,scratch.bytes,NP_MAX);
                mode = LOAD; refresh = 1;
            }
        } else if (picker.state == GB_FILEPICK_CANCELLED) {
            action = NONE; mode = EDIT; refresh = 1;
        } else if (gb_filepick_changed(&picker)) refresh = 1;
    } else if (mode == LOAD || mode == SAVE) {
        gb_docio_step(&job);
        if (job.state == GB_DOCIO_DONE) {
            if (mode == LOAD) {
                np_loaded(&editor,scratch.bytes,job.transferred,is_basic(next_name));
                promote();
            } else saved();
        } else if (job.state == GB_DOCIO_ERROR) {
            retired = candidate; candidate = 0;
            fail(mode == LOAD ? "Load failed; old text retained" :
                                "Save failed; disk may be partial");
        }
    } else if (mode == BAS_REWIND) {
        result = gb_fsctx_rewind(candidate ? candidate : document);
        if (result) { retired = candidate; candidate = 0; fail("Save rewind failed"); }
        else mode = BAS_WRITE;
    } else if (mode == BAS_WRITE) {
        amount = np_bas_chunk(&editor,&basic,scratch.bytes,512);
        if (amount) {
            result = gb_fsctx_write(candidate ? candidate : document,scratch.bytes,amount);
            if (result) { retired = candidate; candidate = 0; fail("Save failed; disk may be partial"); }
        }
        if (mode == BAS_WRITE && basic.phase == 4) saved();
    } else if (mode == EDIT && action) perform();
}

static void copy(void)
{
    if (!editor.selected) return;
    (void)gb_scrap_set(GB_SCRAP_TEXT,editor.text+editor.sel_a,
                      editor.sel_b-editor.sel_a);
}

static void paste(void)
{
    gb_scrap_info_t info;
    unsigned int count;
    unsigned char result;
    if (gb_scrap_query(&info) || !info.length) return;
    if (info.type != GB_SCRAP_TEXT && info.type != GB_SCRAP_UNTYPED) return;
    result = gb_scrap_get(info.type,scratch.bytes,GB_SCRAP_CAPACITY,&count);
    if (result == GB_SCRAP_OK) np_replace(&editor,scratch.bytes,count);
}

static void menu(void)
{
    unsigned char requested = menu_request, item;
    menu_request = 0;
    item = gb_universal_popup(requested == 1 ? 10 : requested == 2 ? 18 : 26,
        requested == 1 ? file_items : requested == 2 ? edit_items : view_items,
        requested == 3 ? 1 : requested == 2 ? 3 : 4);
    cooldown = 4;
    if (item == 255) return;
    if (requested == 1) {
        if (item == 0) request(NEW);
        else if (item == 1) request(OPEN);
        else { action = NONE; save(item == 3); }
    } else if (requested == 2) {
        if (!item) np_all(&editor);
        else if (item == 2) paste();
        else copy();
        np_follow(&editor,wrap,rows); refresh = title_changed = 1;
    } else {
        full = !full;
        gb_wm_setpos(full ? 0 : 2,full ? 8 : 14);
        gb_wm_setsize(full ? gb_screen_columns() : 66,
                      full ? gb_screen_lines()-8 : 158);
        geometry(); np_follow(&editor,wrap,rows); refresh = 1;
    }
}

static unsigned int pointer_index(void)
{
    unsigned char x = gb_mx(), y = gb_my(), col = 0;
    unsigned int row = editor.first;
    if (x > rect.x+5) col = (x-rect.x-5)*2/3;
    if (col >= wrap) col = wrap-1;
    if (y > rect.y+16) row += (y-rect.y-16)/10;
    return np_index(&editor,row,col,wrap);
}

static void click(void)
{
    unsigned char x = gb_mx(), y = gb_my();
    unsigned int total, limit;
    unsigned char col;
    cooldown = 4;
    if (mode == PICK) { gb_filepick_click(&picker,&rect,x,y); return; }
    if (mode == ERROR) { mode = EDIT; refresh = 1; return; }
    if (mode == OVERWRITE) {
        if (y >= rect.y+40 && y < rect.y+50) confirm(x < rect.x+14 ? 's' : 27);
        return;
    }
    if (mode == CONFIRM) {
        if (y >= rect.y+40 && y < rect.y+50) {
            if (x < rect.x+10) confirm('s');
            else if (x < rect.x+24) confirm('d');
            else confirm(27);
        }
        return;
    }
    if (mode != EDIT || y < rect.y+16 || y >= rect.y+16+rows*10) return;
    if (x < rect.x+4) {
        np_position(&editor,editor.len,wrap,&total,&col);
        limit = total >= rows ? total-rows+1 : 0;
        if (y < rect.y+16+rows*5) editor.first = editor.first > 3 ? editor.first-3 : 0;
        else editor.first += 3;
        if (editor.first > limit) editor.first = limit;
    } else {
        editor.anchor = pointer_index(); np_select(&editor,editor.anchor);
        dragging = 1; caret = 1; blink = 0;
    }
    refresh = 1;
}

static void close_request(void)
{
    if (mode == PICK) gb_filepick_cancel(&picker);
    else if (mode == CONFIRM || mode == OVERWRITE) confirm(27);
    else if (mode == LOAD) {
        gb_docio_cancel(&job); retired = candidate; candidate = 0;
        mode = EDIT; refresh = 1;
    } else if (mode == ERROR) { mode = EDIT; refresh = 1; }
    else if (mode == EDIT) request(CLOSE);
    /* Saving is bounded, but closing must not abandon a partially-written
     * document as clean. Wait for success/error before another close request. */
}

static void frame(void)
{
    unsigned char n, key, changed = 0, was_dirty = editor.dirty, had_selection = editor.selected;
    unsigned int row, old_row, old_first = editor.first;
    unsigned char col, old_col;
    geometry();
    /* Explicit acknowledgement is required after a release failure. */
    if (mode != ERROR) storage();
    if (mode == EXIT) return;
    if (refresh || title_changed) { repaint(); return; }
    if (mode == EDIT && (retired || candidate || action)) return;
    if (menu_request && mode == EDIT) { menu(); if (refresh) repaint(); return; }
    if (dragging) {
        if (!(gb_flags() & GB_FIRE)) dragging = 0;
        else if (editor.cur != pointer_index()) {
            np_select(&editor,pointer_index()); np_follow(&editor,wrap,rows);
            refresh = 1;
        }
    }
    if (gb_flags() & GB_FIRE) cooldown = 4;
    if (cooldown) { --cooldown; gb_getkey(); gb_getkey(); }
    else {
        np_position(&editor,editor.cur,wrap,&old_row,&old_col);
        for (n = 0; n < 2; ++n) {
            key = gb_getkey(); if (!key) break;
            if (mode == PICK) gb_filepick_key(&picker,key);
            else if (mode == CONFIRM || mode == OVERWRITE) { confirm(key); break; }
            else if (mode == ERROR) {
                if (key == 13 || key == 27) { mode = EDIT; refresh = 1; } break;
            } else if (mode == EDIT) {
                if (key == 17) { close_request(); break; }
                changed |= np_key(&editor,key);
            }
        }
        if (changed) {
            np_follow(&editor,wrap,rows); caret = 1; blink = 0;
            if (was_dirty != editor.dirty) title_changed = 1;
            np_position(&editor,editor.cur,wrap,&row,&col);
            if (row > old_row) row = old_row;
            if (!had_selection && !title_changed && !refresh && old_first == editor.first &&
                row >= editor.first && row-editor.first < rows) {
                /* Insertion can reflow every following row. Damage that suffix,
                 * not just the caret line, and leave chrome/status untouched. */
                gb_wm_damage(rect.x+4,rect.y+16+(row-editor.first)*10,rect.w-5,
                              (rows-(row-editor.first))*10);
                gb_restore_parent(); return;
            }
            refresh = 1;
        }
    }
    if (refresh || title_changed) { repaint(); return; }
    if (mode == EDIT && ++blink >= 16) {
        blink = 0; caret = !caret;
        np_position(&editor,editor.cur,wrap,&row,&col);
        if (row >= editor.first && row-editor.first < rows) {
            gb_wm_damage(rect.x+5+col*3/2,rect.y+24+(row-editor.first)*10,2,2);
            gb_restore_parent();
        }
    }
}

static void proc(void)
{
    gb_msg_t message;
    gb_message_read(&message); geometry();
    switch (message.type) {
    case GB_MSG_DRAW: draw(); break;
    case GB_MSG_FRAME: frame(); break;
    case GB_MSG_CLICK: click(); break;
    case GB_MSG_CLOSE: close_request(); break;
    case GB_MSG_SIZED:
    case GB_MSG_MAXIMIZED: np_follow(&editor,wrap,rows); refresh = 1; break;
    case GB_MSG_MENU:
        if (gb_universal_popup_active()) gb_universal_popup_close();
        else if (mode == EDIT && !candidate && !retired)
            menu_request = message.p0 >= 26 ? 3 : message.p0 >= 18 ? 2 : 1;
        break;
    }
}

static const gb_mwin_kind_t window = {
    {2,14,66,158,30,72,proc,title,0},GB_WK_STANDARD
};
void main(void)
{
    if (!gb_universal_ready()) return;
    np_reset(&editor); memcpy(name,"UNTITLEDTXT",11); strcpy(path,"/");
    drive = gb_boot_drive_current(); caret = 1;
    update_title(); gb_wm_managed_kind(&window); gb_menu(menus);
    refresh = title_changed = 1; repaint();
}
