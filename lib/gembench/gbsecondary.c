/* App-linked MSX2 GBAP v3 secondary-code loader and call-gate policy. */
#include "gbsecondary.h"

#define R8(a)  (*(volatile unsigned char *)(a))
#define R16(a) (*(volatile unsigned int *)(a))

#define APP_BASE             0x4000u
#define APP_LIMIT            0x3F00u
#define GBAP_MANIFEST_OFFSET R16(0x400Eu)
#define PAGE_NATIVE          ((volatile unsigned char *)0xC200u)
#define PAGE_PURPOSE         ((volatile unsigned char *)0xC2A0u)
#define APP_FLAGS            ((volatile unsigned char *)0xC338u)
#define APP_FLAG_TERMINATING 0x04u
#define SCHED_CURRENT        R8(0x1342u)

/* M6 reuses the serialized filesystem request header only while no filesystem
 * operation is active. The gate consumes every field before secondary code is
 * entered, so a secondary leaf may use unrelated kernel services safely. */
#define GATE_BUSY            R8(0xC3D7u)
#define GATE_LENGTH          R16(0xC3DAu)
#define GATE_ENTRY           R16(0xC3DCu)
#define GATE_TARGET          R16(0xC3E0u)
#define GATE_NATIVE          R8(0xC3E5u)
#define TRANSFER             ((volatile unsigned char *)0xC400u)

#define SEGMENT_SIZE         12u
#define SEGMENT_SECONDARY    2u
#define SEGMENT_REQUIRED     0x01u
#define SEGMENT_EXECUTABLE   0x02u
#define PLATFORM_MSX2        0x02u

extern void gb_secondary_install_copy_gate(void);
extern void gb_secondary_install_call_gate(void);
extern void gb_secondary_gate(void);

static unsigned int word_at(const volatile unsigned char *p)
{
    return (unsigned int)p[0] | ((unsigned int)p[1] << 8);
}

static unsigned char native_page(gb_page_t page, unsigned char *native)
{
    unsigned char low = (unsigned char)page;
    unsigned char status = gb_page_check(page);
    unsigned char index;
    if (status != GB_PAGE_OK) {
        if (status == GB_PAGE_ERR_OWNER) return GB_SECONDARY_ERR_OWNER;
        return GB_SECONDARY_ERR_STALE;
    }
    if (!low || low > 32u) return GB_SECONDARY_ERR_STALE;
    index = (unsigned char)(low - 1u);
    if (PAGE_PURPOSE[index] != GB_PAGE_SECONDARY_CODE)
        return GB_SECONDARY_ERR_BADARG;
    *native = PAGE_NATIVE[index];
    return GB_SECONDARY_OK;
}

static const volatile unsigned char *secondary_descriptor(void)
{
    const volatile unsigned char *manifest;
    const volatile unsigned char *descriptor;
    unsigned int offset = GBAP_MANIFEST_OFFSET;
    unsigned int directory;
    unsigned char index;
    if (R8(0x4007u) != 3u || offset < 16u || offset > 80u)
        return 0;
    manifest = (const volatile unsigned char *)(APP_BASE + offset);
    if (manifest[0] != 'G' || manifest[1] != 'B' ||
        manifest[2] != 'M' || manifest[3] != '3' ||
        manifest[4] != 40u || manifest[5] != 1u ||
        manifest[28] != 2u || manifest[29] != SEGMENT_SIZE)
        return 0;
    directory = word_at(manifest + 30);
    if (directory != offset + 40u) return 0;
    descriptor = (const volatile unsigned char *)(APP_BASE + directory);
    for (index = 0; index < 2u; index++, descriptor += SEGMENT_SIZE) {
        if (descriptor[0] == SEGMENT_SECONDARY) return descriptor;
    }
    return 0;
}

unsigned char gb_secondary_open(gb_secondary_t *secondary)
{
    const volatile unsigned char *descriptor;
    const volatile unsigned char *source;
    unsigned int file_offset, stored, unpacked, load_address, image_size;
    unsigned int copied = 0;
    unsigned int count, index;
    unsigned char native, status;

    if (!secondary) return GB_SECONDARY_ERR_BADARG;
    secondary->page = 0;
    secondary->length = 0;
    descriptor = secondary_descriptor();
    if (!descriptor || !(descriptor[1] & PLATFORM_MSX2) ||
        (descriptor[2] & (SEGMENT_REQUIRED | SEGMENT_EXECUTABLE)) !=
            (SEGMENT_REQUIRED | SEGMENT_EXECUTABLE) || descriptor[3])
        return GB_SECONDARY_ERR_FORMAT;
    file_offset = word_at(descriptor + 4);
    stored = word_at(descriptor + 6);
    unpacked = word_at(descriptor + 8);
    load_address = word_at(descriptor + 10);
    image_size = word_at((const volatile unsigned char *)
                         (APP_BASE + GBAP_MANIFEST_OFFSET + 34u));
    if (!stored || stored != unpacked || load_address != APP_BASE ||
        file_offset < word_at((const volatile unsigned char *)0x400Au) ||
        file_offset + stored < file_offset ||
        file_offset + stored != image_size || image_size > APP_LIMIT)
        return GB_SECONDARY_ERR_FORMAT;
    source = (const volatile unsigned char *)(APP_BASE + file_offset);
    if (source[0] != 0xC3u || source[3] != 'G' || source[4] != 'B' ||
        source[5] != 'S' || source[6] != '3' || source[7] != 1u)
        return GB_SECONDARY_ERR_FORMAT;

    secondary->page = gb_page_alloc(GB_PAGE_SECONDARY_CODE);
    if (!secondary->page) return GB_SECONDARY_ERR_NOMEM;
    status = native_page(secondary->page, &native);
    if (status != GB_SECONDARY_OK) goto fail;

    gb_secondary_install_copy_gate();
    while (copied < stored) {
        count = (unsigned int)(stored - copied);
        if (count > GB_SECONDARY_TRANSFER_MAX)
            count = GB_SECONDARY_TRANSFER_MAX;
        for (index = 0; index < count; index++)
            TRANSFER[index] = source[copied + index];
        GATE_NATIVE = native;
        GATE_LENGTH = count;
        GATE_TARGET = (unsigned int)(APP_BASE + copied);
        gb_secondary_gate();
        copied = (unsigned int)(copied + count);
    }
    gb_secondary_install_call_gate();
    secondary->length = stored;
    return GB_SECONDARY_OK;

fail:
    secondary->page = 0;
    return status;
}

unsigned char gb_secondary_call(gb_secondary_t *secondary,
                                unsigned int entry_offset)
{
    gb_owner_t owner;
    unsigned char native, status;
    if (!secondary || !secondary->page || entry_offset >= secondary->length)
        return GB_SECONDARY_ERR_BADARG;
    if (SCHED_CURRENT != 0u) return GB_SECONDARY_ERR_CONTEXT;
    if (GATE_BUSY) return GB_SECONDARY_ERR_BUSY;
    owner = gb_owner_current();
    if (!(unsigned char)owner || (unsigned char)owner > 8u)
        return GB_SECONDARY_ERR_OWNER;
    if (APP_FLAGS[(unsigned char)owner - 1u] & APP_FLAG_TERMINATING)
        return GB_SECONDARY_ERR_TEARDOWN;
    status = native_page(secondary->page, &native);
    if (status != GB_SECONDARY_OK) return status;
    GATE_NATIVE = native;
    GATE_ENTRY = (unsigned int)(APP_BASE + entry_offset);
    GATE_BUSY = 1u;
    gb_secondary_gate();
    GATE_BUSY = 0u;
    return GB_SECONDARY_OK;
}
