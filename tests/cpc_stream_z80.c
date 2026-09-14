/* Run real CPC M4 transport code. Only the M4 device replies are simulated. */
#include "z80.h"
#include "stream_fixture.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static Z80 cpu;
static unsigned char ram[65536], wire[256], reply[256], payload[2048];
static unsigned ga, rom, wire_size, reply_size, offset, file_size;
static unsigned opens, reads, closes, live, fd, fault, fault_read, checks;
static unsigned max_cycles, max_stack, read_pointer=CPC_STREAM_BUFFER;
enum { OPEN_IO=1, OPEN_LENGTH, OPEN_FD_LOW, OPEN_FD_FF, OPEN_ID,
       READ_IO, READ_LENGTH, READ_OVER, READ_HIGH, READ_ID, READ_ENVELOPE,
       CLOSE_IO, CLOSE_LENGTH, CLOSE_ID };

static unsigned char rd(void *context, unsigned short address)
{
    (void)context;
    if (address>=0xE800 && address<0xE900 && !(ga&8) && rom==6) {
        /* storage_send must never read past the declared response envelope. */
        assert(address-0xE800u < reply_size);
        return reply[address-0xE800];
    }
    return ram[address];
}
static void wr(void *context, unsigned short address, unsigned char value)
{ (void)context; ram[address]=value; }
static void out(void *context, unsigned short port, unsigned char value)
{
    (void)context;
    assert(!cpu.iff1); /* hardware transactions and ROM changes are atomic */
    if(port==0x7F00) {
        assert(value>=0x80 && value<0x90); /* stream must NEVER remap the aperture */
        assert(ram[GA_SHADOW]==value); ga=value; return;
    }
    if(port==0xDF00) {assert(ram[ROM_SHADOW]==value);rom=value;return;}
    assert(rom==6 && !(ga&8) && ram[IO_BUSY] && ram[SCHED_LOCK] && !ram[SCHED_CURRENT]);
    if(port==0xFE00) {assert(wire_size<sizeof(wire));wire[wire_size++]=value;return;}
    assert(port==0xFC00 && wire_size>=4 && wire_size==wire[0]+1u);
    memset(reply,0,sizeof(reply));reply[1]=wire[1];reply[2]=0x43;
    assert(wire[2]==0x43);
    unsigned operation=wire[1];
    if(operation==1) {
        assert(!live && wire[3]==0x81 && wire[wire_size-1]==0);
        assert(!strcmp((char*)wire+4,(char*)ram+CPC_STREAM_PATH));
        ++opens;offset=0;reply[0]=4;reply[3]=fd;
        if(fault==OPEN_IO) reply[4]=5;
        else {live=1;
            if(fault==OPEN_LENGTH) reply[0]=5;
            if(fault==OPEN_FD_LOW) reply[3]=2;
            if(fault==OPEN_FD_FF) reply[3]=255;
            if(fault==OPEN_ID) reply[1]^=1;
        }
    } else if(operation==0x12) {
        assert(live && wire[3]==fd && wire_size==6 && !wire[5]);
        unsigned requested=wire[4];assert(requested && requested<=128);++reads;
        unsigned count=requested;
        if(count>file_size-offset)count=file_size-offset;
        reply[0]=7+count;reply[3]=count==requested?0:20;reply[4]=count;
        memcpy(reply+8,payload+offset,count);offset+=count;
        if(reads==fault_read) {
            if(fault==READ_IO) reply[3]=9;
            if(fault==READ_LENGTH) reply[0]--;
            if(fault==READ_OVER) reply[4]=requested+1;
            if(fault==READ_HIGH) reply[5]=1;
            if(fault==READ_ID) reply[2]=0x44;
            if(fault==READ_ENVELOPE) reply[0]=136;
        }
    } else if(operation==4) {
        assert(live && wire[3]==fd && wire_size==4);++closes;reply[0]=3;
        if(fault==CLOSE_IO) reply[3]=9;
        else if(fault==CLOSE_LENGTH) reply[0]=4;
        else if(fault==CLOSE_ID) reply[1]=3;
        else live=0;
    } else assert(0); /* includes SEEK, CD, GETPATH, writes and guessed closes */
    reply_size=reply[0]+1u;wire_size=0;
}
static Z80Bus bus={.mem_read=rd,.mem_write=wr,.io_write=out};
static void word(unsigned address,unsigned value)
{ram[address]=value;ram[address+1]=value>>8;}
static void setup(void)
{
    memset(ram+0x1000,0,0x3000);memset(ram+0x4000,0xA7,0x4000);
    memset(ram+0xC000,0xD3,0x4000);
    memset(ram+0x3500,0xD7,0x200);
    z80_init(&cpu);ga=ram[GA_SHADOW]=0x8D;rom=ram[ROM_SHADOW]=7;
    ram[BANK_SHADOW]=0xC5;ram[SCHED_LOCK]=7;
    strcpy((char*)ram+CPC_STREAM_PATH,"/GBENCH/NOTEPAD.APP");
    ram[CPC_STREAM_PATH_BYTES]=strlen((char*)ram+CPC_STREAM_PATH)+1;
    wire_size=offset=opens=reads=closes=live=fault=fault_read=0;fd=37;
    file_size=sizeof(payload);
}
static unsigned invoke(unsigned entry,unsigned count)
{
    unsigned oldga=ga,oldrom=rom,oldbank=ram[BANK_SHADOW];
    unsigned lock=ram[SCHED_LOCK],current=ram[SCHED_CURRENT];
    unsigned iff=checks&1;cpu.iff1=cpu.iff2=iff;
    cpu.hl=read_pointer;cpu.bc=count;cpu.ix=0x1234;cpu.iy=0x5678;
    cpu.pc=entry;cpu.sp=0x3610;word(cpu.sp,0x0200);
    unsigned steps=0,cycles=0,minsp=cpu.sp;
    while(cpu.pc!=0x0200 && ++steps<1000000) {
        cycles+=(unsigned)z80_step(&cpu,&bus);
        if(cpu.sp<minsp)minsp=cpu.sp;
    }
    assert(steps<1000000 && cpu.sp==0x3612);
    assert(ga==oldga && rom==oldrom && ram[BANK_SHADOW]==oldbank);
    assert(ram[SCHED_LOCK]==lock && ram[SCHED_CURRENT]==current);
    assert(cpu.iff1==iff && cpu.iff2==iff && cpu.ix==0x1234 && cpu.iy==0x5678);
    for(unsigned i=0x4000;i<0x8000;i++)assert(ram[i]==0xA7);
    for(unsigned i=0xC000;i<0x10000;i++)assert(ram[i]==0xD3);
    if(cycles>max_cycles)max_cycles=cycles;
    if(0x3610-minsp>max_stack)max_stack=0x3610-minsp;
    ++checks;return cpu.a;
}
static void guarded_buffer(void)
{memset(ram+CPC_STREAM_BUFFER-1,0x5A,514);}
static void buffer_matches(unsigned start,unsigned count)
{
    assert(ram[CPC_STREAM_BUFFER-1]==0x5A);
    assert(!memcmp(ram+CPC_STREAM_BUFFER,payload+start,count));
    for(unsigned i=count;i<=512;i++)assert(ram[CPC_STREAM_BUFFER+i]==0x5A);
}
static void closed(void)
{assert(!ram[IO_BUSY] && !ram[IO_FD] && !ram[CPC_STREAM_STATE]);}

