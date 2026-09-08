/* M4 read transport for the shared filesystem-context policy. No publication
 * of offsets/counts here: policy commits a successful request, not each leaf.
 * Kept separate so host tests execute these exact packet/chunk/error paths. */
static unsigned int cpc_fs_read(void)
{
    unsigned char i,j,len=cpc_fs_filename();
    unsigned int got,total=0,amount;
    unsigned long offset;
    CPC_IO_STATUS=2u; /* validation failures are errors, never stale EOF/OK */
    if (!len) return 0;
    offset=(unsigned long)CPC_SELECTED[CTX_OFFSET] |
           ((unsigned long)CPC_SELECTED[CTX_OFFSET+1u]<<8) |
           ((unsigned long)CPC_SELECTED[CTX_OFFSET+2u]<<16) |
           ((unsigned long)CPC_SELECTED[CTX_OFFSET+3u]<<24);
    if (offset>0xFFFFFFFFUL-(unsigned long)REQ_LENGTH) return 0;
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
        if (CPC_IO_STATUS>=2u) return total;
        if (got>amount) { CPC_IO_STATUS=2u;return total; }
        for (j=0;j<got;j++) XFER[total+j]=CPC_BUFFER[j];
        total+=got;
        offset+=got;
        if (got<amount) break;
    }
    return total;
}
