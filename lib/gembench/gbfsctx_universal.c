/* Reuse the native client policy with application-owned storage and transport.
 * Root callbacks only: workers must not enter this non-reentrant client. */
#include "gbuniversal.h"
#include "gbfsctx.h"

unsigned char gb_ufs_request[32];
unsigned char gb_ufs_transfer[512];
extern unsigned int gb_uparam_call(const gb_params_t *request);

unsigned char gb_fsctx_call(unsigned char op)
{
    gb_params_t request;
    unsigned char status;
    gb_ufs_request[0] = op;
    request.operation = GB_PARAMS_FILESYSTEM;
    request.version = GB_PARAMS_VERSION;
    request.data[0] = (unsigned char)(unsigned int)gb_ufs_request;
    request.data[1] = (unsigned char)((unsigned int)gb_ufs_request >> 8);
    request.data[2] = 32;
    request.data[3] = 0;
    request.data[4] = (unsigned char)(unsigned int)gb_ufs_transfer;
    request.data[5] = (unsigned char)((unsigned int)gb_ufs_transfer >> 8);
    request.data[6] = 0;
    request.data[7] = 2;
    status = (unsigned char)(gb_uparam_call(&request) >> 8);
    if (status) {
        gb_ufs_request[1] = status == GB_PARAMS_UNSUPPORTED ? GB_FSCTX_ERR_UNSUPPORTED :
                           status == GB_PARAMS_CONTEXT ? GB_FSCTX_ERR_CONTEXT : GB_FSCTX_ERR_BADARG;
    }
    return gb_ufs_request[1];
}
