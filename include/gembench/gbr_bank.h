#ifndef GEMBENCH_GBR_BANK_H
#define GEMBENCH_GBR_BANK_H

/* MSX2-only auxiliary mapper-segment transport for GBR resources. The kernel
 * owns page switching; application code is always restored before these calls
 * return. Names use the kernel's raw 11-byte, space-padded 8.3 form. */
#define GBR_SEGMENT_READ_MAX 32u

unsigned char gbr_segment_load(const char *name11, unsigned int *size);
unsigned char gbr_segment_read(unsigned char segment, unsigned int offset,
                               unsigned char *data, unsigned char length);
void gbr_segment_free(unsigned char segment);

#endif
