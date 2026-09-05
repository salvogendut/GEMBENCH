/* Independent host storage. Integer addresses are checked as a candidate
 * Z80 layout; backing storage is an aligned host array, never native memory. */
#ifndef FIXTURE_BASE
#define FIXTURE_BASE 0x2000
#endif
#include <stdint.h>
static union { uint16_t alignment; unsigned char bytes[65536]; } fs_memory;
#ifndef FSCTX_REQUEST_ADDRESS
#define FSCTX_REQUEST_ADDRESS (FIXTURE_BASE + 0x0)
#endif
#ifndef FSCTX_TRANSFER_ADDRESS
#define FSCTX_TRANSFER_ADDRESS (FIXTURE_BASE + 0x100)
#endif
#ifndef FSCTX_TABLE_ADDRESS
#define FSCTX_TABLE_ADDRESS (FIXTURE_BASE + 0x300)
#endif
#ifndef FSCTX_PENDING_ADDRESS
#define FSCTX_PENDING_ADDRESS (FIXTURE_BASE + 0x540)
#endif
#ifndef FSCTX_DIAG_ADDRESS
#define FSCTX_DIAG_ADDRESS (FIXTURE_BASE + 0x580)
#endif
#ifndef FSCTX_CURSOR_ADDRESS
#define FSCTX_CURSOR_ADDRESS (FIXTURE_BASE + 0x5a0)
#endif
#define FSCTX_CURSOR_SIZE 64u
#define FSCTX_DRIVE_MAX 3u
#define U8(a)  (fs_memory.bytes[(a)])
#define U16(a) (*(volatile uint16_t *)(fs_memory.bytes + (a)))
#define REQ_OP       U8(FSCTX_REQUEST_ADDRESS)
#define REQ_STATUS   U8(FSCTX_REQUEST_ADDRESS + 1)
#define REQ_HANDLE   U16(FSCTX_REQUEST_ADDRESS + 2)
#define REQ_OWNER    U16(FSCTX_REQUEST_ADDRESS + 4)
#define REQ_DRIVE    U8(FSCTX_REQUEST_ADDRESS + 6)
#define REQ_FLAGS    U8(FSCTX_REQUEST_ADDRESS + 7)
#define REQ_LENGTH   U16(FSCTX_REQUEST_ADDRESS + 8)
#define REQ_ACTUAL   U16(FSCTX_REQUEST_ADDRESS + 10)
#define REQ_OFFSET   (fs_memory.bytes + FSCTX_REQUEST_ADDRESS + 12)
#define REQ_SIZE     (fs_memory.bytes + FSCTX_REQUEST_ADDRESS + 16)
#define REQ_ATTR     U8(FSCTX_REQUEST_ADDRESS + 20)
#define REQ_AUX      U8(FSCTX_REQUEST_ADDRESS + 21)
#define XFER         (fs_memory.bytes + FSCTX_TRANSFER_ADDRESS)
#define DIAG_OP      U8(FSCTX_DIAG_ADDRESS)
#define DIAG_STATUS  U8(FSCTX_DIAG_ADDRESS + 1)
#define DIAG_CALLS   U16(FSCTX_DIAG_ADDRESS + 2)
#define CTX_BASE     (fs_memory.bytes + FSCTX_TABLE_ADDRESS)
#define PENDING      (fs_memory.bytes + FSCTX_PENDING_ADDRESS)
#define FSCTX_CURSOR   (fs_memory.bytes + FSCTX_CURSOR_ADDRESS)
#define FSCTX_ENTRY_ATTR  0x20u
#define FSCTX_ENTRY_SIZE  entry_size
