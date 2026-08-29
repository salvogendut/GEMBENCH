#ifndef GEMBENCH_GBSCRAP_H
#define GEMBENCH_GBSCRAP_H

/*
 * Bounded typed access to GeoBench's existing shared clipboard.
 *
 * The raw gb_clip_* API remains the storage contract and retains its complete
 * 510-byte payload.  A private low-RAM tag describes payloads written through
 * this source API; a raw gb_clip_set() invalidates that tag and is reported as
 * GB_SCRAP_UNTYPED.
 */

#define GB_SCRAP_CAPACITY 510u

#define GB_SCRAP_UNTYPED  0u
#define GB_SCRAP_TEXT     1u
#define GB_SCRAP_BITMAP   2u
#define GB_SCRAP_ICON     3u
#define GB_SCRAP_FILELIST 4u
#define GB_SCRAP_ANY      255u

#define GB_SCRAP_OK             0u
#define GB_SCRAP_TRUNCATED      1u
#define GB_SCRAP_ERR_ARGUMENT   2u
#define GB_SCRAP_ERR_TYPE       3u
#define GB_SCRAP_ERR_MISMATCH   4u
#define GB_SCRAP_ERR_STATE      5u

typedef struct {
    unsigned int length;
    unsigned char type;
} gb_scrap_info_t;

/*
 * Store a typed payload. Oversized input is explicitly truncated to the raw
 * clipboard capacity and returns GB_SCRAP_TRUNCATED. Invalid arguments or an
 * unsupported type leave the previous clipboard untouched. A zero-length
 * payload clears the clipboard.
 */
unsigned char gb_scrap_set(unsigned char type, const char *data,
                           unsigned int length);

/* Return the normalized current type without copying the payload. */
unsigned char gb_scrap_type(void);

/* Snapshot the current normalized type and length. Unknown tags are untyped. */
unsigned char gb_scrap_query(gb_scrap_info_t *info);

/*
 * Copy up to capacity bytes when the current type matches expected_type.
 * GB_SCRAP_ANY accepts typed and untyped data. The copied count is always
 * initialized; a short destination returns GB_SCRAP_TRUNCATED.
 */
unsigned char gb_scrap_get(unsigned char expected_type, char *data,
                           unsigned int capacity, unsigned int *copied);

/* Clear both payload and type metadata. */
void gb_scrap_clear(void);

#endif
