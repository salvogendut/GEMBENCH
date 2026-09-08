/* MSX2 fixed bindings and native Nextor leaves for GBFSCTX.MOD (#74).
 * Expanded at the original call sites: no extra resident/module frames. */
#ifndef GEMBENCH_MSX_FSCTX_H
#define GEMBENCH_MSX_FSCTX_H
#define FSCTX_REQUEST_ADDRESS 0xC3D0u
#define FSCTX_TRANSFER_ADDRESS 0xC400u
#define FSCTX_TABLE_ADDRESS 0xC600u
#define FSCTX_PENDING_ADDRESS 0xC840u
#define FSCTX_DIAG_ADDRESS 0xC880u
#define FSCTX_CURSOR_ADDRESS 0xC8A0u
#define FSCTX_CURSOR_SIZE 64u
#define FSCTX_DRIVE_MAX 3u
#define U8(a)  (*(volatile unsigned char *)(a))
#define U16(a) (*(volatile unsigned int *)(a))
#define REQ_OP       U8(FSCTX_REQUEST_ADDRESS)
#define REQ_STATUS   U8(FSCTX_REQUEST_ADDRESS + 1)
#define REQ_HANDLE   U16(FSCTX_REQUEST_ADDRESS + 2)
#define REQ_OWNER    U16(FSCTX_REQUEST_ADDRESS + 4)
#define REQ_DRIVE    U8(FSCTX_REQUEST_ADDRESS + 6)
#define REQ_FLAGS    U8(FSCTX_REQUEST_ADDRESS + 7)
#define REQ_LENGTH   U16(FSCTX_REQUEST_ADDRESS + 8)
#define REQ_ACTUAL   U16(FSCTX_REQUEST_ADDRESS + 10)
#define REQ_OFFSET   ((volatile unsigned char *)FSCTX_REQUEST_ADDRESS + 12)
#define REQ_SIZE     ((volatile unsigned char *)FSCTX_REQUEST_ADDRESS + 16)
#define REQ_ATTR     U8(FSCTX_REQUEST_ADDRESS + 20)
#define REQ_AUX      U8(FSCTX_REQUEST_ADDRESS + 21)
#define XFER         ((volatile unsigned char *)FSCTX_TRANSFER_ADDRESS)
#define DIAG_OP      U8(FSCTX_DIAG_ADDRESS)
#define DIAG_STATUS  U8(FSCTX_DIAG_ADDRESS + 1)
#define DIAG_CALLS   U16(FSCTX_DIAG_ADDRESS + 2)
#define CTX_BASE     ((volatile unsigned char *)FSCTX_TABLE_ADDRESS)
#define PENDING      ((volatile unsigned char *)FSCTX_PENDING_ADDRESS)
#define FSCTX_CURSOR   ((volatile unsigned char *)FSCTX_CURSOR_ADDRESS)
#define FSCTX_ENTRY_ATTR  U8(0x14E7)
#define FSCTX_ENTRY_SIZE  ((volatile unsigned char *)0x14E8)
#define FS_LOAD_OFS  ((volatile unsigned char *)0x144C)
#define FS_XFLAGS    U8(0x144F)

extern unsigned char gbfs_msx_chdir(void);
#define FSCTX_CHANGE_DIRECTORY() gbfs_msx_chdir()
#define FSCTX_DIRECTORY_FIRST() gb_dir1()
#define FSCTX_DIRECTORY_NEXT() gb_dirn()
#define FSCTX_ENTRY_NAME() gb_entname()
#define FSCTX_FREE_KIB(out) gb_fs_free_kib(out)

/* CHDIR uses the active iterator workspace so WRITE's payload stays intact.
 * Directory calls restore/replace the opaque cursor after activation. */
#define FSCTX_SELECT_CONTEXT(ctx) do { \
    gb_set_drive((ctx)[CTX_DRIVE]); \
    copy_bytes(FSCTX_CURSOR, (ctx) + CTX_PATH, CTX_PATH_CAP); \
} while (0)

/* Retain the native 24-bit read offset and append-on-nonzero write contract.
 * Zero read is not a new distinction between EOF and a native load failure. */
#define FSCTX_READ_CHUNK(ctx, got) do { \
    gb_set_name((const char *)(ctx + CTX_NAME)); \
    FS_LOAD_OFS[0] = ctx[CTX_OFFSET]; \
    FS_LOAD_OFS[1] = ctx[CTX_OFFSET + 1]; \
    FS_LOAD_OFS[2] = ctx[CTX_OFFSET + 2]; \
    FS_XFLAGS = 1u; \
    got = gb_fs_load((char *)XFER, REQ_LENGTH); \
    FS_XFLAGS = 0; \
} while (0)

#define FSCTX_WRITE_CHUNK(ctx, ok) do { \
    gb_set_name((const char *)(ctx + CTX_NAME)); \
    FS_XFLAGS = (ctx[CTX_OFFSET] || ctx[CTX_OFFSET + 1] || \
    ctx[CTX_OFFSET + 2] || ctx[CTX_OFFSET + 3]) ? 2u : 0u; \
    ok = gb_fs_save((char *)XFER, REQ_LENGTH); \
    FS_XFLAGS = 0; \
} while (0)

#endif
