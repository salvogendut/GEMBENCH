#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_COLS 80
#define CLK_COL 68
#define KCFG_MEMSTR "512K"
static unsigned char menu[37], fullscreen;
#define MENU_DEF menu
#define WM_FS (&fullscreen)
static unsigned char gb_hour, gb_min, gb_binmode=1, ss_lmx, ss_lmy;
static unsigned int ss_idle, menu_draws;
static unsigned char full_clip=1;
static char published[9];
static void gb_time(void) {}
static void gb_curhide(void) {}
static void gb_curshow(void) {}
static unsigned char gb_mx(void) { return 0; }
static unsigned char gb_my(void) { return 0; }
static void gb_fill(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{ (void)x;(void)y;(void)w;(void)h;(void)pen; }
static void gb_textbw(unsigned char x,unsigned char y,const char *text)
{
    (void)y;
    if (x==10 && full_clip) { strcpy(published,text); ++menu_draws; }
}
#include "../apps/desktop/core/bar_render.inc"
void cpc_bar_reset(void) { bar_init=bar_wasfs=0; }
void cpc_bar_tick(void)
{
    unsigned char msig,i;
#include "../apps/desktop/core/bar_refresh.inc"
}
#include "../kernel/kc/cpc_bar_damage.inc"
int main(void)
{
    unsigned char oldsig;
    menu[0]=1;menu[1]=10;memcpy(menu+2,"Desk",5);
    cpc_bar_tick();assert(strcmp(published,"Desk")==0);
    oldsig=bar_msig;
    memcpy(menu+2,"Edit",5);gb_min=1;full_clip=0;
    cpc_bar_damage();
    assert(strcmp(published,"Desk")==0); /* exposure did not own the title */
    assert(bar_init==1 && bar_msig==oldsig && bar_min==0);
    full_clip=1;cpc_bar_tick();
    assert(strcmp(published,"Edit")==0 && bar_min==1 && menu_draws==2);
    cpc_bar_tick();assert(menu_draws==2); /* unchanged full bar is still cheap */
    puts("CPC clipped bar repair preserves full-bar cache: PASS");
    return 0;
}
