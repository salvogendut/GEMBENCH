/* Real Settings + real CPC facade and selector; host-owned device leaves.
 * Verified storage itself is exercised by config_edit_test.c and M4 tests.
 * This test is not emulated Z80 execution or launch qualification. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_PREEMPTIVE
#define GB_CPC_RESTART
#define GB_NATIVE_WINDOW_KIND
#define GB_SETTINGS_PROVIDER "platform/cpc.h"
#define GB_FSCTX_PLATFORM_HEADER "../../tests/fixtures/fsctx_client_provider.h"
#define main settings_app_main
#include "../apps/settings/main.c"
#undef main
#include "../kernel/kc/cpc_settings.c"

char st_config[512], st_ui_name[16], st_ui_text[232];
char st_font[11], st_icons[11], st_cursor[11], st_backdrop[11];
unsigned int st_config_length;
unsigned char st_solid, st_ui_op, st_ui_result;
volatile gb_msg_t st_message;
static struct { unsigned char active,cursor; char path[48],name[11]; } fs[4];
static unsigned char status_code,fail_path,fail_dir,fail_read,fail_save;
static unsigned char bad_icon,asset_count=20,popup_result=255,popup_count;
static unsigned char pointer_visible,check_paint_pointer;
static unsigned int fs_calls,read_size,reads,alerts,saves,closes,repaints;
static unsigned int text_count,popup_bytes,backdrops;
static char texts[80][64];
static const gb_mwin_kind_t *registered;

static void valid(gb_fsctx_t h) { assert(h && h<=4 && fs[h-1].active);fs_calls++; }
gb_fsctx_t gb_fsctx_open(unsigned char drive)
{
    unsigned char i;assert(!drive);fs_calls++;
    for(i=0;i<4;i++) if(!fs[i].active) {
        memset(&fs[i],0,sizeof(fs[i]));fs[i].active=1;
        strcpy(fs[i].path,"/");status_code=0;return i+1;
    }
    status_code=GB_FSCTX_ERR_FULL;return 0;
}
unsigned char gb_fsctx_close(gb_fsctx_t h)
{ valid(h);fs[h-1].active=0;return status_code=0; }
unsigned char gb_fsctx_status(void) { return status_code; }
unsigned char gb_fsctx_set_path(gb_fsctx_t h,const char *path)
{
    valid(h);if(fail_path)return status_code=GB_FSCTX_ERR_IO;
    assert(strlen(path)<48);strcpy(fs[h-1].path,path);return status_code=0;
}
unsigned char gb_fsctx_set_name(gb_fsctx_t h,const char *name)
{ valid(h);memcpy(fs[h-1].name,name,11);return status_code=0; }
unsigned char gb_fsctx_dir_next(gb_fsctx_t h,gb_fsctx_entry_t *out)
{
    unsigned char n;valid(h);status_code=fail_dir?GB_FSCTX_ERR_IO:0;
    if(status_code)return 0;
    n=fs[h-1].cursor++;
    memset(out,0,sizeof(*out));
    if(!strcmp(fs[h-1].path,"/")) {
        if(n)return 0;
        memcpy(out->name,"GBENCH     ",11);out->attributes=GB_FSCTX_ATTR_DIRECTORY;
    } else {
        if(n>=asset_count)return 0;
        memcpy(out->name,"ASSET00 FNT",11);
        out->name[5]=(char)('0'+n/10);out->name[6]=(char)('0'+n%10);
    }
    return 1;
}
unsigned char gb_fsctx_dir_first(gb_fsctx_t h,gb_fsctx_entry_t *out)
{ fs[h-1].cursor=0;return gb_fsctx_dir_next(h,out); }
unsigned char gb_fsctx_rewind(gb_fsctx_t h) { valid(h);return status_code=0; }
unsigned int gb_fsctx_read(gb_fsctx_t h,char *buffer,unsigned int length)
{
    valid(h);assert(length<=512);read_size=length;reads++;
    status_code=fail_read?GB_FSCTX_ERR_IO:0;
    if(status_code)return 0;
    memset(buffer,0,length);
    if(length>=16) { memcpy(buffer,bad_icon?"BAD!":"GBIS",4);buffer[5]=21; }
    return length;
}
void cpc_config_update(void)
{
    assert(UI_OP==26);saves++;UI_RES=!fail_save;
    pointer_visible=1; /* the shared reload/repaint restores the pointer */
    if(UI_RES) {
        st_config_length=(unsigned int)snprintf(st_config,sizeof(st_config),
                                               "%s%s\r\n",UI_NAME,UI_TEXT);
    }
}
unsigned char gb_wm_x(void) { return DEF_X; }
unsigned char gb_wm_y(void) { return DEF_Y; }
unsigned char gb_wm_w(void) { return DEF_W; }
unsigned char gb_wm_h(void) { return DEF_H; }
unsigned char gb_mx(void) { return 0; }
unsigned char gb_my(void) { return 0; }
unsigned char gb_getkey(void) { return 0; }
void gb_curhide(void) { pointer_visible=0; }
void gb_curshow(void) { pointer_visible=1; }
void gb_wm_managed_kind(const gb_mwin_kind_t *desc) { registered=desc; }
void gb_wm_close(void) { closes++; }
unsigned char gb_app_quit(void) { closes++;return 0; }
void gb_repaint_top(void) { repaints++;text_count=0;s_draw(); }
void gb_textbw(unsigned char x,unsigned char y,const char *text)
{
    assert(x<GB_COLS && y+8<=GB_LINES && text_count<80);
    assert(strlen(text)<64);strcpy(texts[text_count++],text);
}
void gb_fill(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{
    assert(x+w<=GB_COLS && y+h<=GB_LINES && pen<4);
    if(check_paint_pointer)assert(!pointer_visible);
    if(y>=DEF_Y+TITLE_H)assert(x>DEF_X && x+w<DEF_X+DEF_W && y+h<DEF_Y+DEF_H);
}
void gb_frame(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{ gb_fill(x,y,w,h,pen); }
void gb_backdrop(unsigned char x,unsigned char y,unsigned char w,unsigned char h)
{ backdrops++;gb_fill(x,y,w,h,0); }
void gb_alert(const char *a,const char *b)
{ assert(a && b);alerts++;text_count=0; }
unsigned char gb_popup(unsigned char x,unsigned char y,const char *const *list,unsigned char n)
{
    unsigned char i;assert(x<GB_COLS && y<GB_LINES && n<=17);
    popup_bytes=0;popup_count=n;
    for(i=0;i<n;i++)popup_bytes+=(unsigned int)strlen(list[i])+1;
    assert(popup_bytes<=sizeof(st_ui_text));text_count=0;return popup_result;
}
static unsigned char label(const char *text)
{
    unsigned int i;
    for(i=0;i<text_count;i++)if(!strcmp(texts[i],text))return 1;
    return 0;
}
static void config(const char *text)
{ strcpy(st_config,text);st_config_length=(unsigned int)strlen(text); }
static void drain_picker(void)
{
    unsigned char frame;
    for(frame=0;frame<80 && picker_state!=PICK_IDLE;frame++) {
        unsigned int before=fs_calls;text_count=0;picker_step();
        assert(fs_calls-before<=6); /* directory slices remain bounded */
    }
    assert(picker_state==PICK_IDLE && !settings_storage_claim);
}

int main(void)
{
    char text[512],old[512];unsigned int length=123,before;
    gb_fsctx_t other,third,fourth;unsigned char i;
    assert(GB_COLS==80 && GB_LINES==200 && NROWS==6 && MAXST==16);
    other=gb_fsctx_open(0);assert(!gb_fsctx_set_path(other,"/OTHER"));
    fs[other-1].cursor=7;memcpy(fs[other-1].name,"KEEP    TXT",11);
    config("FONT=DEFAULT\r\nBACKDROP=SOLID\r\n");
    assert(settings_begin(text,&length));assert(length==st_config_length);
    assert(!memcmp(text,st_config,length));assert(!settings_begin(text,&length));
    assert(gb_get_drive()==GB_DRIVE_C && gb_drives()==GB_DRV_C);
    assert(gb_dir1() && gb_isdir());gb_chdir();assert(!strcmp(fs[context-1].path,"/GBENCH"));
    assert(gb_dir1() && !gb_isdir());gb_back();
    assert(!strcmp(fs[other-1].path,"/OTHER") && fs[other-1].cursor==7);
    assert(!memcmp(fs[other-1].name,"KEEP    TXT",11));
    gb_set_drive(GB_DRIVE_A);assert(settings_io_failed()==GB_FSCTX_ERR_UNSUPPORTED);
    settings_io_reset();assert(ist_count("REFINED")==21 && read_size==16 && reads==1);
    assert(!memcmp(fs[context-1].name,"REFINED IST",11));
    bad_icon=1;assert(!ist_count("REFINED"));bad_icon=0;
    fail_read=1;assert(!ist_count("REFINED") && settings_io_failed());fail_read=0;
    settings_io_reset();assert(!gb_fs_load(text,513) && settings_io_failed());
    settings_io_reset();fail_dir=1;assert(!gb_dir1() && settings_io_failed());fail_dir=0;
    settings_io_reset();
    before=saves;memcpy(old,text,sizeof(text));fail_save=1;
    assert(!settings_commit("FONT=","CLASSIC.FNT",text,&length));
    assert(saves==before+1 && !memcmp(old,text,sizeof(text)));
    fail_save=0;assert(settings_commit("FONT=","CLASSIC.FNT",text,&length));
    assert(!memcmp(text,"FONT=CLASSIC.FNT\r\n",length));
    before=saves;assert(!settings_commit("TOO-LONG-KEYNAME=","DEFAULT",text,&length));
    assert(!settings_commit("FONT=","TOO-LONG-VALUENAME",text,&length) && saves==before);
    settings_end();assert(!context && fs[other-1].active);
    st_config_length=513;length=123;
    assert(!settings_begin(text,&length) && length==123 && !context);
    config("FONT=DEFAULT\r\n");st_config[3]=0;assert(!settings_begin(text,&length));
    config("FONT=DEFAULT\r\n");fail_path=1;assert(!settings_begin(text,&length));fail_path=0;
    third=gb_fsctx_open(0);fourth=gb_fsctx_open(0);
    assert(settings_begin(text,&length));settings_end();
    { gb_fsctx_t full=gb_fsctx_open(0);
      assert(!settings_begin(text,&length) && settings_io_failed()==GB_FSCTX_ERR_FULL);
      gb_fsctx_close(full); }
    gb_fsctx_close(third);gb_fsctx_close(fourth);

    settings_app_main();assert(registered==&smw && repaints==1);
    assert(smw.kind==(GB_WK_TITLE|GB_WK_CLOSE|GB_WK_MOVE));
    for(i=0;i<NROWS;i++)assert(label(rows[i].label));
    assert(!label("Colours...") && !label("Screensaver") && !label("Wallpaper"));
    assert(!label("Return to Defaults...") && label("DEFAULT") && backdrops);
    text_count=0;picker_start(ROW_WALLPAPER,0);assert(picker_state==PICK_IDLE);
    picker_start(0,1);assert(picker_state==PICK_IDLE);
    picker_start(0,0);drain_picker();assert(nstem==16 && popup_count==16);
    text_count=0;picker_start(0,0);gb_set_drive(GB_DRIVE_A);
    picker_start(0,0); /* re-entry must not erase a pending I/O failure */
    assert(settings_io_failed()==GB_FSCTX_ERR_UNSUPPORTED);drain_picker();
    before=alerts;fail_dir=1;text_count=0;picker_start(0,0);drain_picker();fail_dir=0;
    assert(alerts==before+1 && picker_state==PICK_IDLE);
    text_count=0;picker_start(0,0);drain_picker(); /* a new attempt clears old error */
    for(i=0;i<MAXST;i++) { strcpy(&stembuf[i*STLEN],"C:ABCDEFGH");stems[i]=&stembuf[i*STLEN]; }
    nstem=MAXST;text_count=0;picker_row_finish(ROW_BACKDROP);
    assert(popup_count==17 && popup_bytes==182);
    check_paint_pointer=1;
    popup_result=0;fail_save=1;before=alerts;memcpy(old,cfgbuf,sizeof(cfgbuf));
    text_count=0;picker_row_finish(ROW_BACKDROP);
    assert(alerts==before+1 && !memcmp(old,cfgbuf,sizeof(cfgbuf)));
    fail_save=0;text_count=0;picker_row_finish(ROW_BACKDROP);
    assert(!strcmp(UI_NAME,"BACKDROP=") && !strcmp(UI_TEXT,"SOLID"));
    text_count=0;picker_start(0,0);assert(settings_storage_claim);
    s_close();assert(!context && closes==1 && fs[other-1].active);
    assert(picker_state==PICK_IDLE && !settings_storage_claim);
    assert(!strcmp(fs[other-1].path,"/OTHER") && fs[other-1].cursor==7);
    gb_fsctx_close(other);
    puts("CPC Settings: owned context, bounded picker, verified-gate publication and six-row UI PASS");
    return 0;
}