int main(int argc,char **argv)
{
    assert(argc==2);FILE *file=fopen(argv[1],"rb");assert(file);
    assert(fread(ram+0x8000,1,0x4000,file)>0 && !ferror(file));fclose(file);
    for(unsigned i=0;i<sizeof(payload);i++)payload[i]=(i*13u+7u)^(i>>8);
    for(unsigned count=0;count<=512;count++) {
        setup();assert(!invoke(CPC_STREAM_OPEN,0));assert(live && opens==1);
        assert(ram[IO_BUSY] && ram[IO_FD]==fd);
        assert(invoke(CPC_STREAM_OPEN,0)==5 && opens==1); /* nested open */
        assert(invoke(STORAGE_GATE,16)==5 && cpu.de==0); /* ordinary gate excluded */
        guarded_buffer();assert(!invoke(CPC_STREAM_READ,count));assert(cpu.bc==count);
        buffer_matches(0,count);assert(reads==(count+127)/128);
        guarded_buffer();assert(!invoke(CPC_STREAM_READ,count));assert(cpu.bc==count);
        buffer_matches(count,count);assert(offset==2*count);
        assert(!invoke(CPC_STREAM_CLOSE,0));closed();assert(closes==1 && !live);
        assert(!invoke(CPC_STREAM_CLOSE,0) && closes==1);closed();
    }
    for(unsigned size=0;size<=513;size++) {
        setup();file_size=size;assert(!invoke(CPC_STREAM_OPEN,0));
        unsigned count=size<512?size:512;
        guarded_buffer();assert(!invoke(CPC_STREAM_READ,512) && cpu.bc==count);
        buffer_matches(0,count);
        guarded_buffer();assert(!invoke(CPC_STREAM_READ,512) && cpu.bc==size-count);
        buffer_matches(count,size-count);
        assert(!invoke(CPC_STREAM_CLOSE,0));closed();
    }
    for(unsigned error=OPEN_IO;error<=OPEN_ID;error++) {
        setup();fault=error;
        assert(invoke(CPC_STREAM_OPEN,0)==(error==OPEN_IO?3:4));closed();
        assert(opens==1 && closes==0 && ram[IO_OFFLINE]==(error!=OPEN_IO));
        assert(!invoke(CPC_STREAM_CLOSE,0) && !closes);
        if(error!=OPEN_IO)assert(invoke(CPC_STREAM_OPEN,0)==7 && opens==1);
    }
    for(unsigned error=READ_IO;error<=READ_ENVELOPE;error++)
        for(unsigned chunk=1;chunk<=4;chunk++) {
            setup();assert(!invoke(CPC_STREAM_OPEN,0));fault=error;fault_read=chunk;
            guarded_buffer();assert(invoke(CPC_STREAM_READ,512)==(error==READ_IO?3:4));
            assert(!cpu.bc && reads==chunk && ram[IO_BUSY]);
            assert(ram[CPC_STREAM_BUFFER-1]==0x5A && ram[CPC_STREAM_BUFFER+512]==0x5A);
            assert(!invoke(CPC_STREAM_CLOSE,0));closed();assert(!live && closes==1);
        }
    for(unsigned error=CLOSE_IO;error<=CLOSE_ID;error++) {
        setup();assert(!invoke(CPC_STREAM_OPEN,0));fault=error;
        assert(invoke(CPC_STREAM_CLOSE,0)==(error==CLOSE_IO?3:4));closed();
        assert(closes==1 && ram[IO_OFFLINE]);
        assert(!invoke(CPC_STREAM_CLOSE,0) && closes==1);
        assert(invoke(CPC_STREAM_OPEN,0)==7 && opens==1);
    }
    for(unsigned error=0;error<9;error++) {
        setup();
        if(error==0)ram[SCHED_LOCK]=0;
        if(error==1)ram[SCHED_CURRENT]=1;
        if(error==2)ga=ram[GA_SHADOW]=0x89;
        if(error==3)ga=ram[GA_SHADOW]=0x8F;
        if(error==4)ram[IO_BUSY]=1;
        if(error==5)ram[IO_OFFLINE]=1;
        if(error==6)ram[CPC_STREAM_PATH_BYTES]=2;
        if(error==7)ram[CPC_STREAM_PATH_BYTES]=65;
        if(error==8)ram[CPC_STREAM_PATH]='X';
        unsigned expected=error<4?6:error==4?5:error==5?7:2;
        assert(invoke(CPC_STREAM_OPEN,0)==expected && !opens && !closes && !reads);
        assert(ram[IO_BUSY]==(error==4) && !ram[IO_FD]);
    }
    for(unsigned ch=0;ch<256;ch++) {
        if(ch>=33 && ch<127 && ch!=92)continue;
        setup();ram[CPC_STREAM_PATH+1]=ch;
        assert(invoke(CPC_STREAM_OPEN,0)==2 && !opens);closed();
    }
    setup();assert(invoke(CPC_STREAM_READ,1)==6 && !reads);
    assert(!invoke(CPC_STREAM_OPEN,0));
    assert(invoke(CPC_STREAM_READ,513)==2 && !reads);
    assert(invoke(CPC_STREAM_READ,65535)==2 && !reads);
    const unsigned bad_pointers[]={0,0x3FFF,0x4000,0x7EFF,0x8000,0xFFF0,
                                   CPC_STREAM_BUFFER-1,CPC_STREAM_BUFFER+1};
    for(unsigned i=0;i<sizeof(bad_pointers)/sizeof(*bad_pointers);i++) {
        read_pointer=bad_pointers[i];
        assert(invoke(CPC_STREAM_READ,1)==2 && !reads && ram[IO_BUSY]);
    }
    read_pointer=CPC_STREAM_BUFFER;
    ram[SCHED_CURRENT]=1;
    assert(invoke(CPC_STREAM_CLOSE,0)==6 && !closes && ram[IO_BUSY]);
    assert(invoke(CPC_STREAM_READ,1)==6 && !reads && ram[IO_BUSY]);
    ram[SCHED_CURRENT]=0;ram[SCHED_LOCK]=0;
    assert(invoke(CPC_STREAM_CLOSE,0)==6 && !closes && ram[IO_BUSY]);
    ram[SCHED_LOCK]=7;
    assert(!invoke(CPC_STREAM_CLOSE,0));closed();
    for(unsigned length=3;length<=64;length++) {
        setup();memset(ram+CPC_STREAM_PATH+1,'A',length-2);
        ram[CPC_STREAM_PATH+length-1]=0;ram[CPC_STREAM_PATH_BYTES]=length;
        assert(!invoke(CPC_STREAM_OPEN,0) && opens==1);
        assert(!invoke(CPC_STREAM_CLOSE,0));closed();
    }
    setup();ram[CPC_STREAM_PATH+ram[CPC_STREAM_PATH_BYTES]-1]='X';
    assert(invoke(CPC_STREAM_OPEN,0)==2 && !opens);closed();
    printf("CPC sequential M4: %u Z80 calls PASS; all counts 0..512, EOF, single-open, "
           "wire faults, no aperture/VRAM damage, busy/offline, IFF/ROM restoration; "
           "max call %u CPU cycles, stack %u bytes (device stall excluded)\n",
           checks,max_cycles,max_stack);
    return 0;
}
