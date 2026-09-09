/* Actual assembled admission/unsupported dispatch and optional boot validator.
 * Storage is stubbed only at fs_load_sys; this is not storage-fault media proof. */
#include "z80.h"
#include "gate_fixture.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned char mem[65536];
static Z80 cpu;
static unsigned char rd(void *c,unsigned short a) { (void)c;return mem[a]; }
static void wr(void *c,unsigned short a,unsigned char v) { (void)c;mem[a]=v; }
static unsigned char in(void *c,unsigned short a) { (void)c;(void)a;assert(0);return 0; }
static void out(void *c,unsigned short a,unsigned char v) { (void)c;(void)a;(void)v;assert(0); }
static Z80Bus bus={.mem_read=rd,.mem_write=wr,.io_read=in,.io_write=out};
static void word(unsigned a,unsigned v) { mem[a]=v;mem[a+1]=v>>8; }
static size_t load(const char *path,unsigned at,unsigned capacity)
{
    FILE *f=fopen(path,"rb");assert(f);
    size_t n=fread(mem+at,1,capacity,f);assert(n && !ferror(f) && fgetc(f)==EOF);
    fclose(f);return n;
}
static int call(unsigned entry)
{
    unsigned steps=0;cpu.pc=entry;cpu.sp=0xF800;word(0xF800,0x0200);
    while(cpu.pc!=0x0200 && ++steps<20000000) z80_step(&cpu,&bus);
    assert(steps<20000000 && cpu.sp==0xF802);return cpu.f&1;
}
int main(int argc,char **argv)
{
    assert(argc==5);z80_init(&cpu);
    for(unsigned enabled=0;enabled<2;++enabled) {
        memset(mem,0,sizeof(mem));load(argv[1+enabled],0x400,0xC00);
        size_t app=load(argv[4],0x4000,0x3F00);word(0x14E8,app);mem[0xC2E5]=31;
        assert(call(0x400)==(int)enabled);
        if(!enabled) {
            mem[0x7000]=10;mem[0x7001]=1;cpu.hl=0x7000;cpu.bc=16;
            cpu.ix=0x1234;cpu.iff1=cpu.iff2=true;mem[0x1340]=7;
            call(0x408);assert(cpu.a==6 && cpu.ix==0x1234);
            assert(cpu.iff1 && cpu.iff2 && mem[0x1340]==7);
        }
    }
    memset(mem,0,sizeof(mem));load(argv[3],0x9000,0x1000);
    /* The loader must not execute the data module before its checks. */
    unsigned passed=0;
    for(unsigned fault=0;fault<9;++fault) {
        mem[0x2000]=1;word(0x14E8,DATA_SIZE);
        memcpy(mem+0xD103,"GBDP\1",5);
        if(fault==1)mem[0x2000]=0;               /* storage failure */
        if(fault==2)word(0x14E8,DATA_SIZE-1);     /* short */
        if(fault==3)word(0x14E8,DATA_SIZE+1);     /* noncanonical size */
        if(fault>=4)mem[0xD103+fault-4]^=0xFF;  /* each signature/version byte */
        assert(call(BOOT_ENTRY)==(fault==0));++passed;
        assert(!memcmp(mem+0x14EC,"GBDPAGE MOD",11));
        assert(mem[0x14F7]==0 && mem[0x14F8]==0xD1);
        assert(mem[0x14F9]==0 && mem[0x14FA]==3);
    }
    printf("data pages: required capability gate off/on, unsupported dispatch, %u boot checks PASS\n",passed);
    return 0;
}
