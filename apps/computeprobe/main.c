#include "gbcompute.h"
#include <string.h>
volatile unsigned char computeprobe_state[8];
static unsigned char block[514];
static gb_params_t request;
static const unsigned int sizes[]={1,2,15,16,255,256,511,512};
#define CHECK(x) do { ++computeprobe_state[1]; if (!(x)) { computeprobe_state[0]=255;return; } } while (0)
static void exercise(void)
{
    unsigned char round,n,serial=0;
    unsigned int i,length;
    for(round=0;round<2;++round)for(n=0;n<8;++n) {
        length=sizes[n];
        for(i=0;i<514;++i)block[i]=(unsigned char)(i*13);
        CHECK(gb_compute(block+1,length)==GB_PARAMS_OK);
        ++serial;
        CHECK(block[1]==serial && (length<2 || block[2]==0x5A));
        for(i=2;i<length;++i)if(block[i+1]!=(unsigned char)(((i+1)*13)^0xA5))break;
        CHECK(i>=length && block[0]==0 && block[length+1]==(unsigned char)((length+1)*13));
    }
    CHECK(gb_compute(block+1,0)==GB_PARAMS_BADARG);
    CHECK(gb_compute(block+1,513)==GB_PARAMS_BADARG);
    memset(&request,0,sizeof(request));
    request.operation=GB_PARAMS_SECONDARY_CALL;request.version=GB_PARAMS_VERSION;
    request.data[0]=255;request.data[1]=63;request.data[2]=1;
    CHECK((gb_parameters(&request)>>8)==GB_PARAMS_BADARG);
    request.data[0]=255;request.data[1]=126;request.data[2]=2;
    CHECK((gb_parameters(&request)>>8)==GB_PARAMS_BADARG);
    request.data[0]=0;request.data[1]=96;request.data[2]=1;request.data[4]=1;
    CHECK((gb_parameters(&request)>>8)==GB_PARAMS_BADARG);
    CHECK(gb_compute(block+1,512)==GB_PARAMS_OK && block[1]==17 && block[2]==0x5A);
    computeprobe_state[0]=85;
}
static void proc(void)
{
    gb_msg_t m;gb_rect_t r;
    gb_message_read(&m);
    if(m.type==GB_MSG_DRAW) {
        gb_window_rect(&r);gb_fill(r.x+1,r.y+14,r.w-2,r.h-15,GB_UI_SURFACE);
        gb_textbw(r.x+4,r.y+22,computeprobe_state[0]==85 ? "SEALED CALLS PASS" : "SEALED CALLS FAIL");
    } else if(m.type==GB_MSG_CLOSE)gb_wm_close();
}
static gb_mwin_t window={11,66,58,50,0,0,proc,"Portable computation",0};
void main(void)
{
    if(!gb_universal_ready())return;
    computeprobe_state[0]=1;exercise();gb_wm_managed(&window);gb_restore_parent();
}
