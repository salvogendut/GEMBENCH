/* App-side marshalling for the MSX2 resident GBR mapper service. */
#include "gbr_bank.h"

#define MSX_GBR_NAME  ((volatile unsigned char *)0xC180)
#define MSX_GBR_PAGE  (*(volatile unsigned char *)0xC18B)
#define MSX_GBR_SIZE  (*(volatile unsigned int *)0xC18C)
#define MSX_GBR_OFF   (*(volatile unsigned int *)0xC18E)
#define MSX_GBR_DST   (*(volatile unsigned int *)0xC190)
#define MSX_GBR_LEN   (*(volatile unsigned char *)0xC192)

#define GBR_SEGMENT_SIZE 0x4000u

unsigned char gbr_segment_call(unsigned char operation);

unsigned char gbr_segment_load(const char *name11, unsigned int *size)
{
    unsigned char index;
    unsigned char segment;
    if (name11 == 0 || size == 0) return 0;
    for (index = 0; index < 11u; index++) MSX_GBR_NAME[index] = name11[index];
    MSX_GBR_PAGE = 0;
    MSX_GBR_SIZE = 0;
    segment = gbr_segment_call(0);
    if (segment == 0) return 0;
    *size = MSX_GBR_SIZE;
    return segment;
}

unsigned char gbr_segment_read(unsigned char segment, unsigned int offset,
                               unsigned char *data, unsigned char length)
{
    unsigned int end;
    unsigned char count;
    if (segment == 0 || data == 0) return 0;
    end = (unsigned int)(offset + length);
    if (end < offset || end > GBR_SEGMENT_SIZE) return 0;
    while (length != 0) {
        count = length > GBR_SEGMENT_READ_MAX ? GBR_SEGMENT_READ_MAX : length;
        MSX_GBR_PAGE = segment;
        MSX_GBR_OFF = offset;
        MSX_GBR_DST = (unsigned int)data;
        MSX_GBR_LEN = count;
        if (!gbr_segment_call(1)) return 0;
        offset = (unsigned int)(offset + count);
        data += count;
        length = (unsigned char)(length - count);
    }
    return 1;
}

void gbr_segment_free(unsigned char segment)
{
    if (segment == 0) return;
    MSX_GBR_PAGE = segment;
    (void)gbr_segment_call(2);
}
