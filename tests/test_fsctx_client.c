/* Execute the production native client, including its reduced profiles.
 * Host struct/int sizes and fake I/O do not prove Z80 ABI or CPC transport. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_FSCTX_PLATFORM_HEADER "fsctx_client_provider.h"
#include "../lib/gembench/gbfsctx.c"
static unsigned char result, calls, last_op;

unsigned char gb_fsctx_call(unsigned char op)
{
    unsigned int i;
    calls++;
    last_op = F_OP = op;
    F_STATUS = result;
    if (result) return result;
    F_AUX = 0;
    switch (op) {
        case OP_ALLOC: F_HANDLE = 0x0102; break;
        case OP_ADOPT_LAUNCH: F_HANDLE = 0x0202; break;
        case OP_DIR_FIRST:
        case OP_DIR_NEXT:
            memcpy((void *)F_TRANSFER, "ENTRY   TXT", 11);
            F_ATTR = 0x20;
            F_SIZE[0] = 4; F_SIZE[1] = 3; F_SIZE[2] = 2; F_SIZE[3] = 1;
            F_AUX = 1;
            break;
        case OP_DIR_BATCH:
            assert(F_LENGTH == 4);
            F_ACTUAL = 4;
            for (i = 0; i < 64; i++) F_TRANSFER[i] = (unsigned char)i;
            break;
        case OP_READ:
            F_ACTUAL = F_LENGTH;
            for (i = 0; i < F_ACTUAL; i++) F_TRANSFER[i] = 0x5A;
            break;
        case OP_FREE_KIB: F_ACTUAL = 1234; F_AUX = 1; break;
        default: break;
    }
    return F_STATUS;
}
int main(void)
{
    unsigned char before;
    unsigned int kib = 0;
    char path[50];
    memset(&client_memory, 0, sizeof(client_memory));
    assert(gb_fsctx_open(2) == 0x0102 && F_DRIVE == 2 && last_op == OP_ALLOC);
    result = GB_FSCTX_ERR_FULL;
    assert(gb_fsctx_open(0) == 0 && gb_fsctx_status() == GB_FSCTX_ERR_FULL);
    result = 0;
    before = calls;
    assert(gb_fsctx_set_path(0x0102, NULL) == GB_FSCTX_ERR_BADARG && calls == before);
    memset(path, 'P', 47); path[47] = 0;
    assert(gb_fsctx_set_path(0x0102, path) == GB_FSCTX_OK);
    assert(F_HANDLE == 0x0102 && last_op == OP_SET_PATH && F_TRANSFER[47] == 0);
    path[47] = 'P'; path[48] = 0;
    before = calls;
    assert(gb_fsctx_set_path(0x0102, path) == GB_FSCTX_ERR_BADARG && calls == before);
    assert(gb_fsctx_activate(0x0202) == GB_FSCTX_OK && F_HANDLE == 0x0202);
    assert(gb_fsctx_dir_batch(0x0102, 1) == 4 && F_FLAGS == 1);
    assert((const void *)gb_fsctx_batch_entries() == (const void *)F_TRANSFER);
    assert(((const unsigned char *)gb_fsctx_batch_entries())[63] == 63);
    result = GB_FSCTX_ERR_IO;
    assert(gb_fsctx_dir_batch(0x0102, 0) == 0 && F_FLAGS == 0);
    assert(!gb_fsctx_free_kib(0x0102, &kib) && kib == 0);
    result = 0;
    assert(gb_fsctx_free_kib(0x0102, &kib) && kib == 1234);
#ifndef GB_FSCTX_BATCH_ONLY
    {
        gb_fsctx_entry_t entry;
        memset(&entry, 0, sizeof(entry));
        assert(gb_fsctx_dir_first(0x0102, &entry));
        assert(!memcmp(entry.name, "ENTRY   TXT", 11));
        assert(entry.attributes == 0x20 && entry.size == 0x01020304UL);
        assert(gb_fsctx_dir_next(0x0102, &entry) && last_op == OP_DIR_NEXT);
        result = GB_FSCTX_ERR_STALE;
        assert(!gb_fsctx_dir_next(0x0102, &entry));
        result = 0;
    }
#endif
#ifndef GB_FSCTX_DIRECTORY_ONLY
    {
        char buffer[520];
        memset(buffer, 0, sizeof(buffer));
        before = calls;
        assert(gb_fsctx_set_name(0x0102, NULL) == GB_FSCTX_ERR_BADARG && calls == before);
        assert(gb_fsctx_set_name(0x0102, "FILE    TXT") == GB_FSCTX_OK);
        assert(!memcmp((const void *)F_TRANSFER, "FILE    TXT", 11));
        assert(gb_fsctx_read(0x0102, buffer, sizeof(buffer)) == 512);
        assert(F_LENGTH == 512 && buffer[511] == 0x5A && buffer[512] == 0);
        before = calls;
        assert(gb_fsctx_write(0x0102, buffer, 513) == GB_FSCTX_ERR_BADARG && calls == before);
        assert(gb_fsctx_write(0x0102, buffer, 512) == GB_FSCTX_OK);
        assert(F_TRANSFER[511] == 0x5A && F_LENGTH == 512 && last_op == OP_WRITE);
        result = GB_FSCTX_ERR_IO;
        memset(buffer, 0, sizeof(buffer));
        assert(!gb_fsctx_read(0x0102, buffer, 8) && buffer[0] == 0);
        result = 0;
        assert(gb_fsctx_rewind(0x0102) == GB_FSCTX_OK && last_op == OP_REWIND);
        assert(gb_fsctx_cancel(0x0102) == GB_FSCTX_OK && last_op == OP_CANCEL);
        assert(gb_fsctx_prepare_launch(0x0102, "DOC     TXT") == GB_FSCTX_OK);
        assert(last_op == OP_PREP_LAUNCH && !memcmp((const void *)F_TRANSFER, "DOC     TXT", 11));
        assert(gb_fsctx_adopt_launch() == 0x0202);
        assert(gb_fsctx_close(0x0202) == GB_FSCTX_OK && last_op == OP_CLOSE);
    }
#endif
    puts("filesystem client: PASS");
    return 0;
}
