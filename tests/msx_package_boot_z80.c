/* Execute real module boot checks. Storage is stubbed at fs_load_sys; the
 * separate openMSX run qualifies actual file reads and ordinary app lifecycles. */
#include "z80.h"
#include "fixture.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static unsigned char mem[65536], parts[4][4096];
static const unsigned addresses[]={0x400,0xCFDB,0x100,0x1C00};
static const unsigned lengths[]={3014,1061,747,256};
static const char *names[]={"GBAPV4  MOD","GBPKFIX MOD","GBPKLOADMOD","GBPKWM  MOD"};
static Z80 cpu;
static unsigned calls, fault, target;
static unsigned dos_status,dos_count;
static unsigned char rd(void *c,unsigned short a) {(void)c;return mem[a];}
static void wr(void *c,unsigned short a,unsigned char v) {(void)c;mem[a]=v;}
static Z80Bus bus={.mem_read=rd,.mem_write=wr};
static unsigned word(unsigned a) {return mem[a]+256*mem[a+1];}
static void putword(unsigned a,unsigned v) {mem[a]=v;mem[a+1]=v>>8;}
static size_t load(const char *p,unsigned char *at,unsigned capacity) {
    FILE *f=fopen(p,"rb");assert(f);
    size_t n=fread(at,1,capacity,f);assert(n && !ferror(f) && fgetc(f)==EOF);
    fclose(f);return n;
}
static void read_module(void) {
    unsigned i=calls++,problem=i==target?fault:0;
    assert(i<4 && !memcmp(mem+0x14EC,names[i],11));
    assert(word(0x14F7)==addresses[i] && word(0x14F9)==lengths[i]);
    cpu.ix=0x7777; /* real resolver may clobber scratch registers */
    cpu.f=0;
    if(problem==1 || problem==3) return; /* unavailable / bounded read too big */
    memcpy(mem+addresses[i],parts[i],lengths[i]);
    putword(0x14E8,lengths[i]-(problem==2));putword(0x14EA,problem==4);
    if(problem==5)mem[addresses[i]]=0;
    if(problem>=6 && problem<=10)mem[addresses[i]+3+problem-6]^=255;
    if(problem>=11)mem[0xD100+(problem==11?0:problem-9)]^=255;
    cpu.f=1;
}
static int call(unsigned entry) {
    unsigned steps=0;cpu.pc=entry;cpu.sp=0xF800;putword(cpu.sp,0xF100);
    while(cpu.pc!=0xF100 && ++steps<20000) {
        if(cpu.pc==FS_LOAD_SYS)read_module();
        if(cpu.pc==5) {cpu.a=dos_status;cpu.hl=dos_count;}
        z80_step(&cpu,&bus);
    }
    assert(steps<20000 && cpu.sp==0xF802);return cpu.f&1;
}
int main(int argc,char **argv) {
    assert(argc==6);z80_init(&cpu);
    for(unsigned i=0;i<4;i++)assert(load(argv[i+2],parts[i],4096)==lengths[i]);
    unsigned passed=0;
    for(target=0;target<4;target++) {
        for(fault=0;fault<=(target==1?16u:10u);fault++) {
            memset(mem,0xA5,sizeof(mem));load(argv[1],mem+0x9000,0x1000);calls=0;
            assert(call(PACKAGE_MODULES_LOAD)==(fault==0));
            assert(calls==(fault>=11 || !fault?4:target+1));
            for(unsigned a=0xCF60;a<0xCFDB;a++)assert(mem[a]==0xA5);
            for(unsigned a=0xD400;a<0xD480;a++)assert(mem[a]==0xA5);
            for(unsigned a=0xFD0;a<0x1000;a++)assert(mem[a]==0xA5);
            if(!fault) {
                for(unsigned i=0;i<4;i++)assert(!memcmp(mem+addresses[i],parts[i],lengths[i]));
                call(0x411); /* actual input init installs exactly the IRQ leaf */
                assert(!memcmp(mem+0xCFDB,parts[1],lengths[1]));
                for(unsigned a=0xD3F0;a<0xD400;a++)assert(mem[a]==0);
            }
            ++passed;
        }
    }
    mem[5]=0xC9;mem[0x144F]=0;
    for(unsigned status=0;status<3;status++) {
        dos_status=status==0?0:status==1?0xC7:0xD0;
        for(dos_count=0;dos_count<2;dos_count++)
            assert(call(FSLOAD_MAXED)==(dos_count==0 && status!=2));
    }
    memcpy(mem+addresses[1],parts[1],lengths[1]);
    for(unsigned bad=0;bad<9;bad++) {
        mem[0x1340]=1;mem[0x1342]=0;mem[0xD0FD]=1;mem[0xD0E3]=1;
        cpu.hl=0x1800;cpu.bc=256;cpu.ix=0x1234;cpu.iy=0x5678;
        if(bad==1)cpu.hl--;
        if(bad==2)cpu.hl++;
        if(bad==3)cpu.bc=0;
        if(bad==4)cpu.bc=255;
        if(bad==5)cpu.bc=257;
        if(bad==6)mem[0x1340]=0;
        if(bad==7)mem[0x1342]=1;
        if(bad==8)mem[0xD0FD]=0;
        call(0xCFDB+8);
        assert(cpu.a==(bad?255:0) && mem[0xD0E3]==(bad!=0));
        assert(cpu.ix==0x1234 && cpu.iy==0x5678);
        if(!bad)assert(cpu.bc==256);
    }
    printf("MSX package modules: %u boot cases, 6 bounded EOF and 9 prefix checks, fixed guards/IRQ install PASS\n",passed);
    return 0;
}
