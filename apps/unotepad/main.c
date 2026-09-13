/* Primary UI/storage controller. Editor and transactional staging live behind
 * the same copied computation protocol on every receiving platform. */
#include "gbfilepick_ui.h"
#include "gbdocio.h"
#include "gbscrap.h"
#include <string.h>
#include "client.h"

enum { EDIT, PICK, CONFIRM, LOAD, SAVE, BAS_REWIND, BAS_WRITE, ERROR, EXIT, OVERWRITE, MENU };
enum { NONE, NEW, OPEN, CLOSE };
/* No whole-document primary buffer. Exclusive chooser/clipboard/I/O scratch. */
union { gb_filepick_t picker; char bytes[768]; } scratch;
#define picker scratch.picker
unsigned char *gb_universal_popup_buffer(void) {return (unsigned char *)scratch.bytes;}
static gb_docio_t job;
static gb_fsctx_t document, candidate, retired;
static char name[11], path[48];
static gb_fsctx_identity_t next;
#define next_name next.name
#define next_path next.path
#define next_drive next.drive
static char title[18], line[NP_LINE_MAX];
unsigned char mode; /* named for read-only runtime observations */
static unsigned char drive, action, menu_request, cooldown;
static unsigned char full, dragging, blink, caret, refresh, title_changed;
static gb_rect_t rect;
static unsigned char drag_x,drag_y;
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

/* GB_PARAMS_TEXT transfers at most 48 glyphs. An even-sized first run keeps
 * the second run aligned to the portable four-pixel coordinate grid. */
static void text_run(unsigned char x,unsigned char y,const char *s,
                     unsigned char pen,unsigned char paper)
{
    gb_text_semantic(x,y,s,pen,paper);
    if(strlen(s)>48)gb_text_semantic(x+72,y,s+48,pen,paper);
}

static void say(unsigned char y, const char *text)
{
    /* Clip to the live client width before crossing the semantic text API. */
    unsigned char n = 0, max = (rect.w-4)*2/3;
    if (max >= NP_LINE_MAX) max = NP_LINE_MAX-1;
    while (n < max && text[n]) { line[n] = text[n]; ++n; }
    line[n] = 0;
    text_run(rect.x+2, rect.y+y, line, GB_UI_TEXT, GB_UI_SURFACE);
}

