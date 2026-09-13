#ifndef GEMBENCH_GBCOMPUTE_H
#define GEMBENCH_GBCOMPUTE_H
#include "gbuniversal.h"

/* UNIVERSAL_COMPUTE=1, portable-secondary-calls capability. Invoke the single
 * sealed computation entry loaded with this APP. Block must be a primary
 * object, not a kernel-stack object; 1..512 bytes are copied in and out.
 * Root callbacks only. Returns GB_PARAMS_*; no page IDs or code offsets.
 */
unsigned char gb_compute(void *block, unsigned int length);
#endif
