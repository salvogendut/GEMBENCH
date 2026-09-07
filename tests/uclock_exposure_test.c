/* Actual portable Clock with a clipped software surface and device stubs. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define GB_UNIVERSAL
#define GB_UNIVERSAL_HOST_TEST
#define main uclock_main
#include "../apps/uclock/main.c"
#undef main

static unsigned char pixels[200][320], expected[200][320];
static unsigned int left=0, right=320, top=0, bottom=200, reads;
static gb_time_snapshot_t now={0,1,16,1};
static gb_rect_t rect={51,20,28,122};
static void dot(unsigned int x,unsigned int y,unsigned char pen)
{if(x>=left && x<right && y>=top && y<bottom) pixels[y][x]=pen;}
void gb_fill(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{for(unsigned int yy=y;yy<(unsigned int)y+h;yy++) for(unsigned int xx=x*4u;xx<(x+w)*4u;xx++) dot(xx,yy,pen);}
void gb_line(unsigned int x0,unsigned int y0,unsigned int x1,unsigned int y1,unsigned char pen)
{
    int x=x0,y=y0,dx=abs((int)x1-x),dy=abs((int)y1-y),sx=x<(int)x1?1:-1,sy=y<(int)y1?1:-1,e=dx-dy;
    for(;;) {dot(x,y,pen);if(x==(int)x1 && y==(int)y1)break;int twice=2*e;if(twice>=-dy){e-=dy;x+=sx;}if(twice<=dx){e+=dx;y+=sy;}}
}
void gb_text_semantic(unsigned char x,unsigned char y,const char *text,unsigned char pen,unsigned char paper)
{for(unsigned int i=0;text[i];i++) for(unsigned int yy=0;yy<8;yy++) for(unsigned int xx=0;xx<6;xx++) dot(x*4u+i*6u+xx,y+yy,(text[i]&(1u<<xx))?pen:paper);}
void gb_window_rect(gb_rect_t *out) {*out=rect;}
void gb_time_read(gb_time_snapshot_t *out) {*out=now;reads++;}
void gb_time_observe(gb_time_snapshot_t *out) {*out=now;}
unsigned char gb_timer_take_dropped(gb_window_t window) {(void)window;return 0;}
unsigned char gb_timer_active_for(gb_window_t window) {(void)window;return 0;}
void gb_timer_cancel(gb_window_t window) {(void)window;}

static void fresh_matches(void)
{
    memcpy(expected,pixels,sizeof(pixels));have_prev=0;draw();
    assert(!memcmp(expected,pixels,sizeof(pixels)));
}
int main(void)
{
    aspect_x=256;show_sec=1;clock_window_handle=0x101;
    draw();assert(ps==16 && ds==16 && have_prev);
    /* The exposed strip excludes the old second-hand endpoint on the right. */
    left=51*4;right=60*4;top=26;bottom=184;now.second=17;
    unsigned int before=reads;draw();
    assert(ps==16 && ds==16 && reads==before);
    left=0;right=320;top=0;bottom=200;now.second=18;focused_tick();
    assert(ps==18 && ds==18);fresh_matches();

    /* A completed hand pass can precede its digital pass when exposure occurs. */
    ds=17;draw_digital(0,1,17);timer_digit_due=1;
    left=51*4;right=60*4;top=26;bottom=184;draw();
    assert(ps==18 && ds==17 && timer_digit_due);
    left=0;right=320;top=0;bottom=200;focused_tick();
    assert(ds==18 && !timer_digit_due);fresh_matches();
    before=reads;have_prev=0;now.minute=2;draw();
    assert(pm==2 && dm==2 && reads==before+1);
    puts("Portable Clock: clipped exposure preserves completed caches, focused catch-up erases old pixels PASS");
    return 0;
}
