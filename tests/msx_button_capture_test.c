/* Execute the real assembled MSX input code on the 1983 Z80 core with a tiny
 * fake I/O bus. These are instruction-level contract tests, not emulator UI
 * qualification; the separate openMSX/1983 workflows use ordinary input. */
#include "z80.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static unsigned char mem[65536], ppi=0xad, keys=255, psg[16], selected;
static unsigned char read_mem(void *ctx, unsigned short a) {(void)ctx;return mem[a];}
static void write_mem(void *ctx, unsigned short a, unsigned char v) {(void)ctx;mem[a]=v;}
static unsigned char read_io(void *ctx, unsigned short a) {
    (void)ctx;
    switch (a&255) {
        case 0xaa:return ppi;
        case 0xa9:return (ppi&15)==8 ? keys : 255;
        case 0xa2:return psg[selected];
        default:assert(0);return 255;
    }
}
static void write_io(void *ctx, unsigned short a, unsigned char v) {
    (void)ctx;
    switch(a&255) {
        case 0xaa:ppi=v;break;
        case 0xa0:selected=v&15;break;
        case 0xa1:psg[selected]=v;break;
        default:assert(0);
    }
}
static Z80 cpu;
static Z80Bus bus={.mem_read=read_mem,.mem_write=write_mem,.io_read=read_io,.io_write=write_io};
static void call(unsigned short address) {
    cpu.pc=address;cpu.sp=0xe000;mem[0xe000]=0;mem[0xe001]=2;
    unsigned count=0;
    while(cpu.pc!=0x0200 && ++count<20000) z80_step(&cpu,&bus);
    assert(count<20000 && cpu.sp==0xe002);
}
static void irq(void) {
    cpu.af=0x1234;cpu.bc=0x5678;cpu.de=0x9abc;cpu.hl=0xdef0;
    cpu.ix=0x4567;cpu.iy=0x89ab;cpu.iff1=cpu.iff2=false;
    call(0xcf60);
    assert(cpu.af==0x1234 && cpu.bc==0x5678 && cpu.de==0x9abc && cpu.hl==0xdef0);
    assert(cpu.ix==0x4567 && cpu.iy==0x89ab && !cpu.iff1 && !cpu.iff2);
    assert(ppi==0xad && psg[15]==0xff);
}
static void press(void) {keys=254;irq();}
static void release(void) {keys=255;irq();}
static unsigned filter(bool enabled) {
    cpu.iff1=cpu.iff2=enabled;cpu.d=7;call(0x414);
    assert(cpu.iff1==enabled && cpu.iff2==enabled);
    return cpu.d;
}
int main(int argc,char **argv) {
    assert(argc==2);
    FILE *f=fopen(argv[1],"rb");assert(f);
    size_t size=fread(mem+0x400,1,0xb00,f);assert(size>2238 && !ferror(f));fclose(f);
    z80_init(&cpu);psg[14]=255;psg[15]=255;
    call(0x411); /* newly appended private init entry */
    mem[0x1351]=0;mem[0xc358]=1;mem[0x1705]=0;
    mem[0x14a2]=12;mem[0x14a3]=6;
    assert(filter(true)==2); /* quit preserved, no phantom legacy edge/hold */
    press();release();assert(mem[0xcf33]==1 && mem[0xcf30]==0);
    mem[0x14a2]=80;mem[0x14a3]=90;
    assert(filter(true)==3 && mem[0x14a2]==12 && mem[0x14a3]==6);
    assert(filter(false)==2 && mem[0xcf33]==0); /* exactly once, IFF2 preserved */
    psg[14]=239;irq();assert(filter(true)==7); /* joystick/mouse trigger */
    assert(filter(true)==6); /* held is not a repeated click */
    press();assert(mem[0xcf33]==0); /* aggregate buttons, no duplicate edge */
    psg[14]=255;irq();assert(mem[0xcf30]==16);
    release();assert(filter(true)==2);
    for(unsigned i=0;i<5;i++) {mem[0xcf36]=10+i;press();release();}
    assert(mem[0xcf33]==4 && mem[0xcf34]==1);
    for(unsigned i=0;i<4;i++) {assert(filter(true)==3);assert(mem[0x14a2]==10+i);}
    assert(filter(true)==2);
    press();release();mem[0x1351]=1;mem[0xc359]=1;
    assert(filter(true)==2 && mem[0xcf34]==2); /* stale focus */
    press();release();mem[0xc359]=2;
    assert(filter(true)==2 && mem[0xcf34]==3); /* closed/reused window */
    press();release();mem[0x1705]=1;
    assert(filter(true)==2 && mem[0xcf34]==4); /* modal transition */
    mem[0xcf34]=255;
    for(unsigned i=0;i<5;i++) {press();release();}
    assert(mem[0xcf34]==255 && mem[0xcf33]==4); /* saturating overflow */
    mem[0x1351]=255;assert(filter(true)==2 && mem[0xcf33]==0 && mem[0xcf35]==0);
    puts("MSX button capture: FIFO, overflow, coordinates, stale context, held level, registers and IFF PASS");
    return 0;
}
