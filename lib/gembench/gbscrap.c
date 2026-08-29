#include "gb.h"
#include "gbscrap.h"

#ifdef GB_SCRAP_HOST_TEST
extern unsigned char gb_scrap_host_type;
#define GB_SCRAP_TYPE gb_scrap_host_type
#else
/* Private MSX2 low-RAM metadata; the raw 510-byte clipboard remains intact. */
#define GB_SCRAP_TYPE (*(volatile unsigned char *)0x133Du)
#endif

static unsigned char valid_stored_type(unsigned char type)
{
    return (unsigned char)(type >= GB_SCRAP_TEXT &&
                           type <= GB_SCRAP_FILELIST);
}

static unsigned char valid_expected_type(unsigned char type)
{
    return (unsigned char)(type == GB_SCRAP_ANY ||
                           type == GB_SCRAP_UNTYPED ||
                           valid_stored_type(type));
}

unsigned char gb_scrap_set(unsigned char type, const char *data,
                           unsigned int length)
{
    unsigned char result = GB_SCRAP_OK;

    if (!valid_stored_type(type)) return GB_SCRAP_ERR_TYPE;
    if (length && !data) return GB_SCRAP_ERR_ARGUMENT;
    if (!length) {
        gb_scrap_clear();
        return GB_SCRAP_OK;
    }
    if (length > GB_SCRAP_CAPACITY) {
        length = GB_SCRAP_CAPACITY;
        result = GB_SCRAP_TRUNCATED;
    }

    /* gb_clip_set() first publishes an untyped, complete payload. The tag is
       written last so a reader can never observe typed partial data. */
    gb_clip_set(data, length);
    GB_SCRAP_TYPE = type;
    return result;
}

unsigned char gb_scrap_query(gb_scrap_info_t *info)
{
    unsigned int length;
    unsigned char type;

    if (!info) return GB_SCRAP_ERR_ARGUMENT;
    length = gb_clip_len();
    if (length > GB_SCRAP_CAPACITY) {
        info->length = 0;
        info->type = GB_SCRAP_UNTYPED;
        return GB_SCRAP_ERR_STATE;
    }
    type = GB_SCRAP_TYPE;
    if (!length || !valid_stored_type(type)) type = GB_SCRAP_UNTYPED;
    info->length = length;
    info->type = type;
    return GB_SCRAP_OK;
}

unsigned char gb_scrap_type(void)
{
    unsigned char type;

    if (!gb_clip_len()) return GB_SCRAP_UNTYPED;
    type = GB_SCRAP_TYPE;
    return valid_stored_type(type) ? type : GB_SCRAP_UNTYPED;
}

unsigned char gb_scrap_get(unsigned char expected_type, char *data,
                           unsigned int capacity, unsigned int *copied)
{
    gb_scrap_info_t info;
    unsigned int count;
    unsigned char result;

    if (!copied) return GB_SCRAP_ERR_ARGUMENT;
    *copied = 0;
    if (!valid_expected_type(expected_type)) return GB_SCRAP_ERR_TYPE;
    result = gb_scrap_query(&info);
    if (result != GB_SCRAP_OK) return result;
    if (expected_type != GB_SCRAP_ANY && expected_type != info.type)
        return GB_SCRAP_ERR_MISMATCH;

    count = info.length;
    result = GB_SCRAP_OK;
    if (count > capacity) {
        count = capacity;
        result = GB_SCRAP_TRUNCATED;
    }
    if (count && !data) return GB_SCRAP_ERR_ARGUMENT;
    if (count && gb_clip_get(data, count) != count) return GB_SCRAP_ERR_STATE;
    *copied = count;
    return result;
}

void gb_scrap_clear(void)
{
    gb_clip_set((const char *)0, 0);
}
