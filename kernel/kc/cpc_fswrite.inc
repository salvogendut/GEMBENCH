/* Native binding only: shared policy owns validation, logical offset and status.
 * Match MSX: offset zero replaces, any nonzero offset appends at actual EOF.
 * Completed prefixes on a later failure are NOT rolled back; logical state is
 * advanced only on complete success, exactly as the shared write contract says.
 */
static unsigned char cpc_fs_write(void)
{
    unsigned char i,len=cpc_fs_filename(),append;
    unsigned int total=0,amount,got;
    if (!len) return 0;
    append=CPC_SELECTED[CTX_OFFSET] || CPC_SELECTED[CTX_OFFSET+1u] ||
           CPC_SELECTED[CTX_OFFSET+2u] || CPC_SELECTED[CTX_OFFSET+3u];
    do {
        amount=REQ_LENGTH-total;
        if (amount>128u) amount=128u;
        for (i=0;i<16u;i++) CPC_PACKET[i]=0;
        CPC_PACKET[0]=append?3u:2u;
#ifdef CPC_FAULT_FS_APPEND
        CPC_PACKET[0]=2u; /* negative: accidentally truncate on each chunk */
#endif
        CPC_PACKET[1]=1;
        U16(0x6002u)=0x6020u;
        CPC_PACKET[4]=len;
        U16(0x6006u)=0x6080u;
        U16(0x6008u)=amount;
        copy_bytes(CPC_IO_PATH,CPC_FILE,len);
        copy_bytes(CPC_BUFFER,XFER+total,amount);
        got=cpc_fs_read128(); /* shared native request gate, now read/write/append */
        if (CPC_IO_STATUS || got!=amount) return 0;
        total+=amount;
        append=1;
    } while (total<REQ_LENGTH);
    return 1;
}

/* C_FREE is bounded ASCII, not a binary counter. Saturate the public u16 KiB
 * result; validate through its K suffix instead of accepting a wrapped prefix.
 * Transport/parse failure returns unsupported through the existing shared hook.
 */
static unsigned char cpc_fs_free(unsigned int *out)
{
    unsigned char i=3,ch,seen=0;
    unsigned int value=0;
    if (exchange(9u,0u)) return 0;
    while (i<=CPC_RESPONSE[0]) {
        ch=CPC_RESPONSE[i++];
        if (ch>='0' && ch<='9') {
            ch-='0';
            if (value>6553u || (value==6553u && ch>5u)) value=65535u;
            else value=value*10u+ch;
            seen=1;
        } else if (seen) {
            if (ch!='K') return 0;
            *out=value;
            return 1;
        } else if (ch!=' ' && ch!='\r' && ch!='\n') return 0;
    }
    return 0;
}
