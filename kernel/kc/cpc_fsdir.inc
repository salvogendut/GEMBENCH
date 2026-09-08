/* M4 directory binding only. The shared module owns handles, ownership, batch
 * publication and the opaque per-context cursor. No caller buffer is scratch.
 * Cursor: ordinal LE16, tag D1, reserved bytes, normalized path at offset 16.
 * Replay is bounded to 1024 entries per activation; exceeding it is FULL, never
 * a successful EOF. Within one <=4-entry shared batch the device cursor is live.
 * Mutation during enumeration has no snapshot guarantee; callers restart FIRST.
 */
static char *directory_error(unsigned char error)
{
    CPC_DIR_STATUS=error;
    CPC_DIR_LIVE=0;
    return (char *)0;
}

static unsigned char directory_read(void)
{
    CPC_COMMAND[3]=64u;
    if (exchange(6u,1u)) return 2u;
    if (CPC_RESPONSE[0]==2u) return 0u;
    /* Returned first string must be terminated within the copied frame. */
    return 1u;
}

static char *cpc_fs_directory(unsigned char first)
{
    unsigned int ordinal,skip;
    unsigned char i,start,len,ch,part,pos,directory;
    CPC_DIR_STATUS=OK;
    if (first) {
        zero_bytes(FSCTX_CURSOR,FSCTX_CURSOR_SIZE);
        FSCTX_CURSOR[2]=0xD1u;
        len=0;
        while (CPC_PATH[len]) len++;
        copy_bytes(FSCTX_CURSOR+16u,CPC_PATH,len+1u);
        CPC_DIR_LIVE=0;
    } else {
        if (FSCTX_CURSOR[2]!=0xD1u) return directory_error(BADARG);
        for (i=0;i<48u;i++) {
            if (FSCTX_CURSOR[16u+i]!=CPC_PATH[i]) return directory_error(BADARG);
            if (!CPC_PATH[i]) break;
        }
    }
    ordinal=U16(FSCTX_CURSOR_ADDRESS);
    if (ordinal>=CPC_DIR_LIMIT) return directory_error(FULL);
    if (!CPC_DIR_LIVE) {
        CPC_COMMAND[3]=0;
        if (exchange(0x25u,1u) || CPC_RESPONSE[0]!=2u) return directory_error(IOERR);
        for (skip=0;skip<ordinal;skip++) {
            if (directory_read()!=1u) return directory_error(IOERR);
        }
        CPC_DIR_LIVE=1;
    }
    i=directory_read();
    if (!i) return (char *)0;
    if (i!=1u) return directory_error(IOERR);
    directory=CPC_RESPONSE[3]=='>';
    start=directory?4u:3u;
    len=0;
    while ((unsigned int)start+len<=CPC_RESPONSE[0]) {
        ch=CPC_RESPONSE[start+len];
        if (!ch) break;
        if (len>=63u || ch<32u || ch>=127u || ch=='/' || ch=='\\') return directory_error(UNSUPPORTED);
        CPC_FILE[len++]=ch;
    }
    if (!len || (unsigned int)start+len>CPC_RESPONSE[0]) return directory_error(IOERR);
    CPC_FILE[len++]=0;
    copy_bytes(CPC_COMMAND+3u,CPC_FILE,len);
    if (exchange(0x16u,len) || CPC_RESPONSE[0]<25u || CPC_RESPONSE[3]) return directory_error(IOERR);
    if (!!(CPC_RESPONSE[12]&0x10u)!=!!directory) return directory_error(IOERR);
    /* Canonical short alias from FSTAT, not the display/long name. */
    for (i=0;i<11u;i++) CPC_DIR_ENTRY[i]=' ';
    part=0;pos=0;
    for (i=0;i<13u;i++) {
        ch=CPC_RESPONSE[13u+i];
        if (!ch) break;
        if (ch=='.') {
            if (part || !pos) return directory_error(UNSUPPORTED);
            part=1;pos=0;continue;
        }
        if (!path_char(ch) || pos>=(part?3u:8u)) return directory_error(UNSUPPORTED);
        CPC_DIR_ENTRY[(part?8u:0u)+pos++]=ch;
    }
    if (i==13u || !pos) return directory_error(UNSUPPORTED);
    CPC_DIR_ENTRY[11]=CPC_RESPONSE[12];
    copy_bytes(CPC_DIR_ENTRY+12u,CPC_RESPONSE+4u,4u);
#ifdef CPC_FAULT_FS_META
    CPC_DIR_ENTRY[14]=0; CPC_DIR_ENTRY[15]=0;
#endif
    U16(FSCTX_CURSOR_ADDRESS)=ordinal+1u;
    return (char *)CPC_DIR_ENTRY;
}
