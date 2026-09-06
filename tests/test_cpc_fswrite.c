/* Execute the real CPC provider with mocked transport, not a second policy. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static unsigned char ram[65536],selected[144],file[2048];
static unsigned int length,calls,fail_at,file_size;
static unsigned char io_status,transport_error;
static const char *free_reply;
#define CPC_SELECTED selected
#define CTX_OFFSET 8
#define REQ_LENGTH length
#define CPC_PACKET (ram+0x6000)
#define CPC_IO_PATH (ram+0x6020)
#define CPC_BUFFER (ram+0x6080)
#define CPC_FILE (ram+0x2500)
#define XFER (ram+0x1500)
#define CPC_RESPONSE (ram+0x1B00)
#define CPC_IO_STATUS io_status
#define U16(a) (*(uint16_t *)(ram+(a)))
static void copy_bytes(volatile unsigned char *d,const volatile unsigned char *s,unsigned int n)
{ while(n--) *d++=*s++; }
static unsigned char cpc_fs_filename(void) { memcpy(CPC_FILE,"/A.BIN",7);return 7; }
static unsigned char exchange(unsigned char cmd,unsigned char n)
{
    assert(cmd==9 && n==0);
    size_t len=strlen(free_reply);assert(len<130);
    memset(CPC_RESPONSE,0xA5,136);memcpy(CPC_RESPONSE+3,free_reply,len);
    CPC_RESPONSE[0]=(unsigned char)(len+2);
    return transport_error;
}
static unsigned int cpc_fs_read128(void)
{
    unsigned int n=U16(0x6008);assert(n<=128);
    assert(!memcmp(CPC_IO_PATH,"/A.BIN",7));
    assert(CPC_PACKET[0]==2 || CPC_PACKET[0]==3);
    calls++;io_status=0;
    if(calls==fail_at) {io_status=3;return 0;}
    if(CPC_PACKET[0]==2) file_size=0;
    assert(file_size+n<=sizeof(file));
    memcpy(file+file_size,CPC_BUFFER,n);file_size+=n;
    return n;
}
#include "../kernel/kc/cpc_fswrite.inc"
int main(void)
{
    for(unsigned i=0;i<512;i++) XFER[i]=(unsigned char)i;
    unsigned char before[512];memcpy(before,XFER,512);
    length=512;assert(cpc_fs_write());assert(calls==4 && file_size==512);
    assert(!memcmp(before,file,512) && !memcmp(before,XFER,512));
    selected[8]=1;length=129;assert(cpc_fs_write());
    assert(calls==6 && file_size==641 && !memcmp(file+512,before,129));
    assert(selected[8]==1); /* only the shared policy may advance the offset */
    length=0;assert(cpc_fs_write());assert(file_size==641 && calls==7);
    selected[8]=0;assert(cpc_fs_write());assert(!file_size && calls==8);
    length=512;fail_at=calls+3;assert(!cpc_fs_write());
    assert(file_size==256 && !memcmp(file,before,256)); /* non-atomic failed prefix */
    assert(!memcmp(before,XFER,512) && !selected[8]);
    unsigned int kib;
    const char *valid[]={"\r\n32760K free\r\n\r\n","0K","65535K","65536K","4294967295K"};
    const unsigned int values[]={32760,0,65535,65535,65535};
    for(unsigned i=0;i<sizeof(values)/sizeof(*values);i++) {
        free_reply=valid[i];kib=123;assert(cpc_fs_free(&kib));assert(kib==values[i]);
    }
    const char *bad[]={"","  ","123","123B","-1K","x123K","65536X"};
    for(unsigned i=0;i<sizeof(bad)/sizeof(*bad);i++) {
        free_reply=bad[i];kib=123;assert(!cpc_fs_free(&kib));assert(kib==123);
    }
    transport_error=3;free_reply="123K";assert(!cpc_fs_free(&kib));
    puts("CPC write/free provider: PASS");return 0;
}
