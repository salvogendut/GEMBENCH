/* The launcher and transaction are executed, not mirrored in the host.
 * Allocation, loading and app entry are controlled external boundaries. */
#include "z80.h"
#include "fixture.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned char mem[65536];
static Z80 cpu;
static unsigned fault,opened,released,producer=0x101,recipient=0x203;
static unsigned char rd(void *c,unsigned short a){(void)c;return mem[a];}
static void wr(void *c,unsigned short a,unsigned char v){(void)c;mem[a]=v;}
static Z80Bus bus={.mem_read=rd,.mem_write=wr};
static unsigned word(unsigned a){return mem[a]|((unsigned)mem[a+1]<<8);}
static void put(unsigned a,unsigned v){mem[a]=v;mem[a+1]=v>>8;}
static void invoke(unsigned pc){
    cpu.pc=pc;cpu.sp=0xF800;put(cpu.sp,0xF100);
    unsigned count=0;
    while(cpu.pc!=0xF100 && ++count<10000){
        if(cpu.pc==OWNER_CURRENT)cpu.de=producer;
        if(cpu.pc==OWNER_ALLOC){cpu.de=recipient;cpu.f=fault!=2;}
        if(cpu.pc==PAGE_ALLOC_OWNED){
            assert(mem[DOC_PENDING]==3 && word(DOC_PENDING+1)==recipient);
            cpu.f=fault!=3;cpu.a=9;
        }
        if(cpu.pc==FAKE_LOAD)cpu.f=fault!=4;
        if(cpu.pc==APP_BASE){
            ++opened;
            assert(mem[BANK_CUR]==9 && mem[DOC_PENDING]==3 && word(DOC_PENDING+1)==recipient);
            assert(!memcmp(mem+LAUNCH_ARG,"EXACT   TXT",11));
            assert(!memcmp(mem+FS_REQ_NAME,"NOTEPAD APP",11));
            if(fault!=6)mem[DOC_PENDING]=0; /* recipient adopts, covered by policy tests */
            if(fault!=5)put(CORE_PENDING_OWNER,0); /* registration */
        }
        if(cpu.pc==OWNER_RELEASE){++released;assert(cpu.de==recipient);put(CORE_PENDING_OWNER,0);}
        z80_step(&cpu,&bus);
    }
    assert(count<10000 && cpu.sp==0xF802);
}
static void reset(void){
    memset(mem+0x3000,0,0x500);mem[BANK_CUR]=7;
    mem[DOC_PENDING]=1;put(DOC_PENDING+1,producer);
    memcpy(mem+DOC_PENDING+4,"EXACT   TXT",11);
    memcpy(mem+FS_ENT_NAME,"GBFSCTX MOD",11); /* the native entry was clobbered */
    memcpy(mem+0x6000,"NOTEPAD APP",11);cpu.hl=0x6000;
    opened=released=0;fault=0;
}
int main(int argc,char **argv){
    assert(argc==2);FILE *f=fopen(argv[1],"rb");assert(f);
    assert(fread(mem+0x8000,1,4096,f)>0 && fgetc(f)==EOF);fclose(f);
    z80_init(&cpu);mem[APP_BASE]=0xC9;
    for(fault=0;fault<7;){
        unsigned selected=fault;reset();fault=selected;
        if(fault==1)mem[WM_NWIN]=WM_MAXWIN;
        invoke(K_WM_OPEN);
        assert(!mem[DOC_PENDING] && !word(CORE_PENDING_OWNER) && mem[BANK_CUR]==7);
        assert(!memcmp(mem+LAUNCH_ARG,"\0\0\0\0\0\0\0\0\0\0\0",11));
        assert(opened==(fault==0 || fault>=5));
        assert(released==(fault>=3 && fault<=5));
        ++fault;
    }
    reset();invoke(DOCUMENT_REJECT);assert(!mem[DOC_PENDING] && !(cpu.f&1) && cpu.hl==0x6000);
    reset();mem[DOC_WORKER]=1;invoke(DOCUMENT_REJECT);assert(mem[DOC_PENDING]==1 && !(cpu.f&1));
    reset();put(DOC_PENDING+1,producer+0x100);invoke(DOCUMENT_REJECT);assert(mem[DOC_PENDING]==1);
    reset();mem[DOC_PENDING]=3;invoke(DOCUMENT_REJECT);assert(mem[DOC_PENDING]==3);
    for(unsigned bound=1;bound<=3;bound+=2){
        for(unsigned generation=0;generation<2;++generation){
            reset();mem[DOC_PENDING]=bound;put(DOC_RELEASING_OWNER,producer+generation*0x100);
            mem[CORE_FSCTX_TABLE]=1;put(CORE_FSCTX_TABLE+2,producer);
            invoke(FSCTX_OWNER_CLEANUP);
            assert(mem[DOC_PENDING]==(generation ? bound : 0));
            assert(mem[CORE_FSCTX_TABLE]==generation);
        }
    }
    puts("Document launch: 15 real Z80 success/rollback/generation/cleanup checks PASS");
    return 0;
}
