/* Real portable popup; mocked display/input, with bounded save-under checks. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../lib/gb/gbuniversal_menu.c"

static unsigned char guarded[770], next_flags, pointer_y, polls, saves, restores;
static unsigned char screen_height=200, saved_width, saved_height;
static unsigned char *saved_buffer;
unsigned char *gb_universal_popup_buffer(void) { return guarded+1; }
unsigned char gb_screen_lines(void) { return screen_height; }
void gb_curhide(void) { }
void gb_curshow(void) { }
unsigned char gb_mx(void) { return 12; }
unsigned char gb_my(void) { return pointer_y; }
unsigned char gb_poll(void) { assert(polls<3);return polls++ ? 0 : next_flags; }
void gb_saverect(unsigned char x,unsigned char y,unsigned char w,unsigned char h,void *p)
{
    assert(x==10 && y==8 && w*h<=768);
    ++saves;saved_width=w;saved_height=h;saved_buffer=p;memset(p,0x5A,w*h);
}
void gb_restorerect(unsigned char x,unsigned char y,unsigned char w,unsigned char h,const void *p)
{
    assert(x==10 && y==8 && w==saved_width && h==saved_height && p==saved_buffer);
    for(unsigned i=0;i<(unsigned)w*h;++i)assert(((const unsigned char *)p)[i]==0x5A);
    ++restores;
}
void gb_fill(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{ (void)pen;assert(x>=10 && x+w<=10+saved_width && y>=8 && y+h<=8+saved_height); }
void gb_frame(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{ gb_fill(x,y,w,h,pen); }
void gb_text_semantic(unsigned char x,unsigned char y,const char *s,unsigned char pen,unsigned char paper)
{
    (void)pen;(void)paper;
    assert(x==11 && x+text_columns(s)<=10+saved_width-1 && y+8<=8+saved_height-1);
}
static void reset(void)
{ memset(guarded,0xD7,sizeof(guarded));polls=saves=restores=0;next_flags=GB_CLICK; }
int main(void)
{
    const char *const labels[]={"New","Load","Save","Save As","Quit","Extra"};
    const char *const wide[]={"Too wide for five saved rows","Load","Save","Save As","Quit"};
    const unsigned char widths[]={0,9,10,10,15,14};
    for(unsigned char screen=0;screen<2;++screen) {
        screen_height=screen ? 212 : 200;
        for(unsigned char count=1;count<=5;++count)
        for(unsigned char row=0;row<count;++row) {
            reset();pointer_y=14+row*10;
            assert(gb_universal_popup(10,labels,count)==row);
            assert(saves==1 && restores==1 && !gb_universal_popup_active());
            assert(saved_width==widths[count] && saved_height==count*10+4);
            /* Largest tested File menu: 14 * 54 = 756 / 768 bytes. */
            assert(guarded[0]==0xD7 && guarded[769]==0xD7);
        }
    }
    reset();next_flags=GB_QUIT;assert(gb_universal_popup(10,labels,5)==255);
    assert(saves==1 && restores==1);
    reset();assert(gb_universal_popup(10,labels,6)==255 && !saves && !polls);
    assert(gb_universal_popup(10,labels,0)==255 && !saves && !polls);
    assert(gb_universal_popup(10,wide,5)==255 && !saves && !polls);
    puts("universal popup: five rows, all selections, cancellation and 768-byte bound PASS");
    return 0;
}
