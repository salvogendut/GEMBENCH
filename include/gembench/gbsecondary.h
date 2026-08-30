#ifndef GEMBENCH_GBSECONDARY_H
#define GEMBENCH_GBSECONDARY_H

#include "gb.h"

/* Architecture Milestone 6 (#41): one optional GBAP v3 secondary-code image
 * can be copied into an application-owned 16 KiB page before publication.
 * Calls are synchronous and root-task-only. Parameters and results cross the
 * mapping boundary through the fixed 512-byte transfer area, never through a
 * pointer into the primary or secondary mapper page. */
typedef struct {
    gb_page_t page;
    unsigned int length;
} gb_secondary_t;

#define GB_SECONDARY_OK              0u
#define GB_SECONDARY_ERR_UNSUPPORTED 1u
#define GB_SECONDARY_ERR_STALE       2u
#define GB_SECONDARY_ERR_OWNER       3u
#define GB_SECONDARY_ERR_BUSY        4u
#define GB_SECONDARY_ERR_BADARG      5u
#define GB_SECONDARY_ERR_CONTEXT     6u
#define GB_SECONDARY_ERR_FORMAT      7u
#define GB_SECONDARY_ERR_NOMEM       8u
#define GB_SECONDARY_ERR_TEARDOWN    9u

#define GB_SECONDARY_TRANSFER_MAX 512u
#define gb_secondary_transfer() ((volatile unsigned char *)0xC400)

unsigned char gb_secondary_open(gb_secondary_t *secondary);
unsigned char gb_secondary_call(gb_secondary_t *secondary,
                                unsigned int entry_offset);

#endif
