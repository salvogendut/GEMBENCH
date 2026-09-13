/* Primary-side model mirror and copied commands; never a banked pointer. */
#include "gbcompute.h"
#include "protocol.h"
typedef struct {
    unsigned int len,cur,first,anchor,sel_a,sel_b,total,c_row;
    unsigned char selected,dirty,c_col;
} np_view_t;
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
    editor.len=np_word(packet+8);editor.cur=np_word(packet+10);
    editor.first=np_word(packet+12);editor.anchor=np_word(packet+14);
    editor.sel_a=np_word(packet+16);editor.sel_b=np_word(packet+18);
    editor.selected=packet[20];editor.dirty=packet[21];
    editor.total=np_word(packet+22);editor.c_row=np_word(packet+24);editor.c_col=packet[26];
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
