#ifndef GEMBENCH_GBFSCTX_H
#define GEMBENCH_GBFSCTX_H

#include "gb.h"

/* Architecture Milestone 4 (#37): four generation-tagged filesystem contexts.
 * The MSX2 implementation serializes native DOS access but retains drive, path,
 * name, offset and directory enumeration state independently for each owner.
 * Every transfer advances at most one 512-byte chunk on the root task. */
typedef unsigned int gb_fsctx_t;

#define GB_FSCTX_CAPACITY       4u
#define GB_FSCTX_TRANSFER_MAX 512u
#define GB_FSCTX_PATH_MAX      47u
#define GB_FSCTX_DIRECTORY_BATCH 4u
#define GB_FSCTX_API_VERSION    1u

#include "gbfsctx_platform.h"

#define GB_FSCTX_OK              0u
#define GB_FSCTX_ERR_UNSUPPORTED 1u
#define GB_FSCTX_ERR_STALE       2u
#define GB_FSCTX_ERR_OWNER       3u
#define GB_FSCTX_ERR_FULL        4u
#define GB_FSCTX_ERR_BADARG      5u
#define GB_FSCTX_ERR_IO          6u
#define GB_FSCTX_ERR_CONTEXT     7u

#define GB_FSCTX_ATTR_DIRECTORY 0x10u

typedef struct {
    char name[11];               /* raw space-padded 8.3 name */
    unsigned char attributes;
    unsigned long size;
} gb_fsctx_entry_t;

gb_fsctx_t gb_fsctx_open(unsigned char drive);
unsigned char gb_fsctx_close(gb_fsctx_t context);
unsigned char gb_fsctx_set_path(gb_fsctx_t context, const char *path);
unsigned char gb_fsctx_set_name(gb_fsctx_t context, const char *name11);
unsigned char gb_fsctx_activate(gb_fsctx_t context);
unsigned char gb_fsctx_dir_first(gb_fsctx_t context, gb_fsctx_entry_t *entry);
unsigned char gb_fsctx_dir_next(gb_fsctx_t context, gb_fsctx_entry_t *entry);
/* Fetch up to four packed entries into the fixed transfer area. The returned
 * pointer remains valid only until the next filesystem-context call. */
unsigned char gb_fsctx_dir_batch(gb_fsctx_t context, unsigned char first);
#define gb_fsctx_batch_entries() ((const gb_fsctx_entry_t *)GB_FSCTX_TRANSFER)
unsigned char gb_fsctx_rewind(gb_fsctx_t context);
unsigned int gb_fsctx_read(gb_fsctx_t context, char *buffer, unsigned int length);
unsigned char gb_fsctx_write(gb_fsctx_t context, const char *buffer,
                             unsigned int length);
unsigned char gb_fsctx_free_kib(gb_fsctx_t context, unsigned int *kib);
unsigned char gb_fsctx_cancel(gb_fsctx_t context);

/* A launcher may prepare an exact drive/path/name before GB_WMLAUNCHAS. The
 * newly loaded application can adopt it under its own owner generation. */
unsigned char gb_fsctx_prepare_launch(gb_fsctx_t context, const char *name11);
gb_fsctx_t gb_fsctx_adopt_launch(void);

/* Status of the most recent operation issued by this application. */
unsigned char gb_fsctx_status(void);

#endif
