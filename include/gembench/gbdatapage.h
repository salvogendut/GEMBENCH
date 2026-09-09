#ifndef GEMBENCH_GBDATAPAGE_H
#define GEMBENCH_GBDATAPAGE_H
#include "gbuniversal.h"

/* UNIVERSAL_DATA_PAGES=1; optional portable-data-pages capability. No native
 * bank numbers, mapping windows, or executable page access. Root callbacks
 * only, non-reentrant. Buffers are caller-owned primary objects (not stack).
 * One call copies <=512 bytes; allocation contents are unspecified. Owner
 * teardown reclaims live handles. A failed release does not consume a handle.
 */
typedef unsigned int gb_data_page_t;
#define GB_DATA_PAGE_SIZE 16384u
#define GB_DATA_PAGE_TRANSFER_MAX 512u
#define GB_DATA_PAGE_OK 0u
#define GB_DATA_PAGE_UNSUPPORTED 1u
#define GB_DATA_PAGE_STALE 2u
#define GB_DATA_PAGE_OWNER 3u
#define GB_DATA_PAGE_FREE 4u
#define GB_DATA_PAGE_NOMEM 5u
#define GB_DATA_PAGE_BADARG 6u
#define GB_DATA_PAGE_CONTEXT 7u

gb_data_page_t gb_data_page_alloc(void);
unsigned char gb_data_page_free(gb_data_page_t page);
unsigned char gb_data_page_read(gb_data_page_t page, unsigned int offset,
                                char *buffer, unsigned int length);
unsigned char gb_data_page_write(gb_data_page_t page, unsigned int offset,
                                 const char *buffer, unsigned int length);
unsigned char gb_data_page_status(void);
#endif
