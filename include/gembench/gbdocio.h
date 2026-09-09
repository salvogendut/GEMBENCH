#ifndef GEMBENCH_GBDOCIO_H
#define GEMBENCH_GBDOCIO_H

#include "gbfsctx.h"

/* SDK helper, not a new kernel ABI. Zero-initialize each caller-owned job.
 * Root callbacks only: call step at most once per frame. Each step makes at
 * most one synchronous filesystem operation, transferring at most 512 bytes.
 * This bounds work size, not the duration of a storage-provider call.
 *
 * The caller lends an exclusively used context with path/name already set,
 * and a primary-page buffer that remains valid until completion/cancellation.
 * Neither context nor buffer is allocated, closed or released here. Universal
 * jobs (including the EOF probe byte) must also live in the primary app page.
 * Do not share a context between active jobs or change it between steps.
 *
 * Load copies raw bytes without adding a terminator or translating newlines.
 * ERROR/CANCELLED may leave a prefix in the destination: publish only DONE.
 * Preserving an old document requires separate staging owned by the caller.
 * Save rewinds then replaces the file, including truncation for length zero.
 * Failure/cancellation can leave a partial file; there is no atomic rollback.
 * Keep the source unchanged while saving; clear dirty state only after DONE.
 */
#define GB_DOCIO_IDLE          0u
#define GB_DOCIO_DONE          1u
#define GB_DOCIO_ERROR         2u
#define GB_DOCIO_CANCELLED     3u
#define GB_DOCIO_LOAD_REWIND   4u
#define GB_DOCIO_LOAD          5u
#define GB_DOCIO_LOAD_EOF      6u
#define GB_DOCIO_SAVE_REWIND   7u
#define GB_DOCIO_SAVE          8u

/* job.error otherwise contains the original GB_FSCTX_ERR_* value. */
#define GB_DOCIO_ERR_TOO_LARGE 0x80u

typedef struct {
    gb_fsctx_t context;
    union {
        char *load;
        const char *save;
    } buffer;
    unsigned int limit;
    unsigned int transferred;   /* confirmed prefix, not a success indication */
    unsigned char state;
    unsigned char error;
    char probe;
} gb_docio_t;

/* Begin returns 1 if accepted. Busy/invalid requests return 0, leaving the
 * existing job unchanged. No I/O occurs until step. NULL buffers are allowed
 * only with zero capacity/length. Initialize with {0}, then use these helpers;
 * observe the fields but do not modify them while a job is active. */
unsigned char gb_docio_load(gb_docio_t *job, gb_fsctx_t context,
                            char *buffer, unsigned int capacity);
unsigned char gb_docio_save(gb_docio_t *job, gb_fsctx_t context,
                            const char *buffer, unsigned int length);
unsigned char gb_docio_busy(const gb_docio_t *job);
/* Returns the resulting state; terminal/idle steps do nothing. */
unsigned char gb_docio_step(gb_docio_t *job);
/* Stops future steps, retaining progress/error. Does no I/O: these calls are
 * synchronous, so nothing remains in flight between steps. Returns 1 only
 * when an active job was cancelled. The caller still owns its context. */
unsigned char gb_docio_cancel(gb_docio_t *job);

#endif
