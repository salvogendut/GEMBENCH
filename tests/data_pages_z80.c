/* Execute the actual shared page policy on the 1983 CPU core. The only fake
 * hardware is a banked aperture and its mapping port. Not full-emulator proof. */
#include "z80.h"
#include "fixture.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned char fixed[65536], pages[32][16384], mapped=16;
static unsigned char before_pages[32][16384];
static unsigned long maps, checks;
static Z80 cpu;
static unsigned char rd(void *c,unsigned short a)
{ (void)c; return a>=0x4000 && a<0x8000 ? pages[mapped-16][a-0x4000] : fixed[a]; }
static void wr(void *c,unsigned short a,unsigned char v)
{ (void)c; if (a>=0x4000 && a<0x8000) pages[mapped-16][a-0x4000]=v; else fixed[a]=v; }
static unsigned char in(void *c,unsigned short a) { (void)c;(void)a;assert(0);return 0; }
static void out(void *c,unsigned short a,unsigned char v)
{ (void)c;assert((a&255)==254 && v>=16 && v<48);mapped=v;++maps; }
static Z80Bus bus={.mem_read=rd,.mem_write=wr,.io_read=in,.io_write=out};
static void word(unsigned short a,unsigned short v) { wr(0,a,v);wr(0,a+1,v>>8); }
static unsigned short readword(unsigned short a) { return rd(0,a)+256u*rd(0,a+1); }
static void invoke(unsigned short address,unsigned short size)
{
    unsigned char prior=mapped; unsigned long guard=0;
    bool iff=checks&1; unsigned char lock=(checks&2) ? 7 : 0;
    cpu.hl=address;cpu.bc=size;cpu.pc=ENTRY;cpu.sp=0xF800;
    word(0xF800,0x0200);cpu.ix=0x1234;cpu.iff1=cpu.iff2=iff;fixed[LOCK]=lock;
    while(cpu.pc!=0x0200 && ++guard<1000000) z80_step(&cpu,&bus);
    assert(guard<1000000 && cpu.sp==0xF802 && cpu.ix==0x1234);
    assert(cpu.iff1==iff && cpu.iff2==iff && mapped==prior);
    assert(fixed[DATA_MAPPED]==prior && fixed[LOCK]==lock);++checks;
}
static unsigned char request(unsigned char op,unsigned short handle,unsigned short off,
                              unsigned short pointer,unsigned short length)
{
    for(unsigned i=0;i<16;++i) wr(0,0x7000+i,0);
    wr(0,0x7000,op);word(0x7002,handle);word(0x7004,off);word(0x7006,pointer);word(0x7008,length);
    memcpy(before_pages,pages,sizeof(pages));unsigned long prior_maps=maps;
    invoke(0x7000,16);unsigned char status=rd(0,0x7001);
    if(status) {
        assert(maps==prior_maps);
        for(unsigned i=0;i<32;++i) {
            if(i==(unsigned)(mapped-16)) {
                assert(!memcmp(before_pages[i],pages[i],0x3000));
                assert(!memcmp(before_pages[i]+0x3010,pages[i]+0x3010,0xFF0));
            } else assert(!memcmp(before_pages[i],pages[i],16384));
        }
    }
    return status;
}
static void init(void)
{
    memset(pages,0x69,sizeof(pages));
    fixed[CORE_PAGE_TOTAL]=6;
    for(unsigned i=0;i<6;++i) fixed[CORE_PAGE_NATIVE+i]=16+i;
    for(unsigned i=0;i<2;++i) {
        fixed[CORE_OWNER_ACTIVE+i]=fixed[CORE_OWNER_GEN+i]=1;
        fixed[CORE_APP_CODE_NATIVE+i]=16+i;
        fixed[CORE_PAGE_STATE+i]=fixed[CORE_PAGE_GEN+i]=1;
        fixed[CORE_PAGE_OWNER+i]=i+1;fixed[CORE_PAGE_OWNER_GEN+i]=1;
        fixed[CORE_PAGE_PURPOSE+i]=1;fixed[CORE_LEGACY_BUSY+i]=1;
    }
    word(OWNER,0x0101);fixed[DATA_MAPPED]=mapped=16;
}
int main(int argc,char **argv)
{
    assert(argc==2);FILE *f=fopen(argv[1],"rb");assert(f);
    assert(fread(fixed+0x8000,1,0x4000,f)>0 && !ferror(f));fclose(f);z80_init(&cpu);init();
    assert(!request(0,0,0,0,0));unsigned short page=readword(0x7002);assert(page==0x0103);
    for(unsigned block=0;block<32;++block) {
        for(unsigned i=0;i<512;++i) wr(0,0x6000+i,(i*13+block)&255);
        assert(!request(3,page,block*512,0x6000,512));
    }
    for(unsigned block=0;block<32;++block) {
        assert(!request(2,page,block*512,0x6000,512));
        for(unsigned i=0;i<512;++i) assert(rd(0,0x6000+i)==((i*13+block)&255));
    }
    unsigned long before=maps;
    assert(!request(2,page,16384,0xFFFF,0));assert(!request(3,page,0,0,0));assert(maps==before);
    assert(request(2,page,16385,0,0)==6);
    assert(request(2,page,16384,0x6000,1)==6);
    assert(request(3,page,0xFFFF,0x6000,2)==6);
    assert(request(2,page,0,0x6000,513)==6);
    unsigned short bad[]={0,0x3FFF,0x7EFF,0xFFFF,0x7000,0x6FFF,0x700F};
    for(unsigned i=0;i<sizeof(bad)/sizeof(bad[0]);++i) {
        assert(request(2,page,0,bad[i],2)==6);assert(request(3,page,0,bad[i],2)==6);
    }
    assert(!request(3,page,16383,0x6FFF,1));assert(!request(2,page,16383,0x7010,1));
    assert(request(2,0x0101,0,0x6000,1)==6); /* primary code purpose */
    fixed[CORE_PAGE_PURPOSE+2]=7;assert(request(3,page,0,0x6000,1)==6);
    assert(request(1,page,0,0,0)==6);fixed[CORE_PAGE_PURPOSE+2]=3;
    word(OWNER,0x0102);fixed[DATA_MAPPED]=mapped=17;
    assert(request(2,page,0,0x6000,1)==3);assert(request(1,page,0,0,0)==3);
    word(OWNER,0x0101);fixed[DATA_MAPPED]=mapped=16;
    fixed[DATA_CURRENT]=1;assert(request(0,0,0,0,0)==7);fixed[DATA_CURRENT]=0;
    fixed[CORE_APP_FLAGS]=4;assert(request(0,0,0,0,0)==7);fixed[CORE_APP_FLAGS]=0;
    fixed[CORE_APP_CODE_NATIVE]=17;assert(request(2,page,0,0x6000,1)==7);fixed[CORE_APP_CODE_NATIVE]=16;
    assert(!request(1,page,0,0,0));assert(request(2,page,0,0x6000,1)==4);
    assert(!request(0,0,0,0,0));assert(readword(0x7002)==0x0203);
    assert(request(2,page,0,0x6000,1)==2);assert(request(2,0,0,0,0)==2);
    for(unsigned i=0;i<3;++i) assert(!request(0,0,0,0,0));
    assert(request(0,0,0,0,0)==5 && !readword(0x7002));
    assert(request(0,0,1,0,0)==6);assert(request(1,0x0203,0,0,1)==6);
    assert(request(4,page,0,0,0)==6);
    request(2,0x0203,0,0x6000,1);wr(0,0x700F,1);invoke(0x7000,16);assert(rd(0,0x7001)==6);
    before=maps;invoke(0x3FFF,16);assert(cpu.a==6);invoke(0x7EF1,16);assert(cpu.a==6);
    invoke(0xFFF0,16);assert(cpu.a==6);invoke(0x7000,15);assert(cpu.a==6);assert(maps==before);
    printf("data pages: %lu instruction-level calls PASS, maps=%lu\n",checks,maps);
    return 0;
}
