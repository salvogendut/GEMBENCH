/* Portable data-page diagnostic. Normal media never stage this application.
 * One live data page is intentionally left for owner teardown; the next launch
 * receives its old handle through the already-qualified typed clipboard. */
#include "gbdatapage.h"
#include "gbscrap.h"
#include <string.h>
volatile unsigned char pageprobe_state[8];
static char input[512], output[514], token[4];
static gb_data_page_t a,b,extra[32];
static gb_params_t request;
static unsigned char arena[34];
#define HEADER (arena+8)
#define CHECK(x) do { if (++pageprobe_state[1]==0) ++pageprobe_state[2]; \
    if (!(x)) { pageprobe_state[0]=255; return; } } while (0)
static unsigned char boundary(unsigned int pointer,unsigned int size)
{
    memset(&request,0,sizeof(request));
    request.operation=GB_PARAMS_DATA_PAGES;request.version=GB_PARAMS_VERSION;
    request.data[0]=(unsigned char)pointer;request.data[1]=(unsigned char)(pointer>>8);
    request.data[2]=(unsigned char)size;request.data[3]=(unsigned char)(size>>8);
    return (unsigned char)(gb_parameters(&request)>>8);
}
static unsigned char wire(unsigned char op,unsigned int pointer,unsigned int size)
{
    memset(HEADER,0,16);HEADER[0]=op;
    HEADER[2]=(unsigned char)a;HEADER[3]=(unsigned char)(a>>8);
    HEADER[6]=(unsigned char)pointer;HEADER[7]=(unsigned char)(pointer>>8);
    HEADER[8]=(unsigned char)size;HEADER[9]=(unsigned char)(size>>8);
    if (boundary((unsigned int)HEADER,16)) return 255;
    return HEADER[1];
}
static void exercise(void)
{
    unsigned int i,block,got;
    unsigned char n=0,status;
    gb_scrap_info_t info;
    CHECK(gb_scrap_query(&info)==GB_SCRAP_OK);
    if (info.length==4 && info.type==GB_SCRAP_TEXT) {
        CHECK(gb_scrap_get(GB_SCRAP_TEXT,token,4,&got)==GB_SCRAP_OK && got==4);
        if (token[0]=='P' && token[1]=='G') {
            a=(unsigned char)token[2] | ((unsigned int)(unsigned char)token[3]<<8);
            status=gb_data_page_read(a,0,output+1,1);
            CHECK(status==GB_DATA_PAGE_STALE || status==GB_DATA_PAGE_FREE);
            pageprobe_state[4]=1;
        }
    }
    a=gb_data_page_alloc();CHECK(a && gb_data_page_status()==GB_DATA_PAGE_OK);
    b=gb_data_page_alloc();CHECK(b && b!=a);
    output[0]=output[513]=0x55;
    for (block=0;block<32;++block) {
        for(i=0;i<512;++i) input[i]=(char)(i*13+block);
        CHECK(gb_data_page_write(a,block*512,input,512)==0);
    }
    for (block=0;block<32;++block) {
        CHECK(gb_data_page_read(a,block*512,output+1,512)==0);
        for(i=0;i<512;++i) if ((unsigned char)output[i+1]!=(unsigned char)(i*13+block)) break;
        CHECK(i==512 && output[0]==0x55 && output[513]==0x55);
    }
    CHECK(gb_data_page_write(b,16383,"Z",1)==0);
    CHECK(gb_data_page_read(b,16383,output+1,1)==0 && output[1]=='Z');
    CHECK(gb_data_page_read(a,16384,0,0)==0);
    CHECK(gb_data_page_read(a,16385,0,0)==GB_DATA_PAGE_BADARG);
    CHECK(gb_data_page_read(a,16384,output+1,1)==GB_DATA_PAGE_BADARG);
    CHECK(gb_data_page_write(a,65535,input,2)==GB_DATA_PAGE_BADARG);
    CHECK(gb_data_page_write(a,0,input,513)==GB_DATA_PAGE_BADARG);
    CHECK(boundary(0x3FFF,16)==GB_PARAMS_BADARG);
    CHECK(boundary(0x7EF1,16)==GB_PARAMS_BADARG);
    CHECK(boundary(0xFFF0,16)==GB_PARAMS_BADARG);
    CHECK(boundary((unsigned int)HEADER,15)==GB_PARAMS_BADARG);
    CHECK(wire(2,0x3FFF,2)==GB_DATA_PAGE_BADARG);
    CHECK(wire(3,0x7EFF,2)==GB_DATA_PAGE_BADARG);
    CHECK(wire(2,0xFFFF,2)==GB_DATA_PAGE_BADARG);
    CHECK(wire(2,(unsigned int)HEADER,1)==GB_DATA_PAGE_BADARG);
    CHECK(wire(3,(unsigned int)HEADER-1,2)==GB_DATA_PAGE_BADARG);
    CHECK(wire(2,(unsigned int)HEADER+15,1)==GB_DATA_PAGE_BADARG);
    CHECK(wire(2,(unsigned int)HEADER-1,1)==0);
    CHECK(wire(2,(unsigned int)HEADER+16,1)==0);
    CHECK(gb_data_page_free(b)==0);
    CHECK(gb_data_page_read(b,0,output+1,1)==GB_DATA_PAGE_FREE);
    CHECK(gb_data_page_free(b)==GB_DATA_PAGE_FREE);
    extra[0]=gb_data_page_alloc();CHECK(extra[0] && extra[0]!=b);
    CHECK(gb_data_page_read(b,0,output+1,1)==GB_DATA_PAGE_STALE);
    CHECK(gb_data_page_free(extra[0])==0);
    while(n<32) { extra[n]=gb_data_page_alloc();if(!extra[n]) break;++n; }
    CHECK(n<32 && gb_data_page_status()==GB_DATA_PAGE_NOMEM);
    pageprobe_state[3]=n;
    while(n) { --n;CHECK(gb_data_page_free(extra[n])==0); }
    CHECK(gb_data_page_read(a,16383,output+1,1)==0 && (unsigned char)output[1]==18);
    token[0]='P';token[1]='G';token[2]=(char)a;token[3]=(char)(a>>8);
    CHECK(gb_scrap_set(GB_SCRAP_TEXT,token,4)==GB_SCRAP_OK);
    pageprobe_state[5]=(unsigned char)a;pageprobe_state[6]=(unsigned char)(a>>8);
    pageprobe_state[0]=85;
}
static void proc(void)
{
    gb_msg_t m;gb_rect_t r;
    gb_message_read(&m);
    if(m.type==GB_MSG_DRAW) {
        gb_window_rect(&r);gb_fill(r.x+1,r.y+14,r.w-2,r.h-15,GB_UI_SURFACE);
        gb_textbw(r.x+4,r.y+22,pageprobe_state[0]==85 ? "DATA PAGES PASS" : "DATA PAGES FAIL");
    } else if(m.type==GB_MSG_CLOSE) gb_wm_close();
}
static gb_mwin_t window={11,66,58,50,0,0,proc,"Portable data pages",0};
void main(void)
{
    if(!gb_universal_ready())return;
    pageprobe_state[0]=1;exercise();gb_wm_managed(&window);gb_restore_parent();
}
