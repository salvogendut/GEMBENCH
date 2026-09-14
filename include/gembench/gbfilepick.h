#ifndef GEMBENCH_GBFILEPICK_H
#define GEMBENCH_GBFILEPICK_H

#include "gbfsctx.h"

/* Cooperative chooser, not an implicit/global filesystem view. Zero-initialize
 * the caller-owned object. Keep it and its filter string alive in primary RAM.
 * Root callbacks only; call step at most once per frame. Each step performs at
 * most one filesystem operation (directory batches contain at most 4 entries).
 * No disk writes, app callbacks, modal polling or document-buffer changes.
 *
 * DONE holds an exact named context. take() transfers ownership to the caller,
 * which must eventually close it; path/name remain available in the object.
 * Cancel/error normally release the temporary context in a subsequent step.
 * A failed close retains the handle in ERROR: cancel() retries cleanup. Never
 * discard/reinitialize a live object; owner teardown is the final safety net.
 * Directories are rescanned for previous/next pages, not snapshotted. */
#define GB_FILEPICK_ROWS 6u
#define GB_FILEPICK_OPEN 0u
#define GB_FILEPICK_SAVE 1u
#define GB_FILEPICK_IDLE 0u
#define GB_FILEPICK_ALLOC 1u
#define GB_FILEPICK_PATH 2u
#define GB_FILEPICK_ACTIVATE 3u
#define GB_FILEPICK_SCAN 4u
#define GB_FILEPICK_READY 5u
#define GB_FILEPICK_NAME 6u
#define GB_FILEPICK_DONE 7u
#define GB_FILEPICK_CANCELLED 8u
#define GB_FILEPICK_ERROR 9u
#define GB_FILEPICK_CLOSING 10u
#define GB_FILEPICK_BAD_NAME 8u
#define GB_FILEPICK_PATH_LIMIT 9u
#define GB_FILEPICK_DIRECTORY_LIMIT 10u

typedef struct {
    char name[11];
    unsigned char directory;
} gb_filepick_row_t;

typedef struct {
    gb_fsctx_t context;
    const char *extensions;       /* packed triplets, e.g. "TXTBASCFG"; NULL=all */
    unsigned int offset, scanned;
    unsigned char state, error, count, more, first, mode, drive, changed, ending;
    char path[48], name[11], edit[13];
    gb_filepick_row_t rows[GB_FILEPICK_ROWS];
} gb_filepick_t;

/* path: absolute, max 47 bytes. Filter: 0..7 uppercase alphanumeric triplets.
 * Invalid/busy begin leaves the old object unchanged, including live handles. */
unsigned char gb_filepick_begin(gb_filepick_t *p, unsigned char drive,
                                const char *path, const char *extensions,
                                unsigned char mode);
unsigned char gb_filepick_step(gb_filepick_t *p);
void gb_filepick_cancel(gb_filepick_t *p);
gb_fsctx_t gb_filepick_take(gb_filepick_t *p);
void gb_filepick_page(gb_filepick_t *p, unsigned char next);
void gb_filepick_up(gb_filepick_t *p);
void gb_filepick_choose(gb_filepick_t *p, unsigned char row);
/* SAVE: edit keys/backspace, Enter submits; Escape cancels in either mode.
 * No silent truncation of overlong/invalid 8.3 names. Existing file selection
 * only fills edit; saving always requires an explicit confirmation. */
void gb_filepick_key(gb_filepick_t *p, unsigned char key);
void gb_filepick_submit(gb_filepick_t *p);
unsigned char gb_filepick_changed(gb_filepick_t *p);
void gb_filepick_label(char *out14, const gb_filepick_row_t *row);

#endif
