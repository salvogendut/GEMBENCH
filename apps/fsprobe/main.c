/* Diagnostic APP: writes ONLY its disposable UFSTEST/RESULT.BIN fixture.
 * One artifact on both machines; runners observe exported results, never seed RAM. */
#include "gbuniversal.h"
#include "gbfsctx.h"

volatile unsigned char fsprobe_state[8];
static char buffer[512];
static gb_params_t request;
static unsigned char header[32];
static unsigned char transfer[512];
static gb_fsctx_t first, second, third, fourth;

#define CHECK(x) do { ++fsprobe_state[1]; if (!(x)) { fsprobe_state[0]=255; return; } } while (0)

static unsigned char pattern(unsigned int start, unsigned int count)
{
    unsigned int i;
    for (i=0; i<count; ++i)
        if ((unsigned char)buffer[i] != (unsigned char)((start+i)*13u+7u)) return 0;
    return 1;
}
static void word(unsigned char offset, unsigned int value)
{
    request.data[offset]=(unsigned char)value;
    request.data[offset+1]=(unsigned char)(value>>8);
}
static unsigned char boundary(unsigned int hp, unsigned int hs,
                              unsigned int tp, unsigned int ts)
{
    request.operation=GB_PARAMS_FILESYSTEM; request.version=GB_PARAMS_VERSION;
    word(0,hp); word(2,hs); word(4,tp); word(6,ts);
    return (unsigned char)(gb_parameters(&request)>>8);
}
static void exercise(void)
{
    unsigned int got, kib, i;
    unsigned char n;
    gb_fsctx_entry_t entry;
    const gb_fsctx_entry_t *batch;
    CHECK(boundary(0x3FFF,32,(unsigned int)transfer,512)==GB_PARAMS_BADARG);
    CHECK(boundary(0x7EE1,32,(unsigned int)transfer,512)==GB_PARAMS_BADARG);
    CHECK(boundary((unsigned int)header,31,(unsigned int)transfer,512)==GB_PARAMS_BADARG);
    CHECK(boundary((unsigned int)header,32,0x7D01,512)==GB_PARAMS_BADARG);
    CHECK(boundary((unsigned int)header,32,0xFFF0,512)==GB_PARAMS_BADARG);
    CHECK(boundary((unsigned int)header,32,(unsigned int)transfer,511)==GB_PARAMS_BADARG);
    CHECK(boundary((unsigned int)transfer,32,(unsigned int)transfer,512)==GB_PARAMS_BADARG);
    CHECK(boundary((unsigned int)transfer+500,32,(unsigned int)transfer,512)==GB_PARAMS_BADARG);
    header[0]=15;
    CHECK(boundary((unsigned int)header,32,(unsigned int)transfer,512)==GB_PARAMS_BADARG);
    first=gb_fsctx_open(0); CHECK(first);
    second=gb_fsctx_open(0); CHECK(second && second!=first);
    CHECK(gb_fsctx_set_path(first,"/UFSTEST")==0);
    CHECK(gb_fsctx_set_path(second,"/UFSTEST/SUB")==0);
    CHECK(gb_fsctx_set_name(first,"SOURCE  BIN")==0);
    CHECK(gb_fsctx_set_name(second,"SMALL   TXT")==0);
    got=gb_fsctx_read(first,buffer,128); CHECK(got==128 && pattern(0,128));
    got=gb_fsctx_read(second,buffer,512); CHECK(got==3 && buffer[0]=='O' && buffer[1]=='K' && buffer[2]=='!');
    got=gb_fsctx_read(first,buffer,512); CHECK(got==512 && pattern(128,512));
    got=gb_fsctx_read(first,buffer,512); CHECK(got==385 && pattern(640,385));
    CHECK(gb_fsctx_read(first,buffer,512)==0 && gb_fsctx_status()==0);
    CHECK(gb_fsctx_rewind(first)==0);
    CHECK(gb_fsctx_read(first,buffer,512)==512 && pattern(0,512));
    CHECK(gb_fsctx_dir_first(second,&entry) && entry.size==3);
    CHECK(!gb_fsctx_dir_next(second,&entry) && gb_fsctx_status()==0);
    n=gb_fsctx_dir_batch(first,1); CHECK(n==2 || n==3); /* RESULT may exist on a repeat */
    batch=gb_fsctx_batch_entries();
    CHECK((batch[0].attributes & GB_FSCTX_ATTR_DIRECTORY) || (batch[1].attributes & GB_FSCTX_ATTR_DIRECTORY));
    CHECK(gb_fsctx_dir_batch(first,0)==0 && gb_fsctx_status()==0);
    CHECK(gb_fsctx_free_kib(first,&kib));
    fsprobe_state[2]=(unsigned char)kib; fsprobe_state[3]=(unsigned char)(kib>>8);
    CHECK(gb_fsctx_set_name(first,"RESULT  BIN")==0);
    CHECK(gb_fsctx_rewind(first)==0);
    for(i=0;i<512;++i) buffer[i]=(char)(i*13u+7u);
    CHECK(gb_fsctx_write(first,buffer,512)==0);
    CHECK(gb_fsctx_write(first,"END",3)==0);
    CHECK(gb_fsctx_rewind(first)==0);
    CHECK(gb_fsctx_read(first,buffer,512)==512 && pattern(0,512));
    CHECK(gb_fsctx_read(first,buffer,512)==3 && buffer[0]=='E' && buffer[1]=='N' && buffer[2]=='D');
    CHECK(gb_fsctx_rewind(first)==0);
    CHECK(gb_fsctx_write(first,"",0)==0);
    CHECK(gb_fsctx_read(first,buffer,512)==0 && gb_fsctx_status()==0);
    CHECK(gb_fsctx_write(first,"DONE",4)==0);
    third=gb_fsctx_open(0); fourth=gb_fsctx_open(0); CHECK(third && fourth);
    CHECK(gb_fsctx_open(0)==0 && gb_fsctx_status()==GB_FSCTX_ERR_FULL);
    CHECK(gb_fsctx_close(third)==0);
    CHECK(gb_fsctx_cancel(third)==GB_FSCTX_ERR_STALE);
    CHECK(gb_fsctx_close(fourth)==0);
    CHECK(gb_fsctx_close(first)==0);
    CHECK(gb_fsctx_close(second)==0);
    fsprobe_state[0]=85;
}
static void draw(void)
{
    gb_rect_t r; gb_window_rect(&r);
    gb_fill(r.x+1,r.y+14,r.w-2,r.h-15,GB_UI_SURFACE);
    gb_textbw(r.x+4,r.y+22,fsprobe_state[0]==85 ? "FILESYSTEM PASS" : "FILESYSTEM FAIL");
}
static void proc(void)
{
    gb_msg_t m; gb_message_read(&m);
    if(m.type==GB_MSG_DRAW) draw();
    if(m.type==GB_MSG_CLOSE) gb_wm_close();
}
static gb_mwin_t window={11,66,58,50,0,0,proc,"Portable FS"};
void main(void)
{
    if(!gb_universal_ready()) return;
    fsprobe_state[0]=1;
    exercise();
    gb_wm_managed(&window);
    gb_restore_parent();
}
