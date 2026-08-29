#include <stdio.h>
#include <string.h>

#include "gb.h"
#include "gbscrap.h"

unsigned char gb_scrap_host_type;
static unsigned char raw_data[GB_SCRAP_CAPACITY];
static unsigned int raw_length;
static int failures;

static void check(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        failures++;
    }
}

void gb_clip_set(const char *data, unsigned int length)
{
    gb_scrap_host_type = GB_SCRAP_UNTYPED;
    if (length > GB_SCRAP_CAPACITY) length = GB_SCRAP_CAPACITY;
    raw_length = length;
    if (length) memcpy(raw_data, data, length);
}

unsigned int gb_clip_len(void)
{
    return raw_length;
}

unsigned int gb_clip_get(char *data, unsigned int capacity)
{
    unsigned int count = raw_length < capacity ? raw_length : capacity;
    if (count) memcpy(data, raw_data, count);
    return count;
}

static void reset(void)
{
    memset(raw_data, 0, sizeof(raw_data));
    raw_length = 0;
    gb_scrap_host_type = GB_SCRAP_UNTYPED;
}

static void test_empty_and_typed(void)
{
    static const char text[] = "typed text";
    gb_scrap_info_t info;
    char output[16];
    unsigned int copied = 99;

    reset();
    check(gb_scrap_query(&info) == GB_SCRAP_OK &&
              info.length == 0 && info.type == GB_SCRAP_UNTYPED,
          "empty clipboard is normalized as untyped");
    check(gb_scrap_set(GB_SCRAP_TEXT, text, sizeof(text) - 1) == GB_SCRAP_OK,
          "typed text stores without truncation");
    check(gb_scrap_query(&info) == GB_SCRAP_OK &&
              info.length == sizeof(text) - 1 && info.type == GB_SCRAP_TEXT,
          "query returns typed text metadata");
    check(gb_scrap_type() == GB_SCRAP_TEXT,
          "compact type query reports typed text");
    memset(output, 0, sizeof(output));
    check(gb_scrap_get(GB_SCRAP_TEXT, output, sizeof(output), &copied) ==
              GB_SCRAP_OK && copied == sizeof(text) - 1 &&
              !memcmp(output, text, copied),
          "matching typed get copies the complete payload");
}

static void test_raw_compatibility_and_stale_tag(void)
{
    unsigned char input[GB_SCRAP_CAPACITY + 8];
    gb_scrap_info_t info;
    unsigned int i;

    reset();
    for (i = 0; i < sizeof(input); i++) input[i] = (unsigned char)i;
    gb_scrap_host_type = GB_SCRAP_ICON;
    gb_clip_set((const char *)input, sizeof(input));
    check(raw_length == GB_SCRAP_CAPACITY,
          "legacy raw set retains its 510-byte clamping behavior");
    check(gb_scrap_host_type == GB_SCRAP_UNTYPED &&
              gb_scrap_query(&info) == GB_SCRAP_OK &&
              info.type == GB_SCRAP_UNTYPED &&
              info.length == GB_SCRAP_CAPACITY,
          "legacy raw set invalidates typed metadata without losing payload");
    check(gb_scrap_type() == GB_SCRAP_UNTYPED,
          "compact type query preserves legacy compatibility");

    gb_scrap_host_type = 0x7Eu;
    check(gb_scrap_query(&info) == GB_SCRAP_OK &&
              info.type == GB_SCRAP_UNTYPED &&
              gb_scrap_type() == GB_SCRAP_UNTYPED,
          "unknown or stale metadata safely degrades to untyped");
}

