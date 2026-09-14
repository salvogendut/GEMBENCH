/* Execute the real bounded publication routine on 1983's Z80 core. */
#include "z80.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static unsigned char mem[65536];
static Z80 cpu;
static unsigned char rd(void *ctx,unsigned short address)
{ (void)ctx;return mem[address]; }
static void wr(void *ctx,unsigned short address,unsigned char value)
{ (void)ctx;mem[address]=value; }
static Z80Bus bus={.mem_read=rd,.mem_write=wr};

static void word(unsigned address,unsigned value)
{ mem[address]=(unsigned char)value;mem[address+1]=(unsigned char)(value>>8); }

static void load(const char *path)
{
    FILE *file=fopen(path,"rb");size_t count;
    assert(file);count=fread(mem+0x8000,1,0x1000,file);
    assert(count && !ferror(file) && fgetc(file)==EOF);fclose(file);
}

static unsigned char publish(unsigned address,unsigned length)
{
    unsigned steps=0;
    cpu.hl=(unsigned short)address;cpu.bc=(unsigned short)length;
    cpu.pc=0x8000;cpu.sp=0xF800;word(cpu.sp,0x0200);
    while(cpu.pc!=0x0200 && ++steps<10000)z80_step(&cpu,&bus);
    assert(steps<10000 && cpu.sp==0xF802);
    return cpu.a;
}

int main(int argc,char **argv)
{
    static const unsigned lengths[]={0,1,511,512};
    unsigned i,j;
    assert(argc==2);z80_init(&cpu);memset(mem,0xA5,sizeof(mem));load(argv[1]);
    for(i=0;i<sizeof(lengths)/sizeof(lengths[0]);++i) {
        unsigned length=lengths[i];
        for(j=0;j<length;++j)mem[0x6000+j]=(unsigned char)(j^0x5A);
        word(0x1200,0xBEEF);memset(mem+0x1000,0xC7,512);
        assert(publish(0x6000,length)==0);
        assert((unsigned)(mem[0x1200]|mem[0x1201]<<8)==length);
        assert(!memcmp(mem+0x1000,mem+0x6000,length));
    }
    for(i=0;i<5;++i) {
        static const unsigned address[]={0x3FFF,0x6000,0x7EFF,0x7F01,0xFFFF};
        static const unsigned length[]={1,513,3,0,2};
        unsigned char before[514];
        word(0x1200,0xBEEF);memset(mem+0x1000,0xC7,512);
        memcpy(before,mem+0x1000,sizeof(before));
        assert(publish(address[i],length[i])==4);
        assert(!memcmp(before,mem+0x1000,sizeof(before)));
    }
    assert(publish(0x7F00,0)==0); /* empty [end,end) is a valid span */
    puts("configuration publication: exact 0/1/511/512-byte copies and bounds PASS");
    return 0;
}
