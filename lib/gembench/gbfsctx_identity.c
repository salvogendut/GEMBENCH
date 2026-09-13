/* Optional filesystem API v2 SDK helper. No new private-memory dependencies. */
#include "gbuniversal.h"
#include "gbfsctx.h"
#include <string.h>

extern unsigned char gb_fsctx_call(unsigned char op);

unsigned char gb_fsctx_identity(gb_fsctx_t context,gb_fsctx_identity_t *out)
{
    const gb_sysinfo_v6_t *info;
    unsigned char result;
    if(!out)return GB_FSCTX_ERR_BADARG;
    info=gb_universal_sysinfo();
    if(!info || info->filesystem_api_version<GB_FSCTX_IDENTITY_API_VERSION)
        return GB_FSCTX_ERR_UNSUPPORTED;
    GB_FSCTX_WORD_AT(2)=context;
    result=gb_fsctx_call(15);
    if(result)return result;
    if(GB_FSCTX_WORD_AT(10)!=GB_FSCTX_IDENTITY_BYTES)return GB_FSCTX_ERR_BADARG;
    memcpy(out,(const void *)GB_FSCTX_TRANSFER,GB_FSCTX_IDENTITY_BYTES);
    return GB_FSCTX_OK;
}
