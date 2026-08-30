#include "gb.h"

#define U8(a)  (*(volatile unsigned char *)(a))
#define U16(a) (*(volatile unsigned int *)(a))

#define REQ_OP       U8(0xC3D0)
#define REQ_STATUS   U8(0xC3D1)
#define REQ_HANDLE   U16(0xC3D2)
#define REQ_OWNER    U16(0xC3D4)
#define REQ_DRIVE    U8(0xC3D6)
#define REQ_FLAGS    U8(0xC3D7)
#define REQ_LENGTH   U16(0xC3D8)
#define REQ_ACTUAL   U16(0xC3DA)
#define REQ_OFFSET   ((volatile unsigned char *)0xC3DC)
#define REQ_SIZE     ((volatile unsigned char *)0xC3E0)
#define REQ_ATTR     U8(0xC3E4)
#define REQ_AUX      U8(0xC3E5)
#define XFER         ((volatile unsigned char *)0xC400)
#define DIAG_OP      U8(0xC880)
#define DIAG_STATUS  U8(0xC881)
#define DIAG_CALLS   U16(0xC882)

#define CTX_BASE     ((volatile unsigned char *)0xC600)
#define CTX_SIZE     144u
#define CTX_MAX      4u
#define CTX_ACTIVE   0u
#define CTX_GEN      1u
#define CTX_OWNER    2u
#define CTX_DRIVE    4u
#define CTX_FLAGS    5u
#define CTX_OFFSET   8u
#define CTX_FILESIZE 12u
#define CTX_NAME     16u
#define CTX_PATH     28u
#define CTX_FIB      76u
#define CTX_PATH_CAP 48u

#define PENDING      ((volatile unsigned char *)0xC840)
#define P_ACTIVE     0u
#define P_OWNER      1u
#define P_DRIVE      3u
#define P_NAME       4u
#define P_PATH       16u

#define ACTIVE_FIB   ((volatile unsigned char *)0xC8A0)
#define FS_ENT_ATTR  U8(0x14E7)
#define FS_ENT_SIZE  ((volatile unsigned char *)0x14E8)
#define FS_LOAD_OFS  ((volatile unsigned char *)0x144C)
#define FS_XFLAGS    U8(0x144F)

#define OK          0u
#define UNSUPPORTED 1u
#define STALE       2u
#define OWNER       3u
#define FULL        4u
#define BADARG      5u
#define IOERR       6u

#define OP_ALLOC          0u
#define OP_CLOSE          1u
#define OP_SET_PATH       2u
#define OP_SET_NAME       3u
#define OP_ACTIVATE       4u
#define OP_DIR_FIRST      5u
#define OP_DIR_NEXT       6u
#define OP_REWIND         7u
#define OP_READ           8u
#define OP_WRITE          9u
#define OP_FREE_KIB      10u
#define OP_CANCEL        11u
#define OP_PREP_LAUNCH   12u
#define OP_ADOPT_LAUNCH  13u
#define OP_DIR_BATCH     14u

extern unsigned char gbfs_msx_chdir(void);

static volatile unsigned char *context_at(unsigned char slot)
{
    return CTX_BASE + (unsigned int)slot * CTX_SIZE;
}

static void copy_bytes(volatile unsigned char *dst,
                       const volatile unsigned char *src,
                       unsigned int count)
{
    while (count--) *dst++ = *src++;
}

static void zero_bytes(volatile unsigned char *dst, unsigned int count)
{
    while (count--) *dst++ = 0;
}

static void status(unsigned char value)
{
    REQ_STATUS = value;
    DIAG_STATUS = value;
}

static volatile unsigned char *validate(void)
{
    unsigned char low = (unsigned char)REQ_HANDLE;
    unsigned char slot;
    volatile unsigned char *ctx;
    if (!low || low > CTX_MAX) { status(STALE); return 0; }
    slot = (unsigned char)(low - 1u);
    ctx = context_at(slot);
    if (!ctx[CTX_ACTIVE] || ctx[CTX_GEN] != (unsigned char)(REQ_HANDLE >> 8)) {
        status(STALE);
        return 0;
    }
    if (ctx[CTX_OWNER] != (unsigned char)REQ_OWNER ||
        ctx[CTX_OWNER + 1] != (unsigned char)(REQ_OWNER >> 8)) {
        status(OWNER);
        return 0;
    }
    return ctx;
}

