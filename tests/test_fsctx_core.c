/* Actual shared module policy with synchronous fake storage leaves.
 * Host unsigned int is not Z80-width: carry/ABI proof stays target-side. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../kernel/core/fsctx_layout.h"
#include "fixtures/fsctx_core_provider.h"
#include "../kernel/core/fsctx_contract.h"
static unsigned char chdir_error, write_ok = 1, free_ok = 1;
static unsigned char entry_size[4] = {8, 0, 0, 0};
static char entry_name[12] = "A       TXT";
static unsigned char selected_drive, io_calls;
static unsigned int read_amount = 8;
static char *next_entry(unsigned char first)
{
    if (first) FSCTX_CURSOR[0] = 0;
    if (FSCTX_CURSOR[0] >= 3) return NULL;
    entry_name[0] = (char)('A' + FSCTX_CURSOR[0]++);
    return entry_name;
}
static unsigned char free_kib(unsigned int *kib) { *kib = 123; return free_ok; }
#define FSCTX_SELECT_CONTEXT(ctx) do { \
    selected_drive = (ctx)[CTX_DRIVE]; \
    copy_bytes(FSCTX_CURSOR, (ctx) + CTX_PATH, CTX_PATH_CAP); \
} while (0)
#define FSCTX_CHANGE_DIRECTORY() chdir_error
#define FSCTX_DIRECTORY_FIRST() next_entry(1)
#define FSCTX_DIRECTORY_NEXT() next_entry(0)
#define FSCTX_ENTRY_NAME() entry_name
#define FSCTX_FREE_KIB(out) free_kib(out)
#define FSCTX_READ_CHUNK(ctx, got) do { \
    (void)(ctx); io_calls++; got = read_amount; \
    memset((void *)XFER, 0x5A, got); \
} while (0)
#define FSCTX_WRITE_CHUNK(ctx, ok) do { \
    (void)(ctx); io_calls++; assert(XFER[0] == 0xA5); ok = write_ok; \
} while (0)
#define main fsctx_dispatch
#include "../kernel/core/fsctx_policy.inc"
#undef main
static void call(unsigned char op, unsigned int handle, unsigned int owner)
{
    REQ_OP = op; REQ_HANDLE = handle; REQ_OWNER = owner;
    fsctx_dispatch();
    assert(DIAG_STATUS == REQ_STATUS && DIAG_OP == op);
}
int main(void)
{
    unsigned int a, b, c, d;
    unsigned char before;
    memset(&fs_memory, 0, sizeof(fs_memory));
    REQ_DRIVE = 3;
    call(OP_ALLOC, 0, 0x0101);
    assert(REQ_STATUS == BADARG);
    REQ_DRIVE = 0;
    call(OP_ALLOC, 0, 0x0101); a = REQ_HANDLE;
    assert(a == 0x0101 && REQ_STATUS == OK);
    assert(!strcmp((const char *)context_at(0) + CTX_PATH, "\\"));
    call(OP_ALLOC, 0, 0x0102); b = REQ_HANDLE;
    call(OP_ALLOC, 0, 0x0101); c = REQ_HANDLE;
    call(OP_ALLOC, 0, 0x0101); d = REQ_HANDLE;
    call(OP_ALLOC, 0, 0x0101); assert(REQ_STATUS == FULL);
    call(OP_REWIND, a, 0x0102); assert(REQ_STATUS == OWNER);
    call(OP_REWIND, a + 0x100, 0x0101); assert(REQ_STATUS == STALE);
    call(255, 0, 0x0101); assert(REQ_STATUS == STALE);
    call(255, a, 0x0101); assert(REQ_STATUS == BADARG);
    strcpy((char *)XFER, "DIR/SUB");
    call(OP_SET_PATH, a, 0x0101);
    assert(!strcmp((char *)context_at(0) + CTX_PATH, "\\DIR\\SUB"));
    call(OP_DIR_FIRST, a, 0x0101);
    assert(REQ_AUX == 1 && XFER[0] == 'A' && REQ_ATTR == 0x20 && REQ_SIZE[0] == 8);
    call(OP_DIR_FIRST, b, 0x0102); assert(XFER[0] == 'A');
    call(OP_DIR_NEXT, a, 0x0101); assert(XFER[0] == 'B');
    call(OP_DIR_NEXT, b, 0x0102); assert(XFER[0] == 'B');
    REQ_FLAGS = 1; REQ_LENGTH = 4;
    call(OP_DIR_BATCH, a, 0x0101);
    assert(REQ_ACTUAL == 3 && XFER[0] == 'A' && XFER[16] == 'B' && XFER[32] == 'C');
    REQ_FLAGS = 0;
    call(OP_DIR_BATCH, a, 0x0101); assert(REQ_ACTUAL == 0 && REQ_STATUS == OK);
    REQ_LENGTH = 5;
    call(OP_DIR_BATCH, a, 0x0101); assert(REQ_STATUS == BADARG);

    REQ_LENGTH = 0; before = io_calls;
    call(OP_READ, a, 0x0101); assert(REQ_STATUS == BADARG && io_calls == before);
    REQ_LENGTH = 513;
    call(OP_WRITE, a, 0x0101); assert(REQ_STATUS == BADARG && io_calls == before);
    REQ_LENGTH = 8;
    call(OP_READ, a, 0x0101);
    assert(REQ_ACTUAL == 8 && REQ_OFFSET[0] == 8 && XFER[0] == 0x5A);
    XFER[0] = 0xA5; write_ok = 0;
    call(OP_WRITE, a, 0x0101);
    assert(REQ_STATUS == IOERR && REQ_ACTUAL == 0 && context_at(0)[CTX_OFFSET] == 8);
    write_ok = 1;
    call(OP_WRITE, a, 0x0101);
    assert(REQ_STATUS == OK && REQ_ACTUAL == 8 && REQ_OFFSET[0] == 16 && XFER[0] == 0xA5);
    chdir_error = 1; before = io_calls;
    call(OP_READ, a, 0x0101);
    assert(REQ_STATUS == IOERR && io_calls == before && selected_drive == 0);
    chdir_error = 0;
    call(OP_CANCEL, a, 0x0101); assert(context_at(0)[CTX_OFFSET] == 0);
    free_ok = 0;
    call(OP_FREE_KIB, a, 0x0101); assert(REQ_STATUS == UNSUPPORTED && !REQ_AUX);
    free_ok = 1;
    call(OP_FREE_KIB, a, 0x0101); assert(REQ_ACTUAL == 123 && REQ_AUX == 1);

    memcpy((void *)XFER, "DOC     TXT", 11);
    call(OP_PREP_LAUNCH, a, 0x0101); assert(PENDING[P_ACTIVE]);
    call(OP_ADOPT_LAUNCH, 0, 0x0102);
    assert(REQ_STATUS == FULL && PENDING[P_ACTIVE]);
    call(OP_CLOSE, c, 0x0101);
    call(OP_ADOPT_LAUNCH, 0, 0x0102);
    assert(REQ_STATUS == OK && !PENDING[P_ACTIVE] && REQ_HANDLE == 0x0203);
    assert(!memcmp((const void *)(context_at(2) + CTX_NAME), "DOC     TXT", 11));
    assert(!strcmp((const char *)context_at(2) + CTX_PATH, "\\DIR\\SUB"));
    call(OP_REWIND, c, 0x0101); assert(REQ_STATUS == STALE);
    call(OP_ADOPT_LAUNCH, 0, 0x0102); assert(REQ_STATUS == STALE);
    call(OP_CLOSE, d, 0x0101);
    context_at(3)[CTX_GEN] = 255;
    call(OP_ALLOC, 0, 0x0102); assert(REQ_HANDLE == 0x0104);
    memset((void *)XFER, 'X', 49);
    call(OP_SET_PATH, a, 0x0101); assert(REQ_STATUS == BADARG);
    assert(context_at(0)[CTX_PATH + 1] == 'X'); /* retained partial-write behavior */
    puts("filesystem core: PASS");
    return 0;
}
