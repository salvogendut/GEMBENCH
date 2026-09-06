/* Execute the actual Desktop fragments with a recording presentation leaf. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#define GB_COLS TEST_COLUMNS
#define CLK_COL (GB_COLS - 12)
#define KCFG_MEMSTR "512K"
static unsigned char menu[37], fullscreen;
#define MENU_DEF menu
#define WM_FS (&fullscreen)
static unsigned char gb_hour, gb_min, gb_binmode = 1;
static unsigned int ss_idle;
static unsigned char ss_lmx, ss_lmy;
static unsigned int fills, texts, hides, shows, times;
static unsigned char fill_x, fill_y, fill_w, fill_h, text_x;
static char last_text[16];
static void gb_curhide(void) { ++hides; }
static void gb_curshow(void) { ++shows; }
static void gb_time(void) { ++times; }
static unsigned char gb_mx(void) { return 23; }
static unsigned char gb_my(void) { return 42; }
static void gb_fill(unsigned char x, unsigned char y, unsigned char w,
                    unsigned char h, unsigned char pen)
{
    assert(pen == 1); ++fills; fill_x=x; fill_y=y; fill_w=w; fill_h=h;
}
static void gb_textbw(unsigned char x, unsigned char y, const char *s)
{
    assert(y == 0); ++texts; text_x=x;
    assert(strlen(s) < sizeof(last_text)); strcpy(last_text, s);
}
#include "../apps/desktop/core/bar_render.inc"
static void tick(void)
{
    unsigned char msig, i;
#include "../apps/desktop/core/bar_refresh.inc"
}
static void clear_trace(void) { fills=texts=hides=shows=times=0; }

int main(void)
{
    gb_hour=9; gb_min=7;
    tick();
    assert(fills == 2 && texts == 2 && hides == shows && hides == 3);
    assert(text_x == CLK_COL && !strcmp(last_text, "09:07"));
    clear_trace(); tick();
    assert(times == 1 && !fills && !texts && !hides && !shows);
    ++gb_min; clear_trace(); tick();
    assert(!fills && texts == 1 && hides == 1 && shows == 1);
    assert(text_x == CLK_COL && !strcmp(last_text, "09:08"));
    menu[0]=1; menu[1]=10; memcpy(menu+2, "Tools", 6);
    clear_trace(); tick();
    assert(fills == 1 && texts == 1 && hides == 1 && shows == 1);
    assert(fill_x == 8 && fill_y == 0 && fill_w == 46 && fill_h == 8);
    assert(text_x == 10 && !strcmp(last_text, "Tools"));
    menu[0]=0; clear_trace(); tick();
    assert(fills == 1 && !texts); /* focus with no menu clears previous labels */
    fullscreen=1; ++gb_min; clear_trace(); tick();
    assert(times == 1 && !fills && !texts && !hides && !shows);
    fullscreen=0; ss_idle=99; clear_trace(); tick();
    assert(fills == 2 && texts == 2 && ss_idle == 0 && ss_lmx == 23 && ss_lmy == 42);
    gb_binmode=0; gb_hour=0x23; gb_min=0x59; clear_trace(); tick();
    assert(!fills && texts == 1 && !strcmp(last_text, "23:59"));
    assert(hides == shows);
    puts("shared Desktop bar: initial, idle, minute, focus, fullscreen, BCD PASS");
    return 0;
}