static volatile unsigned char *allocate(unsigned char drive)
{
    unsigned char slot;
    volatile unsigned char *ctx;
    unsigned char gen;
    if (drive >= 3u) { status(BADARG); return 0; }
    for (slot = 0; slot < CTX_MAX; slot++) {
        ctx = context_at(slot);
        if (!ctx[CTX_ACTIVE]) {
            gen = (unsigned char)(ctx[CTX_GEN] + 1u);
            if (!gen) gen = 1u;
            zero_bytes(ctx, CTX_SIZE);
            ctx[CTX_ACTIVE] = 1u;
            ctx[CTX_GEN] = gen;
            ctx[CTX_OWNER] = (unsigned char)REQ_OWNER;
            ctx[CTX_OWNER + 1] = (unsigned char)(REQ_OWNER >> 8);
            ctx[CTX_DRIVE] = drive;
            ctx[CTX_PATH] = '\\';
            ctx[CTX_PATH + 1] = 0;
            for (drive = 0; drive < 11u; drive++) ctx[CTX_NAME + drive] = ' ';
            REQ_HANDLE = (unsigned int)((unsigned int)gen << 8) | (slot + 1u);
            status(OK);
            return ctx;
        }
    }
    status(FULL);
    return 0;
}

static unsigned char activate(volatile unsigned char *ctx)
{
    gb_set_drive(ctx[CTX_DRIVE]);
    /* ACTIVE_FIB is a native-call workspace, not retained context state. Use
       it for the short-lived CHDIR path so OP_WRITE's payload remains in XFER.
       Directory calls restore or replace the FIB immediately after activation. */
    copy_bytes(ACTIVE_FIB, ctx + CTX_PATH, CTX_PATH_CAP);
    if (gbfs_msx_chdir()) {
        status(IOERR);
        return 0;
    }
    status(OK);
    return 1;
}

static void set_path(volatile unsigned char *ctx)
{
    unsigned char src = 0, dst = 0, ch;
    if (!XFER[0]) {
        ctx[CTX_PATH] = '\\';
        ctx[CTX_PATH + 1] = 0;
        status(OK);
        return;
    }
    if (XFER[0] != '/' && XFER[0] != '\\') ctx[CTX_PATH + dst++] = '\\';
    do {
        if (dst >= CTX_PATH_CAP) { status(BADARG); return; }
        ch = XFER[src++];
        if (ch == '/') ch = '\\';
        ctx[CTX_PATH + dst++] = ch;
    } while (ch);
    status(OK);
}

static void set_name(volatile unsigned char *ctx)
{
    copy_bytes(ctx + CTX_NAME, XFER, 11u);
    status(OK);
}

static void publish_entry(volatile unsigned char *ctx)
{
    char *name = gb_entname();
    copy_bytes(XFER, (const volatile unsigned char *)name, 11u);
    copy_bytes(ctx + CTX_FIB, ACTIVE_FIB, 64u);
    REQ_ATTR = FS_ENT_ATTR;
    copy_bytes(REQ_SIZE, FS_ENT_SIZE, 4u);
    REQ_AUX = 1u;
    status(OK);
}

static void directory(volatile unsigned char *ctx, unsigned char first)
{
    char *entry;
    REQ_AUX = 0;
    if (!activate(ctx)) return;
    if (!first) copy_bytes(ACTIVE_FIB, ctx + CTX_FIB, 64u);
    entry = first ? gb_dir1() : gb_dirn();
    if (!entry) { status(OK); return; }
    publish_entry(ctx);
}

static void directory_batch(volatile unsigned char *ctx)
{
    unsigned char count = 0;
    unsigned char first = REQ_FLAGS;
    char *name;
    volatile unsigned char *out;

    if (!REQ_LENGTH || REQ_LENGTH > 4u) { status(BADARG); return; }
    if (!activate(ctx)) return;
    if (!first) copy_bytes(ACTIVE_FIB, ctx + CTX_FIB, 64u);
    while (count < REQ_LENGTH) {
        name = first ? gb_dir1() : gb_dirn();
        first = 0;
        if (!name) break;
        out = XFER + (unsigned int)count * 16u;
        copy_bytes(out, (const volatile unsigned char *)gb_entname(), 11u);
        out[11] = FS_ENT_ATTR;
        copy_bytes(out + 12, FS_ENT_SIZE, 4u);
        copy_bytes(ctx + CTX_FIB, ACTIVE_FIB, 64u);
        count++;
    }
    REQ_ACTUAL = count;
    status(OK);
}

static void reset_offset(volatile unsigned char *ctx)
{
    zero_bytes(ctx + CTX_OFFSET, 4u);
    status(OK);
}

static void advance_offset(volatile unsigned char *ctx, unsigned int amount)
{
    unsigned int value = (unsigned int)ctx[CTX_OFFSET] |
        ((unsigned int)ctx[CTX_OFFSET + 1] << 8);
    unsigned int next = value + amount;
    ctx[CTX_OFFSET] = (unsigned char)next;
    ctx[CTX_OFFSET + 1] = (unsigned char)(next >> 8);
    if (next < value) {
        ctx[CTX_OFFSET + 2]++;
        if (!ctx[CTX_OFFSET + 2]) ctx[CTX_OFFSET + 3]++;
    }
    copy_bytes(REQ_OFFSET, ctx + CTX_OFFSET, 4u);
}

