/* Actual Z80 seal/call/reclaim code. Only the mapping aperture is simulated. */
#include "z80.h"
#include "fixture.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned char ram[65536],pages[32][16384],mapped=16,leaf[512];
static size_t leaf_size;
static Z80 cpu;
static unsigned calls,maps,irq_ticks,secondary_ticks;
static unsigned entry_sp=0xF800;
static unsigned char rd(void *c,unsigned short a){(void)c;return a>=0x4000&&a<0x8000?pages[mapped-16][a-0x4000]:ram[a];}
static void wr(void *c,unsigned short a,unsigned char v){(void)c;if(a>=0x4000&&a<0x8000)pages[mapped-16][a-0x4000]=v;else ram[a]=v;}
static void out(void*c,unsigned short a,unsigned char v){
    (void)c;
    assert(!cpu.iff1);
    if((a&255)==251){
        assert(ram[SEC_MAPPED]==mapped);
        ++irq_ticks;
        if(mapped==18){assert(ram[SEC_STATE]&&ram[SEC_LOCK]);++secondary_ticks;}
        return;
    }
    assert((a&255)==254&&v>=16&&v<48&&ram[SEC_MAPPED]==v);mapped=v;++maps;
}
static Z80Bus bus={.mem_read=rd,.mem_write=wr,.io_write=out};
static void word(unsigned a,unsigned v){wr(0,a,v);wr(0,a+1,v>>8);}
static void execute(unsigned at){
    cpu.pc=at;cpu.sp=entry_sp;word(cpu.sp,0x0200);
    cpu.pending_irq=false;cpu.im=1;
    ram[0x38]=0xC3;word(0x39,IRQ_HANDLER);
    unsigned steps=0,elapsed=0,next_irq=1500;
    while(cpu.pc!=0x0200&&++steps<1000000){
        if(at==SECONDARY_CALL&&ram[SEC_STATE]&&elapsed>=next_irq){
            z80_interrupt(&cpu);next_irq=elapsed+1500;
        }
        elapsed+=(unsigned)z80_step(&cpu,&bus);
    }
    assert(steps<1000000&&cpu.sp==entry_sp+2);++calls;
}
static void setup(void){
    memset(ram+CORE_ALLOC_HANDLE,0,SEC_TRANSFER+512-CORE_ALLOC_HANDLE);
    memset(pages,0x69,sizeof(pages));mapped=16;ram[SEC_MAPPED]=16;
    ram[CORE_PAGE_TOTAL]=6;ram[CORE_PAGE_FREE]=3;
    for(unsigned i=0;i<6;i++)ram[CORE_PAGE_NATIVE+i]=16+i;
    for(unsigned i=0;i<2;i++){
        ram[CORE_OWNER_ACTIVE+i]=ram[CORE_OWNER_GEN+i]=1;
        ram[CORE_APP_CODE_NATIVE+i]=16+i;
        ram[CORE_PAGE_STATE+i]=ram[CORE_PAGE_GEN+i]=1;
        ram[CORE_PAGE_OWNER+i]=i+1;ram[CORE_PAGE_OWNER_GEN+i]=1;
        ram[CORE_PAGE_PURPOSE+i]=1;ram[CORE_LEGACY_BUSY+i]=1;
    }
    ram[CORE_PAGE_STATE+2]=ram[CORE_PAGE_GEN+2]=1;
    ram[CORE_PAGE_OWNER+2]=ram[CORE_PAGE_OWNER_GEN+2]=1;
    ram[CORE_PAGE_PURPOSE+2]=7;ram[CORE_LEGACY_BUSY+2]=1;
    word(OWNER,0x0101);word(CORE_PENDING_OWNER,0x0101);ram[SEC_LOCK]=1;
    word(BIND_RECORD,0x0101);word(BIND_RECORD+2,0x0103);
    word(BIND_RECORD+4,0x4008);word(BIND_RECORD+6,8+leaf_size);
    memcpy(pages[2]+8,leaf,leaf_size);
}
static int bind(void){cpu.ix=BIND_RECORD;execute(SECONDARY_SEAL_BIND);return cpu.f&1;}
static unsigned invoke(unsigned ptr,unsigned len){
    unsigned prev=mapped;bool iff=calls&1;unsigned lock=calls&2?7:0;
    cpu.hl=ptr;cpu.bc=len;cpu.ix=0x1234;cpu.iy=0x5678;
    cpu.iff1=cpu.iff2=iff;ram[SEC_LOCK]=lock;
    execute(SECONDARY_CALL);
    assert(mapped==prev&&ram[SEC_MAPPED]==prev&&ram[SEC_LOCK]==lock);
    assert(cpu.ix==0x1234&&cpu.iy==0x5678&&cpu.iff1==iff&&cpu.iff2==iff);
    return cpu.a;
}
int main(int argc,char**argv){
    assert(argc==3);FILE*f=fopen(argv[1],"rb");assert(f);
    assert(fread(ram+0x8000,1,0x4000,f)>0&&!ferror(f));fclose(f);
    f=fopen(argv[2],"rb");assert(f);leaf_size=fread(leaf,1,sizeof(leaf),f);assert(leaf_size&&!ferror(f));fclose(f);
    z80_init(&cpu);setup();
    assert(invoke(0x6000,512)==3); /* raw code-purpose page is not a seal */
    ram[SEC_LOCK]=1;assert(bind());
    unsigned char seal[64];memcpy(seal,ram+SEC_TABLE,64);assert(!bind());assert(!memcmp(seal,ram+SEC_TABLE,64));
    word(CORE_PENDING_OWNER,0);
    for(unsigned length=1;length<=512;length++){
        memset(pages[0]+0x2000,0x20,514);pages[0][0x2001]=0; /* nested call path */
        assert(!invoke(0x6001,length)&&cpu.e==1);
        assert(pages[0][0x2000]==0x20&&pages[0][0x2001+length]==0x20);
        for(unsigned i=0;i<length;i++)assert(pages[0][0x2001+i]==(i?0x21:1));
        for(unsigned i=length;i<512;i++)assert(ram[SEC_TRANSFER+i]==0);
        assert(!memcmp(seal,ram+SEC_TABLE,64)&&!ram[SEC_STATE]);
        assert(!memcmp(pages[2]+8,leaf,leaf_size));
    }
    unsigned oldmaps=maps;
    const unsigned bad_stacks[]={0x6000,0x8080,0x0108};
    for(unsigned i=0;i<3;i++){
        entry_sp=bad_stacks[i];assert(invoke(0x6000,1)==2);
    }
    entry_sp=0xF800;
    assert(invoke(0,1)==1);assert(invoke(0x3FFF,1)==1);assert(invoke(0x6000,0)==1);
    assert(invoke(0x6000,513)==1);assert(invoke(0x7EFF,2)==1);assert(invoke(0xFFF0,32)==1);
    ram[SEC_CURRENT]=1;assert(invoke(0x6000,1)==2);ram[SEC_CURRENT]=0;
    ram[CORE_APP_FLAGS]=4;assert(invoke(0x6000,1)==2);ram[CORE_APP_FLAGS]=0;
    ram[SEC_STATE]=1;assert(invoke(0x6000,1)==5&&ram[SEC_STATE]==1);ram[SEC_STATE]=0;
    ram[CORE_OWNER_GEN]=2;assert(invoke(0x6000,1)==2);ram[CORE_OWNER_GEN]=1;
    ram[CORE_PAGE_GEN+2]=2;assert(invoke(0x6000,1)==3);ram[CORE_PAGE_GEN+2]=1;
    ram[CORE_PAGE_OWNER+2]=2;assert(invoke(0x6000,1)==3);ram[CORE_PAGE_OWNER+2]=1;
    ram[CORE_PAGE_PURPOSE+2]=3;assert(invoke(0x6000,1)==3);ram[CORE_PAGE_PURPOSE+2]=7;
    word(SEC_TABLE+3,0x4007);assert(invoke(0x6000,1)==3);memcpy(ram+SEC_TABLE,seal,64);
    word(SEC_TABLE+5,8);assert(invoke(0x6000,1)==3);memcpy(ram+SEC_TABLE,seal,64);
    mapped=ram[SEC_MAPPED]=17;word(OWNER,0x0102);assert(invoke(0x6000,1)==3);
    mapped=ram[SEC_MAPPED]=18;word(OWNER,0x0101);assert(invoke(0x6000,1)==2);
    mapped=ram[SEC_MAPPED]=16;assert(maps==oldmaps);
    cpu.hl=0x0103;cpu.de=0x0101;execute(PAGE_FREE_OWNED);assert(!cpu.a);
    for(unsigned i=0;i<8;i++)assert(!ram[SEC_TABLE+i]);
    /* Recreate the same eight-bit page generation with a raw allocation. */
    for(unsigned i=0;i<255;i++){
        cpu.de=0x0101;cpu.b=7;execute(PAGE_ALLOC_OWNED);assert(cpu.f&1);
        if(i==254)break;
        cpu.hl=cpu.de;cpu.de=0x0101;execute(PAGE_FREE_OWNED);assert(!cpu.a);
    }
    assert(ram[CORE_PAGE_GEN+2]==1);assert(invoke(0x6000,1)==3);
    setup();assert(bind());cpu.de=0x0101;execute(OWNER_RELEASE);assert(!cpu.a);
    for(unsigned i=0;i<8;i++)assert(!ram[SEC_TABLE+i]);
    assert(!ram[CORE_PAGE_STATE]&&!ram[CORE_PAGE_STATE+2]&&!ram[CORE_OWNER_ACTIVE]);
    for(unsigned fault=0;fault<10;fault++){
        setup();
        if(fault==0)word(CORE_PENDING_OWNER,0);
        if(fault==1)ram[CORE_OWNER_ACTIVE]=0;
        if(fault==2)ram[SEC_CURRENT]=1;
        if(fault==3)ram[CORE_APP_FLAGS]=4;
        if(fault==4)ram[CORE_PAGE_PURPOSE+2]=3;
        if(fault==5)word(BIND_RECORD+4,0x4007);
        if(fault==6)word(BIND_RECORD+6,8);
        if(fault==7)word(BIND_RECORD+6,0x3F01);
        if(fault==8)ram[SEC_STATE]=1;
        if(fault==9)ram[SEC_LOCK]=0;
        assert(!bind());for(unsigned i=0;i<64;i++)assert(!ram[SEC_TABLE+i]);
    }
    assert(irq_ticks>1000&&secondary_ticks>1000);
    printf("sealed secondary: %u real Z80 bind/call/reclaim operations PASS, %u maps, %u IRQs (%u in secondary); all lengths, nesting, identity, generation wrap\n",calls,maps,irq_ticks,secondary_ticks);
    return 0;
}