static void test_truncation_and_atomic_errors(void)
{
    unsigned char input[GB_SCRAP_CAPACITY + 20];
    unsigned char before[GB_SCRAP_CAPACITY];
    gb_scrap_info_t info;
    unsigned int i;

    reset();
    for (i = 0; i < sizeof(input); i++) input[i] = (unsigned char)(255u - i);
    check(gb_scrap_set(GB_SCRAP_BITMAP, (const char *)input, sizeof(input)) ==
              GB_SCRAP_TRUNCATED,
          "oversized typed set reports explicit truncation");
    check(gb_scrap_query(&info) == GB_SCRAP_OK &&
              info.type == GB_SCRAP_BITMAP &&
              info.length == GB_SCRAP_CAPACITY &&
              !memcmp(raw_data, input, GB_SCRAP_CAPACITY),
          "typed truncation publishes a complete maximum-size payload");
    memcpy(before, raw_data, sizeof(before));
    check(gb_scrap_set(9, "bad", 3) == GB_SCRAP_ERR_TYPE &&
              gb_scrap_host_type == GB_SCRAP_BITMAP &&
              raw_length == GB_SCRAP_CAPACITY &&
              !memcmp(raw_data, before, sizeof(before)),
          "unsupported set type leaves the prior scrap untouched");
    check(gb_scrap_set(GB_SCRAP_TEXT, 0, 1) == GB_SCRAP_ERR_ARGUMENT &&
              gb_scrap_host_type == GB_SCRAP_BITMAP,
          "invalid set pointer leaves the prior scrap untouched");
}

static void test_get_mismatch_and_short_buffer(void)
{
    static const char payload[] = "abcdef";
    char output[8];
    unsigned int copied;

    reset();
    gb_scrap_set(GB_SCRAP_ICON, payload, sizeof(payload) - 1);
    memset(output, 0x5A, sizeof(output));
    copied = 99;
    check(gb_scrap_get(GB_SCRAP_TEXT, output, sizeof(output), &copied) ==
              GB_SCRAP_ERR_MISMATCH && copied == 0 && output[0] == 0x5A,
          "type mismatch copies no bytes");
    check(gb_scrap_get(GB_SCRAP_ICON, output, 3, &copied) ==
              GB_SCRAP_TRUNCATED && copied == 3 && !memcmp(output, "abc", 3),
          "short destination reports truncation and exact copied count");
    check(gb_scrap_get(GB_SCRAP_ANY, output, sizeof(output), &copied) ==
              GB_SCRAP_OK && copied == sizeof(payload) - 1,
          "any-type retrieval accepts a typed payload");
    check(gb_scrap_get(7, output, sizeof(output), &copied) ==
              GB_SCRAP_ERR_TYPE && copied == 0,
          "unsupported expected type is rejected");
    check(gb_scrap_get(GB_SCRAP_ANY, output, sizeof(output), 0) ==
              GB_SCRAP_ERR_ARGUMENT,
          "missing copied-count pointer is rejected");
}

static void test_clear_and_corrupt_length(void)
{
    gb_scrap_info_t info;

    reset();
    gb_scrap_set(GB_SCRAP_FILELIST, "A.TXT", 5);
    gb_scrap_clear();
    check(raw_length == 0 && gb_scrap_host_type == GB_SCRAP_UNTYPED &&
              gb_scrap_query(&info) == GB_SCRAP_OK && info.length == 0,
          "clear removes payload and metadata");
    gb_scrap_set(GB_SCRAP_TEXT, "x", 1);
    raw_length = GB_SCRAP_CAPACITY + 1;
    check(gb_scrap_query(&info) == GB_SCRAP_ERR_STATE &&
              info.length == 0 && info.type == GB_SCRAP_UNTYPED,
          "corrupt raw length is rejected without exposing an overrun");
    check(gb_scrap_query(0) == GB_SCRAP_ERR_ARGUMENT,
          "missing query destination is rejected");
}

int main(void)
{
    test_empty_and_typed();
    test_raw_compatibility_and_stale_tag();
    test_truncation_and_atomic_errors();
    test_get_mismatch_and_short_buffer();
    test_clear_and_corrupt_length();
    if (failures) return 1;
    puts("gbscrap: all tests passed");
    return 0;
}
