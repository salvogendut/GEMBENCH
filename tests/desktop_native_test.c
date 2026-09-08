/* Actual Desktop, native leaves and gbdoc; only kernel/device calls mocked. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_CPC_RESTART
#define GB_PREEMPTIVE
#define GBDOC_MENU_ONLY
#define GB_DESKTOP_PROVIDER "platform/cpc.h"
#define main desktop_main
#include "../apps/desktop/main.c"
#undef main
#undef gb_wm_open
#undef gb_wm_full
#include "../kernel/kc/cpc_desktop.c"
#include "../lib/gb/gbdoc.c"

unsigned char host_menu[37],host_fullscreen,host_hour=8,host_minute=20,host_binary=1;
unsigned char host_ui_op,host_ui_col,host_ui_line,host_focus,host_windows=1,host_pages=26;
volatile gb_msg_t host_message;
static unsigned char flags,mx=76,my=185,popup_choice=255,modal,fail_open;
static unsigned int paints,damages,alerts,opens,ui_calls,collects,sends,frames,footprints;
static gb_owner_t endpoint;
static const gb_win_t *root_window;
static void (*root_bar)(void);
static char opened[12];
void desktop_start(const gb_win_t *desc,void (*bar)(void)) {root_window=desc;root_bar=bar;}
void desktop_collect(void) {collects++;}
unsigned char gb_flags(void) {return flags;}
unsigned char gb_mx(void) {return mx;}
unsigned char gb_my(void) {return my;}
void gb_curhide(void) {}
void gb_curshow(void) {}
void gb_fill(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{assert(x<80 && y<200 && (unsigned int)x+w<=80 && (unsigned int)y+h<=200 && pen<4);}
void gb_backdrop(unsigned char x,unsigned char y,unsigned char w,unsigned char h) {gb_fill(x,y,w,h,0);}
void gb_frame(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{gb_fill(x,y,w,h,pen);frames++;}
void gb_icon(unsigned char slot,unsigned char x,unsigned char y) {assert(slot<21 && x+8<=80 && y+32<=200);}
void gb_text(unsigned char x,unsigned char y,const char *text) {assert(x<80 && y+8<=200 && text);}
void gb_textbw(unsigned char x,unsigned char y,const char *text)
{gb_text(x,y,text);if(!strcmp(text,"15K used"))footprints++;}
void gb_time(void) {}
void gb_wm_damage(unsigned char x,unsigned char y,unsigned char w,unsigned char h)
{gb_fill(x,y,w,h,0);damages++;}
void gb_restore_parent(void) {paints++;}
unsigned char gb_wm_x(void) {return 0;}
unsigned char gb_wm_y(void) {return 0;}
unsigned char gb_wm_w(void) {return 80;}
unsigned char gb_wm_h(void) {return 200;}
void gb_menu(const void *raw) {const unsigned char *p=raw;memcpy(host_menu,p,1+p[0]*9);}
unsigned char gb_modal(void) {return modal;}
void gb_popup_close(void) {modal=0;}
unsigned char gb_popup(unsigned char x,unsigned char y,const char *const *items,unsigned char n)
{
    assert(y==8);
    if(x==10) {assert(n==2 && !strcmp(items[0],"Clock") && !strcmp(items[1],"Calculator"));}
    else {
        assert(x==17 && n==DESKTOP_SYSTEM_ITEM_COUNT && !strcmp(items[1],"Tidy Icons"));
#if DESKTOP_SETTINGS_READY
        assert(!strcmp(items[2],"Settings") && !strcmp(items[3],"About GEOBENCH"));
#else
        assert(!strcmp(items[2],"About GEOBENCH"));
#endif
    }
    return popup_choice;
}
void gb_alert(const char *a,const char *b) {assert(a && b);alerts++;}
unsigned char gb_ui(void) {assert(host_ui_op==24 && host_ui_col==10 && host_ui_line==69);ui_calls++;return 1;}
void gb_wm_open(const char *name) {opens++;memcpy(opened,name,11);if(!fail_open)host_focus=1;}
gb_owner_t gb_defer_find_accessory(unsigned char id) {assert(id==1 || id==2);return endpoint;}
unsigned char gb_defer_send(const gb_defer_send_t *msg)
{assert(msg->receiver==endpoint && msg->type==GB_DEFER_SHELL && msg->p0==GB_SHELL_ACTIVATE);sends++;return 0;}
static void menu_select(unsigned char col,unsigned char item)
{host_message.type=GB_MSG_MENU;host_message.p0=col;popup_choice=item;on_event();on_frame();popup_choice=255;}
static void click_icon(unsigned char which)
{
    mx=ic_x[which]+1;my=ic_y[which]+2;
    flags=GB_CLICK|GB_FIRE;on_frame();flags=0;on_frame();
    flags=GB_CLICK|GB_FIRE;on_frame();flags=0;on_frame();
}
int main(void)
{
    desktop_main();assert(root_window==&deskwin && root_bar==bar_draw && !paints);
    assert(root_window->y==0 && root_window->h==200 && !ic_present[IDX_TRASH]);
    assert(ic_present[0] && !ic_present[1] && !ic_present[2] && ic_present[3]);
    assert(ic_x[0]==0 && ic_y[0]==20 && ic_x[3]==66 && ic_y[3]==35);
    on_frame();assert(host_menu[0]==2 && host_menu[1]==10 && host_menu[10]==17);
    assert(!memcmp(host_menu+2,"Desk\0\0\0\0",8) && !memcmp(host_menu+11,"System\0\0",8));
    root_bar();assert(collects==1 && bar_init);
    unsigned char old_hour=bar_hour,old_min=bar_min;host_hour++;host_minute++;
    root_window->on_repaint();assert(bar_hour==old_hour && bar_min==old_min);
    root_bar();assert(bar_hour==host_hour && bar_min==host_minute);
    host_fullscreen=1;root_window->on_repaint();assert(!bar_wasfs);host_fullscreen=0;
    menu_select(10,1);assert(opens==1 && !memcmp(opened,"CALC    APP",11));
    endpoint=0x201;host_windows=8;host_pages=0;menu_select(10,0);assert(sends==1 && opens==1);
    endpoint=0;menu_select(10,0);assert(alerts==1 && opens==1);
    host_windows=1;host_pages=26;host_focus=0;fail_open=1;menu_select(10,0);
    assert(alerts==2 && opens==2);fail_open=0;
    ic_x[0]=20;ic_y[0]=80;ic_x[3]=50;menu_select(17,1);
    assert(ic_x[0]==0 && ic_y[0]==20 && ic_x[3]==66);
    menu_select(17,0);assert(show_ram);
    unsigned int prior_footprints=footprints;root_bar();assert(footprints==prior_footprints+1);
    root_bar();assert(footprints==prior_footprints+1); /* no repeated bar painting */
    root_window->on_repaint();assert(footprints==prior_footprints+2);
    menu_select(17,0);assert(!show_ram);
