/* Actual integration source + real chooser/docio helpers, mocked public FS,
 * clipboard and drawing services. Host policy tests, NOT runtime acceptance. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define main notepad_entry
#include "../apps/unotepad/main.c"
#undef main

unsigned char gb_ufs_request[32], gb_ufs_transfer[512];
static char disk[8194], clip[510];
static unsigned int disk_len, offset[5], fs_calls, fail_call, writes, clip_len;
static unsigned char live[5], fs_error, clip_kind, clip_error, closed;
static unsigned char input[8], input_pos, mouse_x, mouse_y, buttons;
static gb_rect_t live_rect = {2,14,66,158};
static gb_rect_t damage;

static unsigned char call(gb_fsctx_t h)
{
    ++fs_calls;
    fs_error = fs_calls == fail_call ? GB_FSCTX_ERR_IO :
               h > 4 || !live[h] ? GB_FSCTX_ERR_STALE : 0;
    return fs_error;
}
gb_fsctx_t gb_fsctx_open(unsigned char d)
{
    unsigned int i;
    (void)d; ++fs_calls;
    if (fs_calls == fail_call) { fs_error = GB_FSCTX_ERR_IO; return 0; }
    for (i=1; i<=4; ++i) if (!live[i]) { live[i]=1; offset[i]=0; fs_error=0; return i; }
    fs_error=GB_FSCTX_ERR_FULL; return 0;
}
unsigned char gb_fsctx_close(gb_fsctx_t h)
{
    if (!call(h)) live[h]=0;
    return fs_error;
}
unsigned char gb_fsctx_status(void) { return fs_error; }
unsigned char gb_fsctx_set_path(gb_fsctx_t h,const char *p) { (void)p; return call(h); }
unsigned char gb_fsctx_set_name(gb_fsctx_t h,const char *p) { (void)p; return call(h); }
unsigned char gb_fsctx_activate(gb_fsctx_t h) { return call(h); }
unsigned char gb_fsctx_dir_batch(gb_fsctx_t h,unsigned char first)
{ (void)first; call(h); return 0; }
unsigned char gb_fsctx_rewind(gb_fsctx_t h)
{
    if (!call(h)) offset[h]=0;
    return fs_error;
}
unsigned int gb_fsctx_read(gb_fsctx_t h,char *p,unsigned int n)
{
    assert(n<=512);
    if (call(h)) return 0;
    if (n>disk_len-offset[h]) n=disk_len-offset[h];
    memcpy(p,disk+offset[h],n); offset[h]+=n;
    return n;
}
unsigned char gb_fsctx_write(gb_fsctx_t h,const char *p,unsigned int n)
{
    assert(n<=512);
    if (call(h)) return fs_error;
    ++writes; assert(offset[h]+n<=sizeof(disk));
    if (!offset[h]) disk_len=0;
    if (n) memcpy(disk+offset[h],p,n);
    offset[h]+=n; disk_len=offset[h]; return 0;
}
unsigned char gb_scrap_set(unsigned char type,const char *p,unsigned int n)
{
    unsigned char result=n>510 ? GB_SCRAP_TRUNCATED : 0;
    if (clip_error) return clip_error;
    if (n>510) n=510;
    memcpy(clip,p,n); clip_len=n; clip_kind=type; return result;
}
unsigned char gb_scrap_query(gb_scrap_info_t *i)
{ i->length=clip_len; i->type=clip_kind; return clip_error; }
unsigned char gb_scrap_get(unsigned char type,char *p,unsigned int n,unsigned int *copied)
{
    *copied=0;
    if (clip_error) return clip_error;
    if (type!=clip_kind) return GB_SCRAP_ERR_MISMATCH;
    if (n>clip_len) n=clip_len;
    memcpy(p,clip,n); *copied=n; return 0;
}
unsigned char gb_universal_ready(void) { return 1; }
unsigned char gb_boot_drive_current(void) { return 0; }
unsigned char gb_screen_columns(void) { return 128; }
unsigned char gb_screen_lines(void) { return 212; }
void gb_window_rect(gb_rect_t *r) { *r=live_rect; }
void gb_wm_setpos(unsigned char x,unsigned char y) { live_rect.x=x; live_rect.y=y; }
void gb_wm_setsize(unsigned char w,unsigned char h) { live_rect.w=w; live_rect.h=h; }
void gb_wm_managed_kind(const gb_mwin_kind_t *w) { (void)w; }
void gb_wm_close(void) { closed=1; }
void gb_menu(const void *p) { (void)p; }
void gb_message_read(gb_msg_t *m) { memset(m,0,sizeof(*m)); }
unsigned char gb_universal_popup_active(void) { return 0; }
void gb_universal_popup_close(void) { }
unsigned char gb_universal_popup(unsigned char x,const char *const *p,unsigned char n)
{ (void)x; (void)p; (void)n; return 255; }
unsigned char gb_getkey(void) { return input_pos<sizeof(input) ? input[input_pos++] : 0; }
unsigned char gb_mx(void) { return mouse_x; }
unsigned char gb_my(void) { return mouse_y; }
unsigned char gb_flags(void) { return buttons; }
void gb_fill(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char p)
{ assert(x+w<=128 && y+h<=212 && p<4); }
void gb_text_semantic(unsigned char x,unsigned char y,const char *p,unsigned char pen,unsigned char paper)
{ assert(x<=128 && y+8<=212 && strlen(p)<NP_LINE_MAX && pen<4 && paper<4); }
void gb_wm_damage(unsigned char x,unsigned char y,unsigned char w,unsigned char h)
{ damage.x=x; damage.y=y; damage.w=w; damage.h=h; assert(x+w<=128 && y+h<=212); }
void gb_restore_parent(void) { draw(); }

static void reset_test(void)
{
    memset(&editor,0,sizeof(editor)); memset(&scratch,0,sizeof(scratch));
    memset(&job,0,sizeof(job)); memset(live,0,sizeof(live)); memset(offset,0,sizeof(offset));
    memset(input,0,sizeof(input)); input_pos=0;
    document=candidate=retired=0; fs_calls=fail_call=writes=0;
    fs_error=clip_error=closed=buttons=0; disk_len=clip_len=0;
    mode=EDIT; action=menu_request=cooldown=refresh=title_changed=dragging=blink=full=0;
    live_rect.x=2; live_rect.y=14; live_rect.w=66; live_rect.h=158;
    notepad_entry(); refresh=title_changed=0;
}
static void tick(void)
{
    unsigned int before=fs_calls;
    frame(); assert(fs_calls<=before+1);
}
static void run_io(void)
{
    unsigned int limit=100;
    while (mode==LOAD || mode==SAVE || mode==BAS_REWIND || mode==BAS_WRITE) {
        assert(limit--); tick();
    }
}
static void old_document(void)
{
    document=gb_fsctx_open(0);
    assert(np_loaded(&editor,"old unsaved",11,0)); editor.dirty=1;
    memcpy(name,"OLD     TXT",11); strcpy(path,"/OLD");
}
static void begin_load(void)
{
    candidate=gb_fsctx_open(0); memcpy(next_name,"NEW     TXT",11); strcpy(next_path,"/NEW");
    gb_docio_load(&job,candidate,scratch.bytes,NP_MAX); mode=LOAD;
}
static void model(void)
{
    unsigned int i,row,n; unsigned char col;
    np_editor_t e={0}; char data[NP_MAX+1], encoded[8194];
    np_bas_t state;
    memset(data,'x',sizeof(data));
    assert(np_key(&e,'a') && np_key(&e,'b') && np_key(&e,13));
    assert(e.len==3 && !memcmp(e.text,"ab\n",3));
    np_all(&e); assert(np_key(&e,'z') && e.len==1 && e.text[0]=='z');
    assert(np_key(&e,8) && !e.len && !np_key(&e,8));
    assert(np_loaded(&e,data,NP_MAX,0) && !e.dirty);
    e.cur=e.len; assert(!np_key(&e,'q') && e.len==NP_MAX);
    assert(!np_loaded(&e,data,NP_MAX+1,0) && e.len==NP_MAX);
    e.anchor=100; np_select(&e,200); assert(np_replace(&e,"XYZ",3));
    assert(e.len==3999 && e.cur==103 && !memcmp(e.text+100,"XYZ",3));
    assert(!np_replace(&e,data,NP_MAX) && e.len==3999);
    memset(data,'\n',NP_MAX);
    assert(np_loaded(&e,data,NP_MAX,0));
    np_position(&e,4096,39,&row,&col); assert(row==4096 && !col);
    assert(np_index(&e,300,0,39)==300);
    e.cur=4096; np_follow(&e,39,12); assert(e.first==4085);
    e.cur=0; np_follow(&e,39,12); assert(!e.first);
    assert(np_loaded(&e,"abc\r\ndef\r\n",10,1) && e.len==8);
    for (i=1;i<=84;++i) {
        unsigned int pos;
        assert(np_loaded(&e,"123456789\nxyz",13,0));
        for (pos=0;pos<=e.len;++pos) {
            np_position(&e,pos,(unsigned char)i,&row,&col);
            assert(np_index(&e,row,col,(unsigned char)i)==pos);
        }
    }
    /* Empty, no trailing LF, exact/full capacity, and chunks split after CR. */
    for (i=0;i<=NP_MAX;i=i ? i==1 ? 511 : i==511 ? 512 : i==512 ? NP_MAX : NP_MAX+1 : 1) {
        unsigned int cap;
        memset(data,'\n',i); assert(np_loaded(&e,data,i,0));
        for (cap=1;cap<=512;cap=cap==1 ? 511 : cap+1) {
            state.offset=0; state.phase=0; n=0;
            while (state.phase!=4) n+=np_bas_chunk(&e,&state,encoded+n,cap);
            assert(n==(i ? i*2 : 2));
            for (row=0;row<n;row+=2) assert(encoded[row]=='\r' && encoded[row+1]=='\n');
            assert(e.len==i && !memcmp(e.text,data,i));
        }
    }
    assert(np_loaded(&e,"a\nb",3,0)); state.offset=state.phase=0;
    n=np_bas_chunk(&e,&state,encoded,sizeof(encoded));
    assert(n==6 && !memcmp(encoded,"a\r\nb\r\n",6));
}
static void lifecycle(void)
{
    unsigned int failure;
    reset_test(); old_document();
    close_request(); assert(mode==CONFIRM && !closed); confirm(27);
    assert(mode==EDIT && editor.dirty && editor.len==11);
    tick(); input[0]=17; input_pos=0; tick(); assert(mode==CONFIRM && !closed);
    confirm('d'); for (failure=0;failure<4 && !closed;++failure) tick(); assert(closed);
    reset_test(); old_document(); request(NEW); confirm('s');
    run_io(); assert(mode==EDIT && !editor.dirty && disk_len==11);
    tick(); assert(!editor.len && !memcmp(name,"UNTITLEDTXT",11));
    tick(); assert(!live[1]);
    /* Failure at rewind or every load chunk/EOF probe retains the OLD editor. */
    for (failure=1;failure<=10;++failure) {
        reset_test(); old_document(); memset(disk,'N',4096); disk_len=4096;
        begin_load(); fail_call=fs_calls+failure; run_io();
        assert(mode==ERROR && editor.dirty && editor.len==11);
        assert(!memcmp(editor.text,"old unsaved",11) && !memcmp(name,"OLD     TXT",11));
        assert(document && !candidate && retired);
        fail_call=0; close_request(); tick(); assert(!retired && mode==EDIT);
    }
    reset_test(); old_document(); memset(disk,'N',4097); disk_len=4097;
    begin_load(); run_io(); assert(mode==ERROR && editor.len==11 && editor.dirty);
    reset_test(); old_document(); memcpy(disk,"new\r\n",5); disk_len=5;
    begin_load(); memcpy(next_name,"NEW     BAS",11); run_io();
    assert(mode==EDIT && !editor.dirty && editor.len==4 && !memcmp(editor.text,"new\n",4));
    assert(!strcmp(path,"/NEW") && retired); tick(); assert(!retired);
    reset_test(); old_document(); begin_load(); close_request(); tick();
    assert(mode==EDIT && editor.len==11 && editor.dirty && !retired);
    /* Save As never publishes the destination until a complete write. */
    reset_test(); old_document(); candidate=gb_fsctx_open(0);
    memcpy(next_name,"NEW     TXT",11); strcpy(next_path,"/NEW"); mode=OVERWRITE;
    tick(); assert(!writes); confirm(27); tick();
    assert(!candidate && !retired && editor.dirty && !memcmp(name,"OLD     TXT",11));
    for (failure=1;failure<=9;++failure) {
        reset_test(); old_document(); memset(editor.text,'T',4096); editor.len=4096;
        candidate=gb_fsctx_open(0); memcpy(next_name,"NEW     TXT",11); strcpy(next_path,"/NEW");
        start_save(); fail_call=fs_calls+failure; run_io();
        assert(mode==ERROR && editor.dirty && editor.len==4096 && !memcmp(name,"OLD     TXT",11));
    }
    reset_test(); old_document(); editor.dirty=0; start_save();
    fail_call=fs_calls+2; run_io(); assert(mode==ERROR && editor.dirty);
    /* BASIC expansion at maximum capacity; a failure never rewrites the text. */
    for (failure=0;failure<=17;++failure) {
        reset_test(); old_document(); memset(editor.text,'\n',4096); editor.len=4096;
        memcpy(name,"OLD     BAS",11); start_save();
        fail_call=failure ? fs_calls+failure : 0; run_io();
        assert(editor.len==4096);
        for (unsigned int i=0;i<4096;++i) assert(editor.text[i]=='\n');
        if (failure) assert(mode==ERROR && editor.dirty);
        else assert(mode==EDIT && !editor.dirty && disk_len==8192);
    }
    reset_test(); old_document(); request(NEW); confirm('d');
    fail_call=fs_calls+1; tick(); assert(mode==ERROR && retired);
    failure=fs_calls; tick(); assert(fs_calls==failure); /* no silent retry spin */
    fail_call=0; close_request(); tick(); assert(!retired && mode==EDIT);
}
static void clipboard_and_damage(void)
{
    reset_test(); old_document(); np_all(&editor); copy();
    assert(clip_len==11 && clip_kind==GB_SCRAP_TEXT);
    clip_error=GB_SCRAP_ERR_CONTEXT; paste();
    assert(editor.selected && editor.len==11);
    clip_error=0; memcpy(clip,"pasted",6); clip_len=6; paste();
    assert(editor.len==6 && !memcmp(editor.text,"pasted",6));
    np_all(&editor); clip_kind=GB_SCRAP_BITMAP; paste(); assert(editor.len==6);
    /* At most two edits per frame; Ctrl-Q cannot bypass dirty confirmation. */
    editor.selected=0; editor.cur=editor.len;
    memcpy(input,"abcd",4); input_pos=0; tick(); assert(editor.len==8 && input_pos==2);
    assert(damage.y>=live_rect.y+16 && damage.y+damage.h<=live_rect.y+16+rows*10);
    tick(); assert(editor.len==10);
    /* Long-line/fullscreen render and caret damage remain inside the client. */
    for (unsigned int width=30;width<=128;++width) {
        live_rect.w=(unsigned char)width; live_rect.x=0;
        memset(editor.text,'A',4096); editor.len=4096; editor.cur=4096;
        geometry(); np_follow(&editor,wrap,rows); draw();
        blink=15; memset(input,0,sizeof(input)); input_pos=0; tick();
        assert(damage.w==2 && damage.h==2);
    }
}
static void chooser_integration(void)
{
    unsigned int guard, before;
    const char *p;
    reset_test(); old_document(); request(OPEN); confirm('d');
    assert(mode==PICK && editor.dirty && editor.len==11);
    for (guard=0;guard<30 && picker.state!=GB_FILEPICK_READY;++guard) tick();
    assert(picker.state==GB_FILEPICK_READY && picker.context);
    close_request();
    for (guard=0;guard<30 && mode==PICK;++guard) tick();
    assert(mode==EDIT && editor.dirty && !candidate && live[document]);
    /* Real chooser -> named context -> explicit overwrite confirmation -> job. */
    choose(GB_FILEPICK_SAVE);
    for (guard=0;guard<30 && picker.state!=GB_FILEPICK_READY;++guard) tick();
    assert(picker.state==GB_FILEPICK_READY);
    for (p="SAVED.TXT";*p;++p) gb_filepick_key(&picker,(unsigned char)*p);
    gb_filepick_submit(&picker);
    for (guard=0;guard<30 && mode==PICK;++guard) tick();
    assert(mode==OVERWRITE && candidate && !writes && editor.dirty);
    assert(!memcmp(next_name,"SAVED   TXT",11));
    before=fs_calls; confirm('s'); assert(fs_calls==before); run_io();
    assert(mode==EDIT && !editor.dirty && disk_len==11 && !memcmp(name,"SAVED   TXT",11));
    tick(); assert(!retired);
    /* Keyboard frame bound remains in force inside the chooser too. */
    choose(GB_FILEPICK_SAVE);
    for (guard=0;guard<30 && picker.state!=GB_FILEPICK_READY;++guard) tick();
    while (refresh) tick();
    memcpy(input,"ABCD",4); input_pos=0; tick();
    assert(input_pos==2 && !strcmp(picker.edit,"AB"));
}
int main(void)
{
    model(); lifecycle(); clipboard_and_damage(); chooser_integration();
    puts("unified Notepad model/controller tests PASS (mocked services; no runtime claim)");
    return 0;
}
