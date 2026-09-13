#include "gbcompute.h"
#include <string.h>
extern unsigned int gb_uparam_call(const gb_params_t *request);
unsigned char gb_compute(void *block, unsigned int length)
{
    gb_params_t request;
    unsigned int pointer=(unsigned int)block;
    memset(&request,0,sizeof(request));
    request.operation=GB_PARAMS_SECONDARY_CALL;
    request.version=GB_PARAMS_VERSION;
    request.data[0]=(unsigned char)pointer;request.data[1]=(unsigned char)(pointer>>8);
    request.data[2]=(unsigned char)length;request.data[3]=(unsigned char)(length>>8);
    return (unsigned char)(gb_uparam_call(&request)>>8);
}