#if DESKTOP_SETTINGS_READY
    unsigned int settings_opens=opens;
    host_focus=0;menu_select(17,2);
    assert(!want_settings && opens==settings_opens+1 && !memcmp(opened,"SETTINGSBIN",11));
    host_windows=8;host_pages=0;menu_select(17,2);assert(opens==settings_opens+1);
    host_windows=1;host_pages=26;
    menu_select(17,3);
#else
    menu_select(17,2);
#endif
    assert(want_about==2 && !ui_calls);on_frame();assert(!want_about && ui_calls==1);
    unsigned int before=alerts,prior_opens=opens;
    host_focus=0;click_icon(IDX_C);
#if DESKTOP_FILEMGR_READY
    assert(alerts==before && opens==prior_opens+1 && !memcmp(opened,"FILEMGR BIN",11));
    desktop_open_disk(1);assert(alerts==before+1 && opens==prior_opens+1);
    host_focus=0;fail_open=1;desktop_open_disk(0);fail_open=0;
    assert(alerts==before+2 && opens==prior_opens+2);
#else
    assert(alerts==before+1 && opens==prior_opens);
#endif
    prior_opens=opens;host_focus=0;click_icon(IDX_CLOCK);
    assert(opens==prior_opens+1 && !memcmp(opened,"CLOCK   APP",11));
    select_icon(IDX_C);before=damages;unsigned int prior_frames=frames;
    desk_active=0;bar_draw();assert(sel_idx==NONE && damages>before && frames==prior_frames);
    host_message.type=GB_MSG_DROP;before=alerts;on_event();assert(alerts==before+1);
    puts("Actual Desktop: native startup, assets, shared Desk/System, owned activation, errors and clipped repair PASS");
    return 0;
}