static void draw(void)
{
    unsigned char i,n,screen=0,ty,len,a,b;
    unsigned char *r;
    geometry();
    if (mode == PICK && rect.w >= 64 && rect.h >= 148) {
        gb_filepick_draw(&picker, &rect); return;
    }
    gb_fill(rect.x+1, rect.y+14, rect.w-2, rect.h-15, GB_UI_SURFACE);
    if (mode != EDIT && mode != MENU) {
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
    if(!model_call(NP_VIEW_BEGIN))return;
    while(screen<rows) {
        if(!model_call(NP_VIEW_ROWS))return;
        n=(unsigned char)np_word(packet+2);if(!n)break;
        for(i=0;i<n;++i,++screen) {
            r=packet+NP_DATA+i*NP_ROW_SIZE;len=r[0];a=r[1];b=r[2];
            memcpy(line,r+4,len);line[len]=0;
            text_run(rect.x+5,rect.y+16+screen*10,line,GB_UI_TEXT,GB_UI_SURFACE);
            if(a!=255 && b>a) {
                line[b]=0;
                text_run(rect.x+5+a*3/2,rect.y+16+screen*10,line+a,GB_UI_SURFACE,GB_UI_TEXT);
            }
        }
    }
    gb_fill(rect.x+1,rect.y+16,3,rows*10,GB_UI_SURFACE);
    gb_text_semantic(rect.x+2,rect.y+16,GLYPH_TRI_UP,GB_UI_TEXT,GB_UI_SURFACE);
    gb_text_semantic(rect.x+2,rect.y+16+rows*10-8,GLYPH_TRI_DOWN,GB_UI_TEXT,GB_UI_SURFACE);
    ty = rect.y+24;
    if (editor.first) ty = editor.first+rows > editor.total ?
        rect.y+16+rows*10-16 : rect.y+16+rows*5-4;
    gb_fill(rect.x+1,ty,3,8,GB_UI_ACCENT);
    say(rect.h-11,"Click text; Ctrl-Q=quit");
    if (caret && editor.c_row >= editor.first && editor.c_row-editor.first < rows) {
        screen = (unsigned char)(editor.c_row-editor.first);
        gb_fill(rect.x+5+editor.c_col*3/2,rect.y+24+screen*10,2,2,GB_UI_ACCENT);
    }
}

static void fail(const char *message)
{
    if (mode == SAVE || mode == BAS_REWIND || mode == BAS_WRITE) {
        model_call(NP_DIRTY);title_changed = 1;
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
        model_call(NP_RESET); memcpy(name,"UNTITLEDTXT",11);
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
        model_call(NP_BAS_BEGIN);mode = BAS_REWIND;
    } else {
        gb_docio_save_chunks(&job,target,editor.len); mode = SAVE;
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
    model_call(NP_SAVED);mode = EDIT; refresh = title_changed = 1;
}

static void saved(void)
{
    promote();
    /* Cleanup the old context before a deferred New/Load/Close can run. */
}
static void start_load(void)
{
    memset(&job,0,sizeof(job));
    model_call(NP_STAGE_BEGIN);
    gb_docio_load_chunks(&job,candidate,NP_MAX);mode=LOAD;refresh=1;
}

static void storage(void)
{
    unsigned int amount,before;
    unsigned char result,complete;
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
                start_load();
            }
        } else if (picker.state == GB_FILEPICK_CANCELLED) {
            action = NONE; mode = EDIT; refresh = 1;
        } else if (gb_filepick_changed(&picker)) refresh = 1;
    } else if (mode == LOAD || mode == SAVE) {
        before=job.transferred;
        if(mode==SAVE && job.state==GB_DOCIO_SAVE) {
            np_put(packet+2,before);np_put(packet+4,NP_CHUNK);
            if(!model_call(NP_EXPORT)) { fail("Document read failed");return; }
            memcpy(scratch.bytes,packet+NP_DATA,np_word(packet+2));
        }
        gb_docio_chunk(&job,scratch.bytes,NP_CHUNK);
        if(mode==LOAD && job.transferred>before &&
           !model_stage(scratch.bytes,job.transferred-before,before)) {
            gb_docio_cancel(&job);retired=candidate;candidate=0;
            fail("Staging failed; old text retained");return;
        }
        if (job.state == GB_DOCIO_DONE) {
            if (mode == LOAD) {
                packet[6]=is_basic(next_name);
                if(!model_call(NP_STAGE_LOAD)) {fail("Load commit failed");return;}
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
        if(!model_call(NP_BAS_READ)) {fail("Document read failed");return;}
        amount=np_word(packet+2);
        complete=packet[6];
        if (amount) {
            result = gb_fsctx_write(candidate ? candidate : document,(char *)packet+NP_DATA,amount);
            if (result) { retired = candidate; candidate = 0; fail("Save failed; disk may be partial"); }
        }
        if (mode == BAS_WRITE && complete) saved();
    } else if (mode == EDIT && action) perform();
}

static void copy(void)
{
    unsigned int at,count,n,done=0;
    if (!editor.selected) return;
    at=editor.sel_a;count=editor.sel_b-at;if(count>GB_SCRAP_CAPACITY)count=GB_SCRAP_CAPACITY;
    while(done<count) {
        n=count-done;if(n>NP_CHUNK)n=NP_CHUNK;
        np_put(packet+2,at+done);np_put(packet+4,n);
        if(!model_call(NP_EXPORT))return;
        memcpy(scratch.bytes+done,packet+NP_DATA,n);done+=n;
    }
    (void)gb_scrap_set(GB_SCRAP_TEXT,scratch.bytes,count);
}

static void paste(void)
{
    gb_scrap_info_t info;
    unsigned int count;
    unsigned char result;
    if (gb_scrap_query(&info) || !info.length) return;
    if (info.type != GB_SCRAP_TEXT && info.type != GB_SCRAP_UNTYPED) return;
    result = gb_scrap_get(info.type,scratch.bytes,GB_SCRAP_CAPACITY,&count);
    if (result == GB_SCRAP_OK && model_call(NP_STAGE_BEGIN) && model_stage(scratch.bytes,count,0))
        model_call(NP_STAGE_PASTE);
}

static void menu(void)
{
    unsigned char requested = menu_request, item;
    menu_request = 0;
    mode=MENU; /* borrowed scratch is exclusive: no chooser/file/clipboard work */
    item = gb_universal_popup(requested == 1 ? 10 : requested == 2 ? 18 : 26,
        requested == 1 ? file_items : requested == 2 ? edit_items : view_items,
        requested == 3 ? 1 : requested == 2 ? 3 : 4);
    mode=EDIT;
    cooldown = 4;
    if (item == 255) return;
    if (requested == 1) {
        if (item == 0) request(NEW);
        else if (item == 1) request(OPEN);
        else { action = NONE; save(item == 3); }
    } else if (requested == 2) {
        if (!item) model_call(NP_ALL);
        else if (item == 2) paste();
        else copy();
        model_call(NP_FOLLOW);refresh = title_changed = 1;
    } else {
        full = !full;
        gb_wm_setpos(full ? 0 : 2,full ? 8 : 14);
        gb_wm_setsize(full ? gb_screen_columns() : 66,
                      full ? gb_screen_lines()-8 : 158);
        geometry();model_call(NP_FOLLOW);refresh = 1;
    }
}

static void pointer_select(unsigned char begin)
{
    unsigned char x = gb_mx(), y = gb_my(), col = 0;
    unsigned int row = editor.first;
    if (x > rect.x+5) col = (x-rect.x-5)*2/3;
    if (col >= wrap) col = wrap-1;
    if (y > rect.y+16) row += (y-rect.y-16)/10;
    np_put(packet+2,row);np_put(packet+4,col);packet[6]=begin;
    model_call(NP_HIT);drag_x=x;drag_y=y;
}

static void click(void)
{
    unsigned char x = gb_mx(), y = gb_my();
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
        packet[6]=y < rect.y+16+rows*5;model_call(NP_SCROLL);
    } else {
        pointer_select(1);
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
    geometry();
    if(mode==MENU)return;
    if(model_fault && mode!=ERROR) {fail("Editor service failed");return;}
    /* Explicit acknowledgement is required after a release failure. */
    if (mode != ERROR) storage();
    if (mode == EXIT) return;
    if (refresh || title_changed) { repaint(); return; }
    if (mode == EDIT && (retired || candidate || action)) return;
    if (menu_request && mode == EDIT) { menu(); if (refresh) repaint(); return; }
    if (dragging) {
        if (!(gb_flags() & GB_FIRE)) dragging = 0;
        else if (drag_x!=gb_mx() || drag_y!=gb_my()) {
            pointer_select(0);
            refresh = 1;
        }
    }
    if (gb_flags() & GB_FIRE) cooldown = 4;
    /* Pointer arrows can return zero while more keys remain in the BIOS queue.
     * Drain a bounded whole queue, not just two slots or until the first zero:
     * otherwise the click's Space can arrive later as an unintended edit. */
    if (cooldown) { --cooldown;for(n=0;n<64;++n)gb_getkey(); }
    else {
        old_row=editor.c_row;
        for (n = 0; n < 2; ++n) {
            key = gb_getkey(); if (!key) break;
            if (mode == PICK) gb_filepick_key(&picker,key);
            else if (mode == CONFIRM || mode == OVERWRITE) { confirm(key); break; }
            else if (mode == ERROR) {
                if (key == 13 || key == 27) { mode = EDIT; refresh = 1; } break;
            } else if (mode == EDIT) {
                if (key == 17) { close_request(); break; }
                packet[6]=key;
                if(model_call(NP_KEY))changed|=(unsigned char)np_word(packet+2);
            }
        }
        if (changed) {
            caret = 1; blink = 0;
            if (was_dirty != editor.dirty) title_changed = 1;
            row=editor.c_row;
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
        row=editor.c_row;
        if (row >= editor.first && row-editor.first < rows) {
            gb_wm_damage(rect.x+5+editor.c_col*3/2,rect.y+24+(row-editor.first)*10,2,2);
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
    case GB_MSG_MAXIMIZED: model_call(NP_FOLLOW);refresh = 1; break;
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
    if (!gb_universal_ready() || gb_universal_sysinfo()->filesystem_api_version < GB_FSCTX_HANDOFF_API_VERSION) return;
    wrap=39;rows=12;
    if(!model_call(NP_RESET))return;
    memcpy(name,"UNTITLEDTXT",11); strcpy(path,"/");
    drive = gb_boot_drive_current(); caret = 1;cooldown=4;
    /* Adopt while startup belongs to the bound launch owner. Copy identity
     * before model/storage reuse transfer scratch; publish only after load. */
    candidate=gb_fsctx_adopt_launch();
    if(candidate) {
        if(gb_fsctx_identity(candidate,&next)) {
            retired=candidate;candidate=0;fail("Cannot open document");
        } else {
            start_load();
        }
    } else if(gb_fsctx_status()!=GB_FSCTX_ERR_STALE) fail("Cannot open document");
    update_title(); gb_wm_managed_kind(&window); gb_menu(menus);
    refresh = title_changed = 1; repaint();
}
