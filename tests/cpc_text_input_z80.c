/* Execute the real CPC matrix scan, translation and opt-in focus adapter. */
#include "z80.h"
#include "text_fixture.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static Z80 cpu;
static unsigned char ram[65536], banks[256][16384], rows[10];
static unsigned mapped=0xC5,row,checks,aperture_reads;
static unsigned char rd(void *unused,unsigned short a) {
    (void)unused;
    if(a>=0x4000 && a<0x8000) {++aperture_reads;return banks[mapped][a-0x4000];}
    return ram[a];
}
static void wr(void *unused,unsigned short a,unsigned char v) {
    (void)unused;
    assert(a<0x4000); /* only fixed input state / stack may change */
    ram[a]=v;
}
static unsigned char in(void *unused,unsigned short p) {
    (void)unused;assert((p>>8)==0xF4 && !cpu.iff1 && row<10);return rows[row];
}
static void out(void *unused,unsigned short p,unsigned char v) {
    (void)unused;assert(!cpu.iff1);
    if(p==0x7F00) {assert(v==0xC4 || v==0xC5);mapped=v;return;}
    assert((p>>8)==0xF4 || (p>>8)==0xF6 || (p>>8)==0xF7);
    if((p>>8)==0xF6 && v>=0x40 && v<=0x49)row=v-0x40;
}
static Z80Bus bus={.mem_read=rd,.mem_write=wr,.io_read=in,.io_write=out};
static void word(unsigned at,unsigned v) {ram[at]=v;ram[at+1]=v>>8;}
static void load(const char *dir,const char *name,unsigned base) {
    char path[1024];snprintf(path,sizeof(path),"%s/%s",dir,name);
    FILE *f=fopen(path,"rb");assert(f);assert(fread(ram+base,1,65536-base,f));fclose(f);
}
static void setup(unsigned flags,unsigned kind,unsigned ctrl,unsigned keyrow,unsigned bit) {
    memset(rows,255,10);rows[keyrow]&=~(1u<<bit);
    if(ctrl)rows[2]&=~0x80;
    ram[WM_FOCUS]=0;ram[WM_TABLE]=0xC4;ram[WM_TABLE+WM_FR_FLAGS]=flags;
    word(WM_TABLE+WM_FR_FRAME,0x5000);banks[0xC4][0x100C]=kind;
    ram[CPC_KEY_PREVIOUS]=ram[CPC_ESCAPE_HELD]=0;ram[SCHED_LOCK]=7;ram[SCHED_CURRENT]=0;
    ram[BANK_CUR]=mapped=0xC5;aperture_reads=0;
    memset(ram+0x3500,0xD7,0x110);
}
static unsigned invoke(unsigned entry,unsigned iff) {
    cpu.pc=entry;cpu.sp=0x35E0;word(cpu.sp,0x0030);
    cpu.iff1=cpu.iff2=iff;cpu.ix=0x1234;cpu.iy=0x5678;
    unsigned steps=0;
    while(cpu.pc!=0x0030 && ++steps<10000)z80_step(&cpu,&bus);
    assert(steps<10000 && cpu.sp==0x35E2);
    assert(cpu.iff1==iff && cpu.iff2==iff && mapped==0xC5 && ram[BANK_CUR]==0xC5);
    assert(cpu.ix==0x1234 && cpu.iy==0x5678 && ram[SCHED_LOCK]==7 && !ram[SCHED_CURRENT]);
    for(unsigned i=0x3500;i<0x3550;++i)assert(ram[i]==0xD7);
    ++checks;return cpu.a;
}
int main(int argc,char **argv) {
    assert(argc==2);memset(ram+0xC000,0xA5,0x4000);z80_init(&cpu);
    load(argv[1],"CORE.RAW",0x8000);load(argv[1],"SCHED.RAW",0x2900);
    load(argv[1],"SUPPORT.RAW",0x400);load(argv[1],"HARDWARE.RAW",0x3800);
    const unsigned kr[]={0,0,0,1,5},kb[]={0,1,2,0,7},ch[]={30,28,31,29,32};
    const unsigned flags[]={0,1,3,0x11,0x13};
    for(unsigned iff=0;iff<2;++iff)for(unsigned f=0;f<5;++f)
    for(unsigned kind=0;kind<2;++kind)for(unsigned ctrl=0;ctrl<2;++ctrl)
    for(unsigned key=0;key<5;++key) {
        unsigned text=flags[f]==0x13 && kind && !ctrl;
        setup(flags[f],kind?0x20:0,ctrl,kr[key],kb[key]);
        unsigned expected=key==4 ? (ctrl && flags[f]==0x13 && kind?0:32) : (text?ch[key]:0);
        assert(invoke(CPC_GETKEY,iff)==expected);
        assert(invoke(CPC_GETKEY,iff)==0); /* held-key suppression */
        if(flags[f]!=0x13 || (ctrl && key!=4))assert(!aperture_reads);
        /* A fresh scan precedes every pointer sample. Only text focus masks
         * its keyboard keys; joystick movement/fire remains independent. */
        rows[9]=0xEF;invoke(CPC_INPUT_SCAN,iff);invoke(CPC_TEXT_POINTER,iff);
        assert(ram[CPC_KEYS+9]==0xEF);
        assert(((ram[CPC_KEYS+kr[key]]>>kb[key])&1)==text);
        rows[kr[key]]|=1u<<kb[key];assert(invoke(CPC_GETKEY,iff)==0);
    }
    setup(0x13,0x20,0,0,0);ram[WM_FOCUS]=255;
    assert(!invoke(CPC_GETKEY,1) && !aperture_reads);
    /* Text GETKEY must neither deliver 27 nor steal the physical press:
     * chrome owns close/cancel, including when a frame sees Escape first. */
    for(unsigned iff=0;iff<2;++iff)for(unsigned first=0;first<2;++first) {
        setup(0x13,0x20,0,8,2);
        if(first)assert(invoke(CPC_GETKEY,iff)==0);
        invoke(CPC_INPUT_SCAN,iff);assert(invoke(CPC_ESCAPE_SAMPLE,iff)==4);
        for(unsigned i=0;i<80;++i) {
            ram[WM_FOCUS]=0;
            assert(invoke(CPC_GETKEY,iff)==0);
            ram[WM_FOCUS]=i&1; /* held GB_QUIT cannot reach another window */
            invoke(CPC_INPUT_SCAN,iff);assert(invoke(CPC_ESCAPE_SAMPLE,iff)==0);
        }
        ram[WM_FOCUS]=0;
        rows[8]|=4;invoke(CPC_INPUT_SCAN,iff);
        invoke(CPC_INPUT_SCAN,iff);assert(invoke(CPC_ESCAPE_SAMPLE,iff)==0);
        rows[8]&=~4;assert(invoke(CPC_GETKEY,iff)==0);
        invoke(CPC_INPUT_SCAN,iff);assert(invoke(CPC_ESCAPE_SAMPLE,iff)==4);
        rows[8]|=4;invoke(CPC_INPUT_SCAN,iff);assert(invoke(CPC_ESCAPE_SAMPLE,iff)==0);
        rows[8]&=~4;invoke(CPC_INPUT_SCAN,iff);assert(invoke(CPC_ESCAPE_SAMPLE,iff)==4);
        assert(invoke(CPC_GETKEY,iff)==0);
    }
    setup(0x13,0,0,8,2); /* Non-text native GETKEY keeps ASCII Escape. */
    assert(invoke(CPC_GETKEY,1)==27);
    assert(invoke(CPC_GETKEY,1)==0);
    for(unsigned i=0xC000;i<0x10000;++i)assert(ram[i]==0xA5);
    printf("CPC text input: %u Z80 calls PASS; focus/kind, arrows/Space/Ctrl, held keys, joystick, bank/IFF/registers/guards\n",checks);
    return 0;
}
