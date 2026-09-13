#include "z80.h"
#include "fixture.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned char mem[65536];static Z80 cpu;
static unsigned char rd(void*c,unsigned short a){(void)c;return mem[a];}
static void wr(void*c,unsigned short a,unsigned char b){(void)c;mem[a]=b;}
static Z80Bus bus={.mem_read=rd,.mem_write=wr};
int main(int argc,char**argv){
    assert(argc==2);FILE*f=fopen(argv[1],"rb");assert(f);assert(fread(mem,1,0x8000,f));fclose(f);
    for(unsigned at=0x8000;at<=0x80D5;at+=3){mem[at]=0xC3;mem[at+1]=0;mem[at+2]=0x90;}
    const unsigned char leaf[]={0xDD,0x21,0xAD,0x0B,0xC9};memcpy(mem+0x9000,leaf,sizeof(leaf));
    const unsigned char irq[]={0xDD,0xE5,0xDD,0x21,0x34,0x12,0xDD,0xE1,0xFB,0xED,0x4D};
    memcpy(mem+0x38,irq,sizeof(irq));
    const unsigned entries[]={_GB_FILL,_GB_FRAME,_GB_SAVERECT,_GB_RESTORERECT,
        _GB_POLL,_GB_GETKEY,_GB_MENU,_GB_RESTORE_PARENT,_GB_SYSINFO,_GB_PAGE_ALLOC,_GB_WM_MANAGED_KIND};
    unsigned checks=0;
    for(unsigned enabled=0;enabled<2;enabled++)for(unsigned n=0;n<sizeof(entries)/sizeof(entries[0]);n++){
        z80_init(&cpu);cpu.iff1=cpu.iff2=enabled;cpu.im=1;cpu.pc=entries[n];cpu.sp=0xF000;
        memset(mem+0xF000,0xA5,16);mem[0xF000]=0;mem[0xF001]=2;
        mem[0xF002]=33;mem[0xF003]=44;mem[0xF004]=3;mem[0xF005]=0x60;
        cpu.a=11;cpu.l=22;cpu.ix=0x789A;
        unsigned steps=0,entered=0,extra=n<2?3:n<4?4:0;
        while(cpu.pc!=0x200&&++steps<2000){
            if(cpu.pc==0x9000){
                entered++;
                if(n<4){assert(cpu.b==11&&cpu.c==22&&cpu.d==33&&cpu.e==44);}
                if(n<2)assert(cpu.a==3);
                if(n>=2&&n<4)assert(cpu.hl==0x6003);
            }
            if(enabled&&steps%19==0)z80_interrupt(&cpu);
            z80_step(&cpu,&bus);
        }
        assert(steps<2000&&entered==1&&cpu.sp==0xF002+extra&&cpu.ix==0x789A);
        assert(cpu.iff1==enabled&&mem[0xF006]==0xA5);++checks;
    }
    printf("IX-preserving SDK: %u real marshalled/tail-call paths with IRQs PASS\n",checks);
}
