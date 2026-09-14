/* Portable binding to shared kernel policy; no app-local payload buffer. */
#include "gbuniversal.h"
#include "gbscrap.h"

static unsigned char header[8];
extern unsigned int gb_uparam_call(const gb_params_t *request);

static unsigned char transfer(unsigned char action, unsigned char type,
                               const char *data, unsigned int length)
{
    gb_params_t request;
    unsigned char status;
    header[0] = action;
    header[2] = type;
    header[4] = (unsigned char)(unsigned int)data;
    header[5] = (unsigned char)((unsigned int)data >> 8);
    header[6] = (unsigned char)length;
    header[7] = (unsigned char)(length >> 8);
    request.operation = GB_PARAMS_CLIPBOARD;
    request.version = GB_PARAMS_VERSION;
    request.data[0] = (unsigned char)(unsigned int)header;
    request.data[1] = (unsigned char)((unsigned int)header >> 8);
    request.data[2] = 8;
    request.data[3] = 0;
    status = (unsigned char)(gb_uparam_call(&request) >> 8);
    if (status) {
        header[2] = header[6] = header[7] = 0;
        if (status == GB_PARAMS_CONTEXT) return GB_SCRAP_ERR_CONTEXT;
        if (status == GB_PARAMS_UNSUPPORTED) return GB_SCRAP_ERR_UNSUPPORTED;
        return status == GB_PARAMS_BADARG ? GB_SCRAP_ERR_ARGUMENT : GB_SCRAP_ERR_STATE;
    }
    return header[1];
}

unsigned char gb_scrap_set(unsigned char type, const char *data, unsigned int length)
{
    return transfer(1, type, data, length);
}

unsigned char gb_scrap_query(gb_scrap_info_t *info)
{
    unsigned char status;
    if (!info) return GB_SCRAP_ERR_ARGUMENT;
    status = transfer(0, 0, 0, 0);
    info->type = header[2];
    info->length = header[6] | ((unsigned int)header[7] << 8);
    return status;
}

unsigned char gb_scrap_type(void)
{
    (void)transfer(0, 0, 0, 0);
    return header[2];
}

unsigned char gb_scrap_get(unsigned char type, char *data,
                           unsigned int capacity, unsigned int *copied)
{
    unsigned char status;
    if (!copied) return GB_SCRAP_ERR_ARGUMENT;
    *copied = 0;
    status = transfer(2, type, data, capacity);
    *copied = header[6] | ((unsigned int)header[7] << 8);
    return status;
}

void gb_scrap_clear(void)
{
    (void)transfer(3, 0, 0, 0);
}
