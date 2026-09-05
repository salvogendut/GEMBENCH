/* Shared paged filesystem-context policy (#74). Include after a provider. */
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
    if (drive >= FSCTX_DRIVE_MAX) { status(BADARG); return 0; }
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
    FSCTX_SELECT_CONTEXT(ctx);
    if (FSCTX_CHANGE_DIRECTORY()) {
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
    char *name = FSCTX_ENTRY_NAME();
    copy_bytes(XFER, (const volatile unsigned char *)name, 11u);
    copy_bytes(ctx + CTX_CURSOR, FSCTX_CURSOR, FSCTX_CURSOR_SIZE);
    REQ_ATTR = FSCTX_ENTRY_ATTR;
    copy_bytes(REQ_SIZE, FSCTX_ENTRY_SIZE, 4u);
    REQ_AUX = 1u;
    status(OK);
}

static void directory(volatile unsigned char *ctx, unsigned char first)
{
    char *entry;
    REQ_AUX = 0;
    if (!activate(ctx)) return;
    if (!first) copy_bytes(FSCTX_CURSOR, ctx + CTX_CURSOR, FSCTX_CURSOR_SIZE);
    entry = first ? FSCTX_DIRECTORY_FIRST() : FSCTX_DIRECTORY_NEXT();
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
    if (!first) copy_bytes(FSCTX_CURSOR, ctx + CTX_CURSOR, FSCTX_CURSOR_SIZE);
    while (count < REQ_LENGTH) {
        name = first ? FSCTX_DIRECTORY_FIRST() : FSCTX_DIRECTORY_NEXT();
        first = 0;
        if (!name) break;
        out = XFER + (unsigned int)count * 16u;
        copy_bytes(out, (const volatile unsigned char *)FSCTX_ENTRY_NAME(), 11u);
        out[11] = FSCTX_ENTRY_ATTR;
        copy_bytes(out + 12, FSCTX_ENTRY_SIZE, 4u);
        copy_bytes(ctx + CTX_CURSOR, FSCTX_CURSOR, FSCTX_CURSOR_SIZE);
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
    FSCTX_READ_CHUNK(ctx, got);
    REQ_ACTUAL = got;
    advance_offset(ctx, got);
    status(OK);
}

static void write_chunk(volatile unsigned char *ctx)
{
    unsigned char ok;
    if (REQ_LENGTH > 512u) { status(BADARG); return; }
    if (!activate(ctx)) return;
    FSCTX_WRITE_CHUNK(ctx, ok);
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
    if (!FSCTX_FREE_KIB(&kib)) { status(UNSUPPORTED); return; }
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