static void read_chunk(volatile unsigned char *ctx)
{
    unsigned int got;
    if (!REQ_LENGTH || REQ_LENGTH > 512u) { status(BADARG); return; }
    if (!activate(ctx)) return;
    gb_set_name((const char *)(ctx + CTX_NAME));
    FS_LOAD_OFS[0] = ctx[CTX_OFFSET];
    FS_LOAD_OFS[1] = ctx[CTX_OFFSET + 1];
    FS_LOAD_OFS[2] = ctx[CTX_OFFSET + 2];
    FS_XFLAGS = 1u;
    got = gb_fs_load((char *)XFER, REQ_LENGTH);
    FS_XFLAGS = 0;
    REQ_ACTUAL = got;
    advance_offset(ctx, got);
    status(OK);
}

static void write_chunk(volatile unsigned char *ctx)
{
    unsigned char ok;
    if (REQ_LENGTH > 512u) { status(BADARG); return; }
    if (!activate(ctx)) return;
    gb_set_name((const char *)(ctx + CTX_NAME));
    FS_XFLAGS = (ctx[CTX_OFFSET] || ctx[CTX_OFFSET + 1] ||
                 ctx[CTX_OFFSET + 2] || ctx[CTX_OFFSET + 3]) ? 2u : 0u;
    ok = gb_fs_save((char *)XFER, REQ_LENGTH);
    FS_XFLAGS = 0;
    if (!ok) { status(IOERR); return; }
    REQ_ACTUAL = REQ_LENGTH;
    advance_offset(ctx, REQ_LENGTH);
    status(OK);
}

static void free_space(volatile unsigned char *ctx)
{
    unsigned int kib;
    REQ_AUX = 0;
    if (!activate(ctx)) return;
    if (!gb_fs_free_kib(&kib)) { status(UNSUPPORTED); return; }
    REQ_ACTUAL = kib;
    REQ_AUX = 1u;
    status(OK);
}

static void prepare_launch(volatile unsigned char *ctx)
{
    PENDING[P_ACTIVE] = 0;
    PENDING[P_OWNER] = (unsigned char)REQ_OWNER;
    PENDING[P_OWNER + 1] = (unsigned char)(REQ_OWNER >> 8);
    PENDING[P_DRIVE] = ctx[CTX_DRIVE];
    copy_bytes(PENDING + P_NAME, XFER, 11u);
    copy_bytes(PENDING + P_PATH, ctx + CTX_PATH, CTX_PATH_CAP);
    PENDING[P_ACTIVE] = 1u;
    status(OK);
}

static void adopt_launch(void)
{
    volatile unsigned char *ctx;
    if (!PENDING[P_ACTIVE]) { status(STALE); return; }
    ctx = allocate(PENDING[P_DRIVE]);
    if (!ctx) return;
    copy_bytes(ctx + CTX_NAME, PENDING + P_NAME, 11u);
    copy_bytes(ctx + CTX_PATH, PENDING + P_PATH, CTX_PATH_CAP);
    PENDING[P_ACTIVE] = 0;
    status(OK);
}

void main(void)
{
    volatile unsigned char *ctx;
    unsigned char op = REQ_OP;

    DIAG_OP = op;
    DIAG_CALLS++;
    REQ_ACTUAL = 0;
    REQ_AUX = 0;
    status(BADARG);
    if (op == OP_ALLOC) { allocate(REQ_DRIVE); return; }
    if (op == OP_ADOPT_LAUNCH) { adopt_launch(); return; }

    ctx = validate();
    if (!ctx) return;
    switch (op) {
        case OP_CLOSE:        ctx[CTX_ACTIVE] = 0; status(OK); break;
        case OP_SET_PATH:     set_path(ctx); break;
        case OP_SET_NAME:     set_name(ctx); break;
        case OP_ACTIVATE:     activate(ctx); break;
        case OP_DIR_FIRST:    directory(ctx, 1u); break;
        case OP_DIR_NEXT:     directory(ctx, 0u); break;
        case OP_REWIND:       reset_offset(ctx); break;
        case OP_READ:         read_chunk(ctx); break;
        case OP_WRITE:        write_chunk(ctx); break;
        case OP_FREE_KIB:     free_space(ctx); break;
        case OP_CANCEL:       reset_offset(ctx); break;
        case OP_PREP_LAUNCH:  prepare_launch(ctx); break;
        case OP_DIR_BATCH:    directory_batch(ctx); break;
        default:              status(BADARG); break;
    }
}
