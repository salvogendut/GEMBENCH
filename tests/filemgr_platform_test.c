/* Actual File Manager + CPC binding + shared menus/scrollbar. Kernel/storage
 * leaves are mocked; target layout and M4 execution are separate gates. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_PREEMPTIVE
#define GB_CPC_RESTART
#define GB_FILEMGR_PROVIDER "../../tests/filemgr_provider.h"
#define GB_FSCTX_PLATFORM_HEADER "../../tests/fixtures/fsctx_client_provider.h"
#define main filemgr_main
#include "../apps/filemgr/main.c"
#undef main
#include "../kernel/kc/cpc_filemgr.c"

char fm_test_config[512],fm_test_ui_name[16],fm_test_ui_text[232];
unsigned int fm_test_config_length;
unsigned char fm_test_ui_op,fm_test_ui_result,fm_test_focus,fm_test_windows,fm_test_pages;
volatile gb_msg_t fm_test_message;
gb_fsctx_entry_t fm_test_batch[4];
static struct { unsigned char active,cursor;char path[48]; } contexts[4];
static unsigned char status_code,fail_directory,fail_activate,fail_save,fail_open,fail_path;
static unsigned char pointer_x,pointer_y,key,selected_menu=255,changed_entry;
static unsigned int fs_calls,alerts,opens,saves,paints,closes,damage,cleared_cells;
static unsigned char draw_x=DEF_X,draw_y=DEF_Y,draw_w=DEF_W,draw_h=DEF_H;
static char opened[12];
static const gb_mwin_kind_t *registered;
static const char root_names[][12]={"Z       TXT","GBENCH     ","A       TXT","NATIVE  BIN","OTHER      "};
static const char app_names[][12]={"CALC    APP","CLOCK   APP","ABIPROBEAPP","DATA    TXT"};

static void entry(gb_fsctx_t h,unsigned char index,gb_fsctx_entry_t *out)
{
    unsigned char root=!strcmp(contexts[h-1].path,"/");
    memcpy(out->name,root?root_names[index]:app_names[index],11);
    out->attributes=root && (index==1 || index==4)?GB_FSCTX_ATTR_DIRECTORY:0x20;
    out->size=123;
    if(changed_entry)out->name[0]='X';
}
static unsigned char count(gb_fsctx_t h)
{ return !strcmp(contexts[h-1].path,"/")?5:4; }
gb_fsctx_t gb_fsctx_open(unsigned char drive)
{
    unsigned char i;assert(!drive);fs_calls++;
    for(i=0;i<4;i++)if(!contexts[i].active){
        contexts[i].active=1;contexts[i].cursor=0;strcpy(contexts[i].path,"/");
        status_code=0;return i+1;
    }
    status_code=GB_FSCTX_ERR_FULL;return 0;
}
unsigned char gb_fsctx_set_path(gb_fsctx_t h,const char *path)
{
    assert(h && h<=4 && contexts[h-1].active && strlen(path)<48);fs_calls++;
    if(fail_path)return status_code=GB_FSCTX_ERR_STALE;
    strcpy(contexts[h-1].path,*path?path:"/");return status_code=0;
}
unsigned char gb_fsctx_activate(gb_fsctx_t h)
{ assert(h && h<=4 && contexts[h-1].active);fs_calls++;return status_code=fail_activate?GB_FSCTX_ERR_IO:0; }
unsigned char gb_fsctx_status(void){return status_code;}
unsigned char gb_fsctx_dir_batch(gb_fsctx_t h,unsigned char first)
{
    unsigned char n=0;assert(h && h<=4 && contexts[h-1].active);fs_calls++;
    if(first)contexts[h-1].cursor=0;
    while(n<4 && contexts[h-1].cursor<count(h))entry(h,contexts[h-1].cursor++,&fm_test_batch[n++]);
    status_code=fail_directory?GB_FSCTX_ERR_IO:0;return fail_directory?0:n;
}
unsigned char gb_fsctx_dir_next(gb_fsctx_t h,gb_fsctx_entry_t *out)
{
    fs_calls++;status_code=fail_directory?GB_FSCTX_ERR_IO:0;
    if(status_code || contexts[h-1].cursor==count(h))return 0;
    entry(h,contexts[h-1].cursor++,out);return 1;
}
unsigned char gb_fsctx_dir_first(gb_fsctx_t h,gb_fsctx_entry_t *out)
{contexts[h-1].cursor=0;return gb_fsctx_dir_next(h,out);}
unsigned char gb_fsctx_free_kib(gb_fsctx_t h,unsigned int *kib)
{assert(h && contexts[h-1].active);fs_calls++;*kib=32760;return 1;}
void cpc_config_update(void)
{
    assert(UI_OP==26 && !strcmp(UI_NAME,"VIEW="));
    assert(!strcmp(UI_TEXT,"LIST") || !strcmp(UI_TEXT,"DEFAULT"));
    saves++;UI_RES=!fail_save;
    if(UI_RES){snprintf(fm_test_config,sizeof(fm_test_config),"VIEW=%s\r\n",UI_TEXT);fm_test_config_length=strlen(fm_test_config);}
}
void gb_wm_open(const char *name)
{opens++;memcpy(opened,name,11);opened[11]=0;if(!fail_open)fm_test_focus=2;}
void gb_wm_managed_kind(const gb_mwin_kind_t *desc)
{registered=desc;fm_test_windows=2;fm_test_focus=1;fm_test_pages=26;}
unsigned char gb_app_quit(void){closes++;return 0;}
void gb_wm_close(void){closes++;}
void gb_menu(const void *definition){assert(definition);}
unsigned char gb_resource_menu_popup(unsigned char col,const unsigned char *desc,unsigned int size,const unsigned char *state)
{assert(col==10 && desc && size && state);return selected_menu;}
void gb_alert(const char *first,const char *second){assert(first && second);alerts++;}
unsigned char gb_wm_x(void){return draw_x;}
unsigned char gb_wm_y(void){return draw_y;}
unsigned char gb_wm_w(void){return draw_w;}
unsigned char gb_wm_h(void){return draw_h;}
void gb_wm_setpos(unsigned char x,unsigned char y){draw_x=x;draw_y=y;}
void gb_wm_setsize(unsigned char w,unsigned char h){draw_w=w;draw_h=h;}
void gb_wm_damage(unsigned char x,unsigned char y,unsigned char w,unsigned char h)
{assert((unsigned int)x+w<=GB_COLS && (unsigned int)y+h<=GB_LINES);damage++;}
void gb_repaint_top(void){paints++;}
void gb_restore_parent(void){paints++;}
void gb_curhide(void){}
void gb_curshow(void){}
unsigned char gb_flags(void){return 0;}
unsigned char gb_mx(void){return pointer_x;}
unsigned char gb_my(void){return pointer_y;}
unsigned char gb_getkey(void){unsigned char value=key;key=0;return value;}
unsigned char gb_poll(void){return GB_QUIT;}
void gb_fill(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{assert((unsigned int)x+w<=GB_COLS && (unsigned int)y+h<=GB_LINES && pen<4);if(!pen && w==CELL_W && h==CELL_H-1)cleared_cells++;}
void gb_frame(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{assert(pen);gb_fill(x,y,w,h,pen);}
void gb_text(unsigned char x,unsigned char y,const char *text)
{assert(x<GB_COLS && y+8<=GB_LINES && text);}
void gb_textbw(unsigned char x,unsigned char y,const char *text){gb_text(x,y,text);}
void gb_icon(unsigned char slot,unsigned char x,unsigned char y){assert(slot<21 && x<GB_COLS && y<GB_LINES);}
void gb_icon_half(unsigned char slot,unsigned char x,unsigned char y){gb_icon(slot,x,y);}

static void finish_list(void)
{for(unsigned char i=0;i<8 && list_state;i++)fm_frame();assert(list_state==LIST_IDLE);}
int main(void)
{
    (void)GB_FSCTX_REQUEST;
    assert(GB_COLS==80 && GB_LINES==200 && FM_SHARED_CORE && !FM_FILE_COPY && !FM_EMBEDDED_ICONS);
    strcpy(fm_test_config,"VIEW=DEFAULT\r\n");fm_test_config_length=strlen(fm_test_config);
    filemgr_main();assert(registered==&fmmw_kind && registered->kind==GB_WK_STANDARD);
    assert(view_menu.valid && list_state==LIST_WAIT && fs_context==1 && !paints);
    fm_frame();assert(total==4 && list_state==LIST_NEXT && !disp_total() && !paints);
    gb_fsctx_t other=gb_fsctx_open(0);gb_fsctx_set_path(other,"/OTHER");
    gb_fsctx_dir_batch(other,1); /* another window's operation between batches */
    finish_list();assert(total==5 && order[0]==1 && order[1]==4 && order[2]==2 && order[3]==0);
    assert(strstr(title_buf,"Disk C") && strstr(title_buf,"31MiB free") && paints==1);
    fm_draw();unsigned int before=fs_calls;
    pointer_x=CT_X+1;pointer_y=CT_Y+2;fm_click();assert(nsel==1 && fs_calls==before);
    fm_click();assert(!strcmp(fm_path,"/GBENCH") && !strcmp(contexts[0].path,fm_path));
    finish_list();assert(total==4 && !strcmp(contexts[other-1].path,"/OTHER"));
    assert(order[0]==2 && order[1]==0 && order[2]==1 && order[3]==3);
    select_entry(3);before=cleared_cells;
    open_entry(1);assert(opens==1 && !memcmp(opened,"CALC    APP",11) && !alerts);
    assert(!nsel && cleared_cells==before+1); /* repair one cell before child focus */
    fm_test_focus=1;fail_open=1;open_entry(1);assert(opens==2 && alerts==1);fail_open=0;
    before=opens;open_entry(3);assert(opens==before && alerts==2); /* TXT deferred */
    changed_entry=1;open_entry(0);assert(opens==before && alerts==3);changed_entry=0;finish_list();
    assert(filemgr_open_file(fs_context,"/OTHER","CALC    APP")==1 && opens==before);
    fail_activate=1;assert(filemgr_open_file(fs_context,"/GBENCH","CALC    APP")==2);fail_activate=0;
    fm_test_pages=0;assert(filemgr_open_file(fs_context,"/GBENCH","CALC    APP")==2);fm_test_pages=26;
    fm_test_windows=8;assert(filemgr_open_file(fs_context,"/GBENCH","CALC    APP")==2);fm_test_windows=2;
    assert(!filemgr_save_view(2));
    key='l';fm_frame();assert(view==V_LIST && saves==1 && !strcmp(fm_test_config,"VIEW=LIST\r\n"));
    assert(gbr_menu_checked(&view_menu,FILEMGR_VIEW_LIST));
    fail_save=1;key='i';before=alerts;fm_frame();assert(view==V_ICONS && alerts==before+1);
    assert(!strcmp(fm_test_config,"VIEW=LIST\r\n"));fail_save=0;
    key='l';fm_frame();key='i';fm_frame();assert(!strcmp(fm_test_config,"VIEW=DEFAULT\r\n"));
    fm_test_message.type=GB_MSG_MENU;fm_test_message.p0=10;fm_proc();
    assert(view_menu.armed);selected_menu=2;fm_frame();assert(view==V_LIST && !view_menu.armed);
    fm_proc();selected_menu=255;before=saves;fm_frame();assert(view==V_LIST && saves==before);
    draw_x=10;draw_y=20;fm_test_message.type=GB_MSG_MOVED;fm_proc();assert(win_x==10 && win_y==20);
    draw_w=40;draw_h=90;top=99;fm_test_message.type=GB_MSG_SIZED;fm_proc();assert(win_w==40 && win_h==90 && top<99);
    fm_draw();
    go_up();assert(!fm_path[0] && !strcmp(contexts[0].path,"/"));finish_list();
    before=alerts;relist();fm_frame();assert(total==4 && list_state==LIST_NEXT);
    fail_directory=1;fm_frame();assert(!list_state && !total && alerts==before+1);
    assert(!strcmp(title_buf,"Error"));fail_directory=0;
    fm_test_message.type=GB_MSG_DROP;before=fs_calls;fm_proc();assert(fs_calls==before);
    relist();fm_close();assert(!list_state && closes==1);
    fail_path=1;before=alerts;go_up();assert(closes==2 && alerts==before+1 && !list_state);fail_path=0;
    for(unsigned char i=0;i<4;i++)contexts[i].active=1;
    filemgr_main();assert(closes==3); /* exhausted context pool quits cleanly */
    contexts[0].active=0;fail_path=1;filemgr_main();assert(closes==4 && !list_state);
    fm_test_config_length=513;cfg_load_view();assert(view==V_ICONS);
    puts("Actual File Manager: owned batches/navigation, shared menus/geometry, provider gates and errors PASS");
    return 0;
}
