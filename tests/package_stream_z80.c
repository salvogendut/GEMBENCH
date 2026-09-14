/* Real assembled admission, streaming and owner/page policy. Fake devices:
 * bank aperture and sequential read/close callbacks. No host format policy. */
#include "z80.h"
#include "stream_fixture.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static unsigned char fixed[65536], pages[32][16384], image[32768], original[32768];
static unsigned char binary[16384], mapped;
static size_t image_size, original_size, binary_size, offset;
static unsigned reads, closes, map_calls, checks, fault_read, fault_kind, close_fault;
static unsigned opens, open_fault;
static int stream_open;
static int dos_bank_pending;
static uint64_t last_cycles;
static uint64_t max_blackout;
static unsigned irq_ticks, secondary_ticks;
static Z80 cpu;
static unsigned char invoke(unsigned short entry,unsigned short de,unsigned short hl);
static unsigned char rd(void *c,unsigned short a)
{ (void)c;return a>=0x4000 && a<0x8000 ? pages[mapped-16][a-0x4000] : fixed[a]; }
static void wr(void *c,unsigned short a,unsigned char v)
{ (void)c;if(a>=0x4000 && a<0x8000)pages[mapped-16][a-0x4000]=v;else fixed[a]=v; }
static unsigned char in(void *c,unsigned short a) { (void)c;(void)a;assert(0);return 0; }
static void out(void *c,unsigned short port,unsigned char value)
{
    (void)c;port&=255;
    if(port==250) {
        assert(MSX_STREAM_TEST && cpu.iff1 && fixed[PKG_LOCK] && !fixed[PKG_CURRENT]);
        unsigned operation=cpu.c;
        if(operation==0x43) {
            assert(!stream_open && cpu.a==1 && cpu.de==0x0300);
            ++opens;cpu.a=open_fault?9:0;cpu.b=37;stream_open=!open_fault;
        } else if(operation==0x48) {
            assert(cpu.b==37 && cpu.de==PKG_BUFFER);
            cpu.bc=cpu.hl;cpu.hl=cpu.de;out(0,253,0);cpu.hl=cpu.bc;
            if(!cpu.a && !cpu.hl && fault_read!=reads)cpu.a=0xC7; /* actual DOS EOF */
        } else if(operation==0x45) {
            assert(cpu.b==37);out(0,252,0);
        } else assert(0);
        /* DOS returns its TPA in hardware, without changing our software
         * shadow. Its index-register clobbers must also be contained. */
        mapped=16;dos_bank_pending=1;cpu.ix=0x9876;cpu.iy=0xABCD;return;
    }
    if(port==254) {
        assert(!cpu.iff1); /* mapper hardware/shadow transitions must be atomic */
        assert(value>=16 && value<48);mapped=value;dos_bank_pending=0;++map_calls;
    } else if(port==253) {
        assert(stream_open && mapped==17 && cpu.bc<=512 && cpu.bc>0);
        assert(cpu.hl==PKG_BUFFER && fixed[PKG_LOCK]==1);
        assert(cpu.iff1==PKG_ALLOW_IRQ);
        unsigned requested=cpu.bc, actual=requested;++reads;
        if(offset+actual>image_size)actual=(unsigned)(image_size-offset);
        cpu.a=0;
        if(fault_read==reads) {
            if(fault_kind==1)cpu.a=9;
            else if(fault_kind==2 && actual) --actual;
            else if(fault_kind==3)actual=0;
            else if(fault_kind==5)cpu.a=0xC7;
        }
        memcpy(fixed+PKG_BUFFER,image+offset,actual);offset+=actual;cpu.bc=actual;
        if(fault_read==reads && fault_kind==4)cpu.bc=requested+1;
    } else if(port==252) {
        assert(stream_open && mapped==17 &&
               fixed[PKG_LOCK]==(MSX_STREAM_TEST && !fixed[PKG_BUSY] ? 7 : 1));
        stream_open=0;++closes;cpu.a=close_fault ? 9 : 0;
    } else if(port==251) {
        assert(PKG_ALLOW_IRQ && fixed[PKG_LOCK]==1 && fixed[PKG_BUSY]);
        /* A fixed-state IRQ may also interrupt DOS's own temporary TPA map.
         * Only the DOS call/recovery interval permits this mismatch. */
        assert((mapped==fixed[PKG_MAPPED] || (MSX_STREAM_TEST && dos_bank_pending && mapped==16)) &&
               fixed[PKG_CURRENT]==0);
        ++irq_ticks;if(mapped!=17)++secondary_ticks;
    } else assert(0);
}
static Z80Bus bus={.mem_read=rd,.mem_write=wr,.io_read=in,.io_write=out};
static void word(unsigned short a,unsigned short v) { wr(0,a,v);wr(0,a+1,v>>8); }
static unsigned short getword(unsigned short a) { return rd(0,a)+256u*rd(0,a+1); }
static unsigned short iw(unsigned a) { return image[a]+256u*image[a+1]; }
static void iw_set(unsigned a,unsigned v) { image[a]=v;image[a+1]=v>>8; }
static size_t loadfile(const char *path,unsigned char *buffer,size_t capacity)
{
    FILE *f=fopen(path,"rb");assert(f);size_t n=fread(buffer,1,capacity,f);
    assert(n && !ferror(f) && fgetc(f)==EOF);fclose(f);return n;
}
static void crc(void)
{
    unsigned at=iw(14)+56;memset(image+at,0,4);uint32_t sum=0xFFFFFFFFu;
    for(size_t i=0;i<image_size;++i) {
        sum^=image[i];for(unsigned j=0;j<8;++j)sum=(sum>>1)^((sum&1)?0xEDB88320u:0);
    }
    sum=~sum;for(unsigned i=0;i<4;++i)image[at+i]=(unsigned char)(sum>>(8*i));
}
static void init(void)
{
    memset(fixed,0,sizeof(fixed));memcpy(fixed+0x8000,binary,binary_size);
    memset(pages,0x69,sizeof(pages));mapped=17;fixed[PKG_MAPPED]=17;
    fixed[CORE_PAGE_TOTAL]=8;fixed[CORE_PAGE_FREE]=6;
    for(unsigned i=0;i<8;++i)fixed[CORE_PAGE_NATIVE+i]=16+i;
    for(unsigned i=0;i<2;++i) {
        fixed[CORE_OWNER_ACTIVE+i]=fixed[CORE_OWNER_GEN+i]=1;
        fixed[CORE_APP_CODE_NATIVE+i]=16+i;
        fixed[CORE_PAGE_STATE+i]=fixed[CORE_PAGE_GEN+i]=fixed[CORE_PAGE_PURPOSE+i]=1;
        fixed[CORE_PAGE_OWNER+i]=i+1;fixed[CORE_PAGE_OWNER_GEN+i]=1;
        fixed[CORE_LEGACY_BUSY+i]=1;
    }
    word(CORE_PENDING_OWNER,0x0102);
    word(PKG_CAPS_LOW,0x7FFF);word(PKG_CAPS_HIGH,0x01DF);
    reads=closes=map_calls=fault_read=fault_kind=close_fault=0;
    opens=open_fault=0;dos_bank_pending=0;
    offset=0;stream_open=1;image_size=original_size;memcpy(image,original,original_size);
    if(MSX_STREAM_TEST) {
        stream_open=0;memcpy(fixed+0x0300,"\\GBENCH\\STREAM.APP",19);
        assert(invoke(MSX_PKG_OPEN,0x0300,0)==0 && stream_open && opens==1);
        map_calls=0;
    }
}
static unsigned char invoke(unsigned short entry,unsigned short de,unsigned short hl)
{
    unsigned long steps=0;unsigned char prior=mapped;
    unsigned char lock=(checks&2)?7:0;int iff=checks&1;
    if(MSX_STREAM_TEST && entry!=PACKAGE_LOAD && entry!=OWNER_RELEASE)lock=7;
    z80_init(&cpu);cpu.pc=entry;cpu.sp=0xF800;word(cpu.sp,0x0200);
    fixed[0x38]=0xC3;word(0x39,IRQ_HANDLER);cpu.im=1;
    cpu.de=de;cpu.hl=hl;cpu.ix=0x1234;cpu.iy=0x5678;cpu.iff1=cpu.iff2=iff;
    fixed[PKG_LOCK]=lock;
    last_cycles=max_blackout=0;irq_ticks=secondary_ticks=0;
    uint64_t blackout=0,next_irq=1500;
    while(cpu.pc!=0x0200 && ++steps<60000000) {
        assert(cpu.pc<0x4000 || cpu.pc>=0x8000); /* no application executes */
        if(entry==PACKAGE_LOAD && fixed[PKG_BUSY] && last_cycles>=next_irq) {
            z80_interrupt(&cpu);next_irq=last_cycles+1500;
        }
        unsigned elapsed=(unsigned)z80_step(&cpu,&bus);last_cycles+=elapsed;
        if(fixed[PKG_BUSY] && !cpu.iff1)blackout+=elapsed;else blackout=0;
        if(blackout>max_blackout)max_blackout=blackout;
    }
    if(steps==60000000)fprintf(stderr,"timeout check=%u pc=%04x\n",checks,cpu.pc);
    assert(steps<60000000 && cpu.sp==0xF802);
    if(MSX_STREAM_TEST && entry!=OWNER_RELEASE && entry!=GBAP4_VALIDATE_LOADED) {
        assert(cpu.ix==0x1234 && cpu.iy==0x5678);
        assert(cpu.iff1==iff && cpu.iff2==iff && fixed[PKG_LOCK]==lock);
        assert(mapped==prior && fixed[PKG_MAPPED]==prior && !dos_bank_pending);
    }
    if(entry==PACKAGE_LOAD) {
        assert(cpu.ix==0x1234 && cpu.iy==0x5678);
        assert(cpu.iff1==iff && cpu.iff2==iff && fixed[PKG_LOCK]==lock);
        assert(mapped==prior && fixed[PKG_MAPPED]==prior);
        if(PKG_ALLOW_IRQ)assert(max_blackout<1024); /* CPU fixture, not a DOS bound */
        else assert(!irq_ticks);
        for(unsigned i=0;i<16384;++i)assert(pages[0][i]==0x69); /* parent */
        for(unsigned i=0x3F00;i<16384;++i)assert(pages[1][i]==0x69); /* primary snapshot */
    }
    ++checks;return cpu.a;
}
static void failed(unsigned expected)
{
    unsigned char status=invoke(PACKAGE_LOAD,0x0102,0);
    if(status!=expected)fprintf(stderr,"case=%u got=%u expected=%u reads=%u offset=%zu\n",checks,status,expected,reads,offset);
    assert(status==expected && !stream_open && closes==1 && !fixed[PKG_BUSY]);
    assert(!getword(PKG_PAGE) && !getword(PKG_ENTRY) && !getword(PKG_SECONDARY_SIZE));
    for(unsigned i=0;i<8;++i)assert(fixed[CORE_PAGE_STATE+i]==(i<2));
    assert(fixed[CORE_PAGE_FREE]==6);
}
static unsigned success(void)
{
    unsigned m=iw(14),primary=iw(m+40),secondary=(unsigned)image_size-primary;
    unsigned char status=invoke(PACKAGE_LOAD,0x0102,0);
    if(status)fprintf(stderr,"valid case=%u status=%u primary=%u secondary=%u reads=%u\n",checks,status,primary,secondary,reads);
    assert(!status && !stream_open && closes==1 && !fixed[PKG_BUSY]);
    assert(!memcmp(pages[1],image,primary) && !memcmp(pages[2],image+primary,secondary));
    for(unsigned i=secondary;i<16384;++i)assert(!pages[2][i]);
    assert(getword(PKG_PAGE)==0x0103 && getword(PKG_ENTRY)==0x4008);
    assert(getword(PKG_SECONDARY_SIZE)==secondary && fixed[CORE_PAGE_PURPOSE+2]==7);
    assert(fixed[CORE_PAGE_OWNER+2]==2 && fixed[CORE_PAGE_OWNER_GEN+2]==1);
    assert(fixed[CORE_PAGE_FREE]==5);
    if(PKG_ALLOW_IRQ)assert(irq_ticks>100 && secondary_ticks>100);
    printf("stream load bytes=%zu reads=%u T-states=%llu IRQ ticks=%u secondary=%u max DI=%llu (fixture storage/ISR)\n",
           image_size,reads,(unsigned long long)last_cycles,irq_ticks,secondary_ticks,
           (unsigned long long)max_blackout);
    return reads;
}
int main(int argc,char **argv)
{
    assert(argc==6);binary_size=loadfile(argv[1],binary,sizeof(binary));
    for(unsigned sample=0;sample<3;++sample) {
        original_size=loadfile(argv[2+sample],original,sizeof(original));init();
        unsigned calls=success();
        /* The actual existing owner teardown also reclaims successful results. */
        invoke(OWNER_RELEASE,0x0102,0);
        for(unsigned i=0;i<8;++i)assert(fixed[CORE_PAGE_STATE+i]==(i==0));
        /* Error, short, zero-progress and oversized return at EVERY exact read,
         * plus explicit failure at the EOF probe. Avoid 60M-step max cases on
         * every fault: medium case exercises multiple secondary chunks too. */
        if(sample==1)for(unsigned call=1;call<=calls;++call)for(unsigned kind=1;kind<=4;++kind) {
            if(call==calls && (kind==2 || kind==3))continue; /* EOF is correctly zero */
            init();fault_read=call;fault_kind=kind;failed(call==calls && kind==4 ? 1 : 2);
        }
        init();close_fault=1;failed(2);
        init();image[image_size-1]^=1;failed(1); /* full stream CRC, no rehash */
        init();image[image_size++]=0xAA;failed(1); /* exact EOF, no trailing byte */
        init();image_size--;failed(2); /* truncated secondary */
        /* Descriptor and entry mutations get valid CRCs, so CRC cannot mask
         * the actual structural checks. */
        unsigned m=original[14]+256u*original[15],s=m+64+20;
        unsigned primary=original[m+40]+256u*original[m+41];
        const unsigned truncated[]={0,1,255,257,primary-1};
        for(unsigned i=0;i<sizeof(truncated)/sizeof(truncated[0]);++i) {
            init();image_size=truncated[i];failed(2);
        }
        /* Every required capability must actually be offered by the receiver. */
        for(unsigned bit=0;bit<32;++bit)if(original[m+12+bit/8]&(1u<<(bit%8))) {
            init();unsigned at=(bit<16?PKG_CAPS_LOW:PKG_CAPS_HIGH)+(bit%16)/8;
            fixed[at]&=~(1u<<(bit%8));failed(1);
        }
        /* Assigned compute bit requires both a qualified receiver profile and
         * its live capability. Never admit it just because it is assigned. */
        init();image[m+15]|=4;crc();failed(1);
        init();image[m+15]|=4;fixed[PKG_CAPS_HIGH+1]|=4;crc();
        if(ADMISSION_DUAL){assert(invoke(PACKAGE_LOAD,0x0102,0)==0);}
        else failed(1);
        const unsigned positions[]={0,3,7,8,9,12,14,m,m+4,m+5,m+6,m+7,m+8,m+10,m+11,m+13,m+15,
            m+20,m+30,m+31,m+32,m+33,m+34,m+35,m+36,m+38,m+40,m+42,m+44,m+52,m+54,m+60,
            16,17,18,19,20,22,s,s+1,s+2,s+3,s+4,s+6,s+7,s+8,s+10,s+12,s+14,s+16,s+18};
        for(unsigned i=0;i<sizeof(positions)/sizeof(positions[0]);++i) {
            init();image[positions[i]]^=0x80;
            if(positions[i]==m+33)image[m+33]=1; /* preferred < required */
            crc();failed(1);
        }
        for(unsigned field=0;field<20;++field) {
            init();image[m+64+field]^=0x80;crc();failed(1);
        }
        if(sample==2)for(unsigned field=24;field<32;++field) {
            init();image[field]^=0x80;crc();failed(1);
        }
        for(unsigned i=0;i<8;++i) {
            init();image[primary+i]^=0x80;crc();
            /* Low entry mutation can still point at loaded executable bytes. */
            if(i==1 && image[primary+1]+256u*image[primary+2]<0x4000+image_size-primary) {
                assert(invoke(PACKAGE_LOAD,0x0102,0)==0);
            } else failed(1);
        }
        init();iw_set(primary+1,0x4007);crc();failed(1);
        init();iw_set(primary+1,0x4000+(unsigned)image_size-primary);crc();failed(1);
        init();iw_set(s+12,0x3F01);iw_set(s+16,0x3F01);crc();failed(1);
        init();iw_set(m+40,0x3F01);crc();failed(1);
        init();iw_set(m+52,0x7E01);crc();failed(1);
        init();iw_set(m+32,0x0101);crc();failed(1); /* one-page claim */
        init();fixed[CORE_PAGE_TOTAL]=2;fixed[CORE_PAGE_FREE]=0;
        assert(invoke(PACKAGE_LOAD,0x0102,0)==1 && closes==1 && !getword(PKG_PAGE));
        /* Allocation race/failure after admission: leave free count initially
         * sufficient but make every otherwise-free slot legacy-busy. */
        init();for(unsigned i=2;i<8;++i)fixed[CORE_LEGACY_BUSY+i]=1;
        assert(invoke(PACKAGE_LOAD,0x0102,0)==3 && closes==1 && !getword(PKG_PAGE));
        for(unsigned variant=0;variant<6;++variant) {
            init();
            if(variant==0)fixed[PKG_CURRENT]=1;
            if(variant==1)fixed[CORE_APP_FLAGS+1]=4;
            if(variant==2)fixed[CORE_APP_CODE_NATIVE+1]=16;
            if(variant==3)fixed[CORE_OWNER_GEN+1]=2;
            if(variant==4)word(CORE_PENDING_OWNER,0);
            if(variant==5)fixed[PKG_BUSY]=1;
            assert(invoke(PACKAGE_LOAD,0x0102,0)==(variant==5?5:4));
            assert(!reads && !closes && !map_calls && stream_open);
        }
    }
    if(MSX_STREAM_TEST) {
        init();fault_read=1;fault_kind=5;failed(2); /* EOF with data is not normalized */
        init();assert(invoke(MSX_PKG_OPEN,0x0300,0)==255 && opens==1);
        /* No zero-sized/foreign-buffer transfer may reach DOS. */
        assert(invoke(MSX_PKG_READ,0,PKG_BUFFER)==255 && !reads);
        assert(invoke(MSX_PKG_READ,0,PKG_BUFFER+1)==255 && !reads);
        assert(invoke(MSX_PKG_CLOSE,0,0)==0 && !stream_open && closes==1);
        assert(invoke(MSX_PKG_CLOSE,0,0)==255 && closes==1);
        open_fault=1;
        assert(invoke(MSX_PKG_OPEN,0x0300,0)==9 && !stream_open && opens==2);
        assert(!fixed[MSX_PKG_STATE] && !fixed[MSX_PKG_STATE+2]);
        open_fault=0;assert(invoke(MSX_PKG_OPEN,0x0300,0)==0 && opens==3);
        close_fault=1;assert(invoke(MSX_PKG_CLOSE,0,0)==9 && !stream_open);
        assert(!fixed[MSX_PKG_STATE] && fixed[MSX_PKG_STATE+2]==9);
        assert(fixed[MSX_PKG_STATE+1]==37);
        assert(invoke(MSX_PKG_OPEN,0x0300,0)==255 && opens==3);
        assert(invoke(MSX_PKG_CLOSE,0,0)==255 && closes==2);
        puts("MSX stream: single open, readonly handle, DOS bank/index/IFF restoration, invalid calls and close poison PASS");
    }
    if(ADMISSION_DUAL) {
        original_size=loadfile(argv[5],original,sizeof(original));
        for(unsigned variant=0;variant<5;++variant) {
            init();memcpy(pages[1],original,original_size);
            word(fs_ent_size,(unsigned short)original_size);word(fs_ent_size+2,0);
            fixed[GB4_STREAMED]=1; /* stale stream mode must never bypass CRC */
            if(variant==1)pages[1][original_size-1]^=1;
            if(variant==2)word(fs_ent_size+2,1);
            if(variant==3) { pages[1][0]=0xC9;word(fs_ent_size,1); }
            if(variant==4)pages[1][7]=5;
            invoke(GBAP4_VALIDATE_LOADED,0,0);
            assert((cpu.f&1)==(variant==0 || variant==3));
            assert(!fixed[GB4_STREAMED]);
        }
        original_size=loadfile(argv[2],original,sizeof(original));init();
        memcpy(pages[1],original,original_size);word(fs_ent_size,(unsigned short)original_size);
        fixed[GB4_STREAMED]=1;invoke(GBAP4_VALIDATE_LOADED,0,0);
        assert(!(cpu.f&1) && !fixed[GB4_STREAMED]); /* normal entry rejects two segments */
        assert(invoke(PACKAGE_LOAD,0x0102,0)==0 && fixed[GB4_STREAMED]==1);
        puts("Dual admission: primary CRC, legacy, bad version/size, stale mode and distinct streamed entry PASS");
    }
    printf("package stream: %u instruction-level transactions/checks PASS; three sizes, two icons, CRC, fault sweep and owner teardown\n",checks);
    return 0;
}
