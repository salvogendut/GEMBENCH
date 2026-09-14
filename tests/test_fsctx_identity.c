#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../lib/gembench/gbfsctx_identity.c"

unsigned char gb_ufs_request[32],gb_ufs_transfer[512];
static gb_sysinfo_v6_t info;
static unsigned char absent,calls,error;
static unsigned int actual=60;
const gb_sysinfo_v6_t *gb_universal_sysinfo(void) {return absent ? 0 : &info;}
unsigned char gb_fsctx_call(unsigned char op)
{
    ++calls;assert(op==15 && GB_FSCTX_WORD_AT(2)==0x0203);
    GB_FSCTX_WORD_AT(10)=actual;
    return error;
}
int main(void)
{
    gb_fsctx_identity_t out,old;
    assert(sizeof(out)==60);
    memset(&old,0xA5,sizeof(old));out=old;
    absent=1;assert(gb_fsctx_identity(0x0203,&out)==GB_FSCTX_ERR_UNSUPPORTED);
    absent=0;info.filesystem_api_version=1;
    assert(gb_fsctx_identity(0x0203,&out)==GB_FSCTX_ERR_UNSUPPORTED && !calls);
    info.filesystem_api_version=2;
    assert(gb_fsctx_identity(0x0203,0)==GB_FSCTX_ERR_BADARG && !calls);
    memset(gb_ufs_transfer,0,sizeof(gb_ufs_transfer));
    gb_ufs_transfer[0]=2;memcpy(gb_ufs_transfer+1,"EXACT   TXT",11);
    strcpy((char *)gb_ufs_transfer+12,"/DEEP/PATH");
    for(error=1;error<=GB_FSCTX_ERR_CONTEXT;++error) {
        assert(gb_fsctx_identity(0x0203,&out)==error);
        assert(!memcmp(&out,&old,sizeof(out)));
    }
    error=0;actual=59;assert(gb_fsctx_identity(0x0203,&out)==GB_FSCTX_ERR_BADARG);
    actual=61;assert(gb_fsctx_identity(0x0203,&out)==GB_FSCTX_ERR_BADARG);
    assert(!memcmp(&out,&old,sizeof(out)));
    actual=60;assert(gb_fsctx_identity(0x0203,&out)==0);
    assert(out.drive==2 && !memcmp(out.name,"EXACT   TXT",11) && !strcmp(out.path,"/DEEP/PATH"));
    memset(gb_ufs_transfer,0x5A,sizeof(gb_ufs_transfer));
    assert(!strcmp(out.path,"/DEEP/PATH"));
    puts("filesystem identity client: PASS");
    return 0;
}
