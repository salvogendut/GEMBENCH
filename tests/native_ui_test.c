#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../lib/gb/gb.h"
static unsigned char request[256], saved[4864], status, choice;
static unsigned int width, height, draws, saves, restores, pops, prompts, polls;
static unsigned char sx,sy,sw,sh;
#define GBUI_BASIC_ONLY
#define GB_UI_PROVIDER "../../tests/native_ui_provider.h"
#define main native_ui_main
#include "../kernel/kc/gbui_mod.c"
#undef main
void gb_curhide(void) { }
void gb_curshow(void) { }
void gb_fill(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{ (void)x;(void)y;(void)w;(void)h;(void)pen;draws++; }
void gb_frame(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{ (void)x;(void)y;(void)w;(void)h;(void)pen;draws++; }
void gb_textbw(unsigned char x,unsigned char y,const char *s) { (void)x;(void)y;assert(s);draws++; }
unsigned char gb_poll(void) { return ++polls==2 ? GB_QUIT : 0; }
unsigned char gb_getkey(void) { return 0; }
unsigned char gb_mx(void) { return 0; }
unsigned char gb_my(void) { return 0; }
void gb_saverect(unsigned char x,unsigned char y,unsigned char w,unsigned char h,void *buf)
{ assert(buf==saved && (unsigned int)w*h<=sizeof(saved)); sx=x;sy=y;sw=w;sh=h;saves++; }
void gb_restorerect(unsigned char x,unsigned char y,unsigned char w,unsigned char h,const void *buf)
{ assert(buf==saved && x==sx && y==sy && w==sw && h==sh);restores++; }
unsigned char gb_popup(unsigned char x,unsigned char y,const char *const *labels,unsigned char n)
{ assert(x<GB_COLS && y<GB_LINES && n && labels[0] && choice<n);pops++;return choice; }
unsigned char gb_prompt(const char *caption,char *buf,unsigned char maxlen)
{ assert(caption && maxlen<=12);prompts++;strcpy(buf,"ABC");return choice; }
static void reset(unsigned char op)
{ memset(request,0,sizeof(request));status=99;UI_OP=op;draws=saves=restores=pops=prompts=polls=0; }
static void rejected(void)
{ native_ui_main();assert(status==2 && !draws && !saves && !pops && !prompts && !polls); }
int main(void)
{
    reset(1);UI_N=2;UI_COL=10;UI_LINE=8;memcpy(UI_TEXT,"One\0Two",8);choice=1;
    native_ui_main();assert(status==0 && UI_RES==1 && pops==1 && !saves);
    reset(6);UI_N=1;UI_LINE=8;strcpy(UI_TEXT,"Disabled");UI_NAME[0]=1;choice=0;
    native_ui_main();assert(status==0 && UI_RES==255 && pops==1);
    reset(2);UI_N=12;strcpy(UI_TEXT,"Name:");choice=1;
    native_ui_main();assert(status==0 && UI_RES==1 && !memcmp(UI_NAME,"ABC\0",4));
    assert(saves==1 && restores==1 && sw==52 && sh==34);
    reset(2);UI_N=12;strcpy(UI_TEXT,"Name:");choice=0;
    native_ui_main();assert(status==0 && !UI_RES && saves==1 && restores==1);
    reset(24);UI_COL=10;UI_LINE=69;native_ui_main();
    assert(status==0 && saves==1 && restores==1 && sw==60 && sh==62 && pops==1);
    reset(25);width=320;height=200;native_ui_main();
    assert(status==0 && !UI_RES && saves==1 && restores==1 && width==320 && height==200);
    for (unsigned char op=3;op<=8;op++) if (op!=6) { reset(op);rejected(); }
    reset(1);rejected(); /* zero rows */
    reset(1);UI_N=GB_UI_POPUP_MAX+1;rejected();
    reset(1);UI_N=GB_UI_POPUP_MAX;UI_LINE=110;choice=GB_UI_POPUP_MAX-1;
    memcpy(UI_TEXT,"SOLID",6);
    for (unsigned char i=1;i<GB_UI_POPUP_MAX;i++) memcpy(UI_TEXT+6+(i-1)*11,"C:12345678",11);
    native_ui_main();assert(status==0 && UI_RES==choice && pops==1);
    reset(6);UI_N=9;rejected();
    reset(1);UI_N=1;memset(UI_TEXT,'X',232);rejected();
    reset(1);UI_N=1;UI_COL=79;strcpy(UI_TEXT,"Wide");rejected();
    reset(1);UI_N=1;UI_LINE=250;strcpy(UI_TEXT,"Bad");rejected();
    reset(1);UI_N=1;UI_LINE=245;strcpy(UI_TEXT,"Bad");rejected();
    reset(2);UI_N=128|12;strcpy(UI_TEXT,"Bad");rejected();
    reset(24);UI_COL=21;UI_LINE=69;rejected();
    reset(24);UI_COL=10;UI_LINE=139;rejected();
    puts("shared native UI: dispatch, bounds, cancel, save-under and unsupported operations PASS");
    return 0;
}
