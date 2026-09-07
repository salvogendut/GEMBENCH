/* Execute the actual M4 packet/chunk adapter; only the hardware call is fake.
 * 32-bit file-offset bounds are checked even on hosts with 64-bit long. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static union { uint16_t alignment; unsigned char bytes[65536]; } memory;
static unsigned char selected[144],io_status,bad_name,oversized_reply;
static unsigned int length,calls,fail_at,file_size;
#define CPC_SELECTED selected
#define CTX_OFFSET 8
#define REQ_LENGTH length
#define CPC_PACKET (memory.bytes+0x6000)
#define CPC_IO_PATH (memory.bytes+0x6020)
#define CPC_BUFFER (memory.bytes+0x6080)
#define CPC_FILE (memory.bytes+0x2500)
#define XFER (memory.bytes+0x1500)
#define CPC_IO_STATUS io_status
#define U16(a) (*(uint16_t *)(memory.bytes+(a)))
static unsigned char cpc_fs_filename(void)
{ memcpy(CPC_FILE,"/A.BIN",7);return bad_name?0:7; }
static unsigned int cpc_fs_read128(void)
{
    unsigned int n=U16(0x6008);
    uint32_t offset=0;
    for(unsigned int i=0;i<4;i++) offset|=(uint32_t)CPC_PACKET[10+i]<<(8*i);
    assert(n && n<=128 && CPC_PACKET[0]==1 && CPC_PACKET[1]==1);
    assert(U16(0x6002)==0x6020 && U16(0x6006)==0x6080);
    assert(CPC_PACKET[4]==7 && !memcmp(CPC_IO_PATH,"/A.BIN",7));
    calls++;io_status=0;
    if(calls==fail_at) { io_status=5;return 0; }
    if(oversized_reply) return n+1;
    if(offset>=file_size) n=0;
    else if(n>file_size-offset) n=(unsigned int)(file_size-offset);
    for(unsigned int i=0;i<n;i++) CPC_BUFFER[i]=(unsigned char)(offset+i);
    if(n<U16(0x6008)) io_status=1;
    return n;
}
#include "../kernel/kc/cpc_fsread.inc"
static void reset(unsigned int size)
{
    memset(&memory,0xA5,sizeof(memory));memset(selected,0,sizeof(selected));
    file_size=size;calls=fail_at=bad_name=oversized_reply=0;io_status=5;length=512;
}
int main(void)
{
    reset(1024);assert(cpc_fs_read()==512 && calls==4 && !io_status);
    for(unsigned int i=0;i<512;i++) assert(XFER[i]==(unsigned char)i);
    assert(XFER[-1]==0xA5 && XFER[512]==0xA5 && !selected[8]);
    reset(333);assert(cpc_fs_read()==333 && calls==3 && io_status==1);
    for(unsigned int i=0;i<333;i++) assert(XFER[i]==(unsigned char)i);
    assert(XFER[333]==0xA5);
    reset(0);assert(!cpc_fs_read() && calls==1 && io_status==1 && XFER[0]==0xA5);
    reset(1024);selected[8]=255;selected[9]=1;length=129;
    assert(cpc_fs_read()==129 && calls==2 && !io_status);
    assert(XFER[0]==255 && XFER[1]==0 && XFER[128]==127 && selected[8]==255 && selected[9]==1);
    for(unsigned int leaf=1;leaf<=4;leaf++) {
        reset(1024);fail_at=leaf;
        assert(cpc_fs_read()==128*(leaf-1) && calls==leaf && io_status==5);
        assert(!selected[8] && XFER[128*(leaf-1)]==0xA5);
        /* Same context offset: retry must start at zero, not after the prefix. */
        fail_at=0;assert(cpc_fs_read()==512 && !io_status && XFER[0]==0 && XFER[511]==255);
    }
    reset(1024);bad_name=1;io_status=0;
    assert(!cpc_fs_read() && !calls && io_status>=2);
    reset(1024);memset(selected+8,255,4);io_status=1;length=1;
    assert(!cpc_fs_read() && !calls && io_status>=2);
    reset(1024);oversized_reply=1;
    assert(!cpc_fs_read() && calls==1 && io_status>=2 && XFER[0]==0xA5);
    puts("CPC read provider: chunking, EOF, errors, retry and bounds PASS");
    return 0;
}
