/* Primary-side model mirror and copied commands; never a banked pointer. */
#include "gbcompute.h"
#include "protocol.h"
#include <stdint.h>
#include <stddef.h>
typedef struct {
    uint16_t len,cur,first,anchor,sel_a,sel_b;
    uint8_t selected,dirty;
    uint16_t total,c_row;
    uint8_t c_col;
} np_view_t;
typedef char np_view_wire_layout[(offsetof(np_view_t,selected)==12 &&
    offsetof(np_view_t,total)==14 && offsetof(np_view_t,c_col)==18) ? 1 : -1];
np_view_t editor; /* named for read-only runtime observations */
/* Owned primary FS transfer scratch is idle during computation. FS calls
 * overwrite it, so keep model metadata in the separate snapshot above. */
#define packet gb_ufs_transfer
static unsigned char model_fault;
static unsigned char wrap,rows;
static unsigned char model_call(unsigned char op)
{
    packet[0]=op;packet[7]=wrap;packet[28]=rows;
    if(gb_compute(packet,NP_PACKET)!=GB_PARAMS_OK) { model_fault=1;return 0; }
    /* Fixed-width mirror follows the wire snapshot. Host compilers may append
     * tail padding: copy only the 19 defined bytes, never sizeof(editor). */
    memcpy(&editor,packet+8,19);
    return !packet[1];
}
static unsigned char model_stage(const char *data,unsigned int count,unsigned int at)
{
    unsigned int n;
    while(count) {
        n=count>NP_CHUNK ? NP_CHUNK : count;
        np_put(packet+2,at);np_put(packet+4,n);memcpy(packet+NP_DATA,data,n);
        if(!model_call(NP_STAGE_APPEND))return 0;
        at+=n;data+=n;count-=n;
    }
    return 1;
}
