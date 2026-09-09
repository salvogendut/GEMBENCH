#include "gbdatapage.h"
#include <string.h>
static unsigned char header[16];
extern unsigned int gb_uparam_call(const gb_params_t *request);

static unsigned char transfer(unsigned char op, gb_data_page_t page,
                               unsigned int offset, const char *buffer,
                               unsigned int length)
{
    gb_params_t request;
    unsigned int pointer;
    unsigned char status;
    memset(header,0,sizeof(header));
    header[0]=op;
    header[2]=(unsigned char)page; header[3]=(unsigned char)(page>>8);
    header[4]=(unsigned char)offset; header[5]=(unsigned char)(offset>>8);
    pointer=(unsigned int)buffer;
    header[6]=(unsigned char)pointer; header[7]=(unsigned char)(pointer>>8);
    header[8]=(unsigned char)length; header[9]=(unsigned char)(length>>8);
    memset(&request,0,sizeof(request));
    request.operation=GB_PARAMS_DATA_PAGES; request.version=GB_PARAMS_VERSION;
    pointer=(unsigned int)header;
    request.data[0]=(unsigned char)pointer; request.data[1]=(unsigned char)(pointer>>8);
    request.data[2]=sizeof(header);
    status=(unsigned char)(gb_uparam_call(&request)>>8);
    if (status) {
        header[2]=header[3]=0;
        header[1]=status==GB_PARAMS_UNSUPPORTED ? GB_DATA_PAGE_UNSUPPORTED :
                  status==GB_PARAMS_CONTEXT ? GB_DATA_PAGE_CONTEXT : GB_DATA_PAGE_BADARG;
    }
    return header[1];
}
gb_data_page_t gb_data_page_alloc(void)
{
    if (transfer(0,0,0,0,0)) return 0;
    return header[2] | ((unsigned int)header[3]<<8);
}
unsigned char gb_data_page_free(gb_data_page_t page)
{ return transfer(1,page,0,0,0); }
unsigned char gb_data_page_read(gb_data_page_t page,unsigned int offset,
                                char *buffer,unsigned int length)
{ return transfer(2,page,offset,buffer,length); }
unsigned char gb_data_page_write(gb_data_page_t page,unsigned int offset,
                                 const char *buffer,unsigned int length)
{ return transfer(3,page,offset,buffer,length); }
unsigned char gb_data_page_status(void) { return header[1]; }
