#include <stddef.h>
#include <stdio.h>

#include "gbfsctx.h"

#ifdef __SDCC
typedef char entry_name_offset[offsetof(gb_fsctx_entry_t, name) == 0 ? 1 : -1];
typedef char entry_attr_offset[offsetof(gb_fsctx_entry_t, attributes) == 11 ? 1 : -1];
typedef char entry_size_offset[offsetof(gb_fsctx_entry_t, size) == 12 ? 1 : -1];
typedef char entry_record_size[sizeof(gb_fsctx_entry_t) == 16 ? 1 : -1];
#endif

int main(void)
{
    if (GB_FSCTX_CAPACITY != 4 || GB_FSCTX_TRANSFER_MAX != 512 ||
        GB_FSCTX_PATH_MAX != 47 || GB_FSCTX_DIRECTORY_BATCH != 4 ||
        GB_FSCTX_API_VERSION != 1 ||
        GB_CAP_FS_CONTEXTS != 0x1000u)
        return 1;
    if (GB_FSCTX_OK != 0 || GB_FSCTX_ERR_STALE != 2 ||
        GB_FSCTX_ERR_OWNER != 3 || GB_FSCTX_ERR_FULL != 4 ||
        GB_FSCTX_ERR_BADARG != 5 || GB_FSCTX_ERR_IO != 6 ||
        GB_FSCTX_ERR_CONTEXT != 7)
        return 1;
    puts("gbfsctx contract tests: ok");
    return 0;
}
