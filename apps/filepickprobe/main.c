/* Diagnostic for the real portable chooser + bounded document-I/O bindings.
 * Opens read-only fixture files, or selects a Save As destination WITHOUT
 * writing it. Not a reduced Notepad. Normal delivery never stages this APP. */
#include "gbfilepick_ui.h"
#include "gbdocio.h"
#include <string.h>

gb_filepick_t picker;               /* exported for read-only diagnostic observers */
static gb_docio_t job;
static gb_fsctx_t document;
char text[4098];                    /* full 4096-byte capacity + two guards */
static unsigned char view, closing, restart, next_mode, changed, keycool;
volatile unsigned char filepickprobe_state[12];
static const unsigned char menu[] = {2, 10, 'O','p','e','n',0,0,0,0,
                                    18, 'S','a','v','e',' ','A','s',0};

static void record(void)
{
    filepickprobe_state[0] = picker.state;
    filepickprobe_state[1] = picker.mode;
    filepickprobe_state[2] = picker.count;
    filepickprobe_state[3] = picker.more;
    filepickprobe_state[4] = picker.error;
    filepickprobe_state[5] = (unsigned char)picker.offset;
    filepickprobe_state[6] = (unsigned char)(picker.offset >> 8);
    filepickprobe_state[7] = job.state;
    filepickprobe_state[8] = (unsigned char)job.transferred;
    filepickprobe_state[9] = (unsigned char)(job.transferred >> 8);
    filepickprobe_state[10] = view;
    filepickprobe_state[11] = (text[0] == 0x55 && text[4097] == 0x55) ? 85 : 255;
}

static void draw(void)
{
    gb_rect_t r;
    char preview[40]; unsigned char i;
    gb_window_rect(&r);
    if (!view) { gb_filepick_draw(&picker, &r); return; }
    gb_fill(r.x+1, r.y+14, r.w-2, r.h-15, GB_UI_SURFACE);
    gb_text_semantic(r.x+2, r.y+20, view == 1 ? "Reading document..." :
        view == 2 ? "Document loaded" : view == 3 ? "Destination selected (no write)" :
        "Document error", GB_UI_TEXT, GB_UI_SURFACE);
    if (view == 2) {
        for (i=0; i<39 && i<job.transferred; ++i)
            preview[i] = text[i+1] >= 32 && text[i+1] < 127 ? text[i+1] : ' ';
        preview[i] = 0;
        gb_text_semantic(r.x+2, r.y+38, preview, GB_UI_TEXT, GB_UI_SURFACE);
    }
    gb_text_semantic(r.x+2, r.y+58, "Open / Save As in top bar", GB_UI_TEXT, GB_UI_SURFACE);
}

static void frame(void)
{
    gb_rect_t r;
    unsigned char key;
    /* Lifecycle/restart cleanup is itself bounded; no close+open+read burst. */
    if (closing || restart) {
        if (document) { gb_fsctx_close(document); document=0; return; }
        if (picker.context || picker.state == GB_FILEPICK_CLOSING) {
            if (picker.state != GB_FILEPICK_CLOSING) gb_filepick_cancel(&picker);
            gb_filepick_step(&picker); return;
        }
        if (closing) { gb_wm_close(); return; }
        restart=0; view=0; memset(&job,0,sizeof(job));
        gb_filepick_cancel(&picker);
        gb_filepick_begin(&picker,0,"/DOCUI","TXTBASCFG",next_mode);
    } else if (view == 1) {
        gb_docio_step(&job);
        if (!gb_docio_busy(&job)) { view=job.state == GB_DOCIO_DONE ? 2 : 4; changed=1; }
    } else if (!view) {
        gb_filepick_step(&picker);
        if (picker.state == GB_FILEPICK_DONE) {
            document=gb_filepick_take(&picker);
            if (picker.mode == GB_FILEPICK_SAVE) view=3;
            else { gb_docio_load(&job,document,text+1,4096); view=1; }
            changed=1;
        }
        if (gb_flags() & GB_FIRE) keycool=4;
        if (keycool) { --keycool; gb_getkey(); gb_getkey(); }
        else { key=gb_getkey(); if (key) gb_filepick_key(&picker,key); }
    }
    record();
    if (gb_filepick_changed(&picker) || changed) {
        changed=0;
        gb_window_rect(&r);
        gb_wm_damage(r.x+1,r.y+14,r.w-2,r.h-15);
        gb_restore_parent(); /* damage limits the repaint; it does not enqueue one */
    }
}

static void proc(void)
{
    gb_msg_t m; gb_rect_t r;
    gb_message_read(&m);
    if (m.type == GB_MSG_DRAW) draw();
    else if (m.type == GB_MSG_FRAME) frame();
    else if (m.type == GB_MSG_CLOSE) closing=1;
    else if (m.type == GB_MSG_CLICK && !view) {
        keycool=4;
        gb_window_rect(&r); gb_filepick_click(&picker,&r,gb_mx(),gb_my());
    } else if (m.type == GB_MSG_MENU) {
        keycool=4;
        next_mode = m.p0 >= 18; restart=1;
    }
}
static const gb_mwin_kind_t window = {
    {4,20,68,156,64,148,proc,"Document chooser"},
    GB_WK_TITLE | GB_WK_CLOSE | GB_WK_MOVE | GB_WK_RESIZE
};
void main(void)
{
    if (!gb_universal_ready()) return;
    text[0]=text[4097]=0x55;
    gb_filepick_begin(&picker,0,"/DOCUI","TXTBASCFG",GB_FILEPICK_OPEN);
    gb_wm_managed_kind(&window);
    gb_menu(menu);
    record(); gb_restore_parent();
}
