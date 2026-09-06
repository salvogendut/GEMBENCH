#include "../core/fsctx_layout.h"
#include "cpc_fsctx.h"
#include "../core/fsctx_contract.h"
#include "../core/fsctx_policy.inc"

/* Hardware path binding only. Use root + relative CD components as required
 * by the original M4 backend, then GETPATH to confirm activation: CD has no
 * status payload on the qualified protocol. Never treat an empty reply as a
 * successful directory change. No application transfer buffer is touched. */
static unsigned char path_char(unsigned char ch)
{
    return (ch>='A' && ch<='Z') || (ch>='0' && ch<='9') || ch=='_' || ch=='-' || ch=='~';
}

static unsigned char exchange(unsigned char cmd, unsigned char length)
{
    CPC_COMMAND[1]=cmd;
    CPC_COMMAND[2]=0x43u;
    CPC_COMMAND_END=0x1BA3u+length;
    return cpc_fs_exchange();
}

static unsigned char cpc_fs_activate(void)
{
    unsigned char i, start, count=0, ch, len;
#ifdef CPC_FS_DIRECTORY
    CPC_DIR_LIVE=0; /* CD invalidates the device cursor; replay on first use. */
#endif
    for (i=0;i<CTX_PATH_CAP;i++) {
        ch=CPC_SELECTED[CTX_PATH+i];
        if (ch=='\\') ch='/';
        CPC_PATH[i]=ch;
        if (!ch) break;
        if (ch=='/') {
            if (i && !count) return 1;
            count=0;
        } else {
            if (!path_char(ch) || ++count>8u) return 1;
        }
    }
    if (i==CTX_PATH_CAP || !i || CPC_PATH[0]!='/' || (i>1u && !count)) return 1;
    len=i;
    CPC_COMMAND[3]='/'; CPC_COMMAND[4]=0;
    if (exchange(8u,2u) || CPC_RESPONSE[0]!=2u) return 1;
    start=1;
    while (start<len) {
        count=0;
        while (start<len && CPC_PATH[start]!='/') CPC_COMMAND[3u+count++]=CPC_PATH[start++];
        CPC_COMMAND[3u+count++]=0;
        if (exchange(8u,count) || CPC_RESPONSE[0]!=2u) return 1;
        start++;
    }
    if (exchange(0x13u,0u) || CPC_RESPONSE[0]!=(unsigned char)(len+3u)) return 1;
    for (i=0;i<=len;i++) if (CPC_RESPONSE[3u+i]!=CPC_PATH[i]) return 1;
    return 0;
}

/* Join the validated absolute context path with its padded 8.3 file name.
 * Chunking is a hardware concern: shared policy owns the 32-bit offset and
 * advances it once by the total actual count, just as on MSX. */
static unsigned char cpc_fs_filename(void)
{
    unsigned char i=0, j, part, padded, seen, ch;
    while (CPC_PATH[i]) i++;
    /* Keep copying separate from the large read loop: SDCC 4.6.2 #16671
     * spills the duplicated volatile path load incorrectly in that loop. */
    copy_bytes(CPC_FILE,CPC_PATH,i);
    if (i>1u) CPC_FILE[i++]='/';
    for (part=0;part<2u;part++) {
        padded=0; seen=0;
        if (part && CPC_SELECTED[CTX_NAME+8u]!=' ') CPC_FILE[i++]='.';
        for (j=0;j<(part?3u:8u);j++) {
            ch=CPC_SELECTED[CTX_NAME+(part?8u:0u)+j];
            if (ch==' ') { padded=1; continue; }
            if (padded || !path_char(ch)) return 0;
            CPC_FILE[i++]=ch; seen=1;
        }
        if (!part && !seen) return 0;
    }
    CPC_FILE[i++]=0;
    return i; /* <= 61: 47-byte path + slash + 12-byte name + NUL */
}

static unsigned int cpc_fs_read(void)
{
    unsigned char i,j,len=cpc_fs_filename();
    unsigned int got,total=0,amount;
    unsigned long offset;
    if (!len) return 0;
    offset=(unsigned long)CPC_SELECTED[CTX_OFFSET] |
           ((unsigned long)CPC_SELECTED[CTX_OFFSET+1u]<<8) |
           ((unsigned long)CPC_SELECTED[CTX_OFFSET+2u]<<16) |
           ((unsigned long)CPC_SELECTED[CTX_OFFSET+3u]<<24);
    if (offset+(unsigned long)REQ_LENGTH<offset) return 0;
    while (total<REQ_LENGTH) {
        amount=REQ_LENGTH-total;
        if (amount>128u) amount=128u;
        for (i=0;i<16u;i++) CPC_PACKET[i]=0;
        CPC_PACKET[0]=1; CPC_PACKET[1]=1;
        U16(0x6002u)=0x6020u;
        CPC_PACKET[4]=len;
        U16(0x6006u)=0x6080u;
        U16(0x6008u)=amount;
        for (i=0;i<4u;i++) CPC_PACKET[10u+i]=(unsigned char)(offset>>(8u*i));
        for (i=0;i<len;i++) CPC_IO_PATH[i]=CPC_FILE[i];
        got=cpc_fs_read128();
        if (CPC_IO_STATUS>=2u) return total; /* existing zero-read/error ambiguity */
        for (j=0;j<got;j++) XFER[total+j]=CPC_BUFFER[j];
        total+=got;
        offset+=got;
        if (got<amount) break;
    }
    return total;
}

#ifdef CPC_FS_DIRECTORY
#include "cpc_fsdir.inc"
#endif

#ifdef CPC_FS_WRITE
#include "cpc_fswrite.inc"
#endif
