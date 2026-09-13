/* Router control flow is real assembled code. Package/CRC/DOS are controlled
 * boundaries here; real Desktop success/corruption/rollback run in openMSX. */
#include "z80.h"
#include "fixture.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned char mem[65536];
static Z80 cpu;
static unsigned package_status,admit,packages,admissions,closes;
static unsigned char rd(void *c,unsigned short a){(void)c;return mem[a];}
static void wr(void *c,unsigned short a,unsigned char v){(void)c;mem[a]=v;}
static Z80Bus bus={.mem_read=rd,.mem_write=wr};
static void word(unsigned a,unsigned v){mem[a]=v;mem[a+1]=v>>8;}
static void load(const char *p,unsigned at){
    FILE *f=fopen(p,"rb");assert(f);size_t n=fread(mem+at,1,4096,f);
    assert(n && !ferror(f) && fgetc(f)==EOF);fclose(f);
}
static int call(unsigned entry){
    cpu.pc=entry;cpu.sp=0xF800;word(cpu.sp,0xF100);
    unsigned n=0;
    while(cpu.pc!=0xF100 && ++n<20000){
        if(cpu.pc==0x400){++admissions;cpu.f=admit;}
        if(cpu.pc==0x100){
            ++packages;assert(mem[0xD0FD]==1 && mem[0xD0FE]==9 && mem[0xD0E3]==1);
            assert(mem[0x1340]==1);word(0xD0EF,9024);
            if(package_status<4){++closes;mem[0xD0FD]=0;mem[0xD0E3]=0;}
            cpu.a=package_status;
        }
        if(cpu.pc==0xCFE6){++closes;assert(mem[0xD0FD]==1);mem[0xD0FD]=0;cpu.a=0;}
        z80_step(&cpu,&bus);
    }
    assert(n<20000 && cpu.sp==0xF802);return cpu.f&1;
}
static void reset(void){
    memset(mem+0xD0E3,0,29);mem[0x1340]=3;mem[0x1342]=0;word(MSX_PENDING_OWNER,0);
    memset(mem+0x3000,0,32);mem[0x3002]=1;word(0x3003,256);
    memset(mem+0x1800,0,512);mem[0x1800]=0xC3;
    memcpy(mem+0x1803,"GBAP\4",5);mem[0x1808]=2;mem[0x1842]=2;
    packages=admissions=closes=0;admit=1;package_status=0;
    cpu.ix=0x1234;cpu.iy=0x5678;cpu.iff1=cpu.iff2=false;
}
int main(int argc,char **argv){
    assert(argc==3);z80_init(&cpu);load(argv[1],0x1C00);load(argv[2],0x9000);
    mem[0x100]=mem[0x400]=mem[0xCFE6]=0xC9;
    unsigned checks=0;
    for(unsigned strict=0;strict<2;strict++)for(unsigned format=0;format<2;format++){
        for(unsigned status=0;status<6;status++){
            reset();mem[0x123D]=strict;package_status=status;admit=status==0;
            if(!format)mem[0x1842]=1;
            assert(call(MSX_APP_LOAD)==(status==0));
            assert(mem[0x3000]==strict && mem[0x3001]==1 && mem[0x123D]==0);
            assert(packages==format && admissions==!format && closes==format);
            assert(!mem[0xD0FD] && !mem[0xD0E3] && !mem[0xD0E4] && mem[0x1340]==3);
            assert(cpu.ix==0x1234 && cpu.iy==0x5678 && !cpu.iff1 && !cpu.iff2);
            ++checks;
        }
        reset();mem[0x3002]=0;mem[0x123D]=strict;
        assert(!call(MSX_APP_LOAD) && !packages && !admissions && !mem[0x123D]);++checks;
    }
    for(unsigned fault=0;fault<6;fault++){
        reset();cpu.hl=0x6123;
        if(fault==1)word(MSX_PENDING_OWNER,0x101);
        if(fault==2)mem[0x1342]=1;
        if(fault==3)mem[0xD0E7]=1;
        if(fault==4)mem[0xD0FD]=1;
        if(fault==5)mem[0xD0FF]=0xD0;
        unsigned char before[29];memcpy(before,mem+0xD0E3,29);
        assert(call(MSX_APP_CAN_LAUNCH)==!fault && cpu.hl==0x6123);
        assert(!memcmp(before,mem+0xD0E3,29));++checks;
        if(fault>1){
            mem[0xD0E3]=1;mem[0xD0E4]=2;memcpy(before,mem+0xD0E3,29);
            assert(!call(MSX_APP_LOAD) && !mem[0x3001]);
            assert(!memcmp(before,mem+0xD0E3,29));++checks;
        }
    }
    /* Later ordinary bytes that happen to resemble a package aren't a prefix. */
    reset();mem[0xD0E4]=1;word(0x3010,512);cpu.hl=256;cpu.c=9;
    assert(!call(MSX_APP_PROBE) && !packages);++checks;
    printf("MSX launch router: %u path, format, status, close, early-context and prefix checks PASS\n",checks);
    return 0;
}
