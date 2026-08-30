#include "gbfsctx.h"

#define R8(a)  (*(volatile unsigned char *)(a))
#define R16(a) (*(volatile unsigned int *)(a))

#define F_OP       R8(0xC3D0)
#define F_STATUS   R8(0xC3D1)
#define F_HANDLE   R16(0xC3D2)
#define F_DRIVE    R8(0xC3D6)
#define F_FLAGS    R8(0xC3D7)
#define F_LENGTH   R16(0xC3D8)
#define F_ACTUAL   R16(0xC3DA)
#define F_OFFSET   ((volatile unsigned char *)0xC3DC)
#define F_SIZE     ((volatile unsigned char *)0xC3E0)
#define F_ATTR     R8(0xC3E4)
#define F_AUX      R8(0xC3E5)
#define F_TRANSFER ((volatile unsigned char *)0xC400)

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

extern unsigned char gb_fsctx_call(unsigned char op);

static void set_handle(gb_fsctx_t context)
{
    F_HANDLE = context;
}

#ifndef GB_FSCTX_DIRECTORY_ONLY
static unsigned char copy_name_in(const char *name)
{
    unsigned char i;
    if (!name) return 0;
    for (i = 0; i < 11; i++) F_TRANSFER[i] = (unsigned char)name[i];
    return 1;
}
#endif

static unsigned char copy_path_in(const char *path)
{
    unsigned char i = 0;
    if (!path) return 0;
    while (path[i]) {
        if (i >= GB_FSCTX_PATH_MAX) return 0;
        F_TRANSFER[i] = (unsigned char)path[i];
        i++;
    }
    F_TRANSFER[i] = 0;
    return 1;
}

static unsigned char call_handle(unsigned char op, gb_fsctx_t context)
{
    set_handle(context);
    return gb_fsctx_call(op);
}

gb_fsctx_t gb_fsctx_open(unsigned char drive)
{
    F_DRIVE = drive;
    if (gb_fsctx_call(OP_ALLOC) != GB_FSCTX_OK) return 0;
    return F_HANDLE;
}

#ifndef GB_FSCTX_DIRECTORY_ONLY
unsigned char gb_fsctx_close(gb_fsctx_t context)
{
    return call_handle(OP_CLOSE, context);
}
#endif

unsigned char gb_fsctx_set_path(gb_fsctx_t context, const char *path)
{
    if (!copy_path_in(path)) return GB_FSCTX_ERR_BADARG;
    return call_handle(OP_SET_PATH, context);
}

#ifndef GB_FSCTX_DIRECTORY_ONLY
unsigned char gb_fsctx_set_name(gb_fsctx_t context, const char *name)
{
    if (!copy_name_in(name)) return GB_FSCTX_ERR_BADARG;
    return call_handle(OP_SET_NAME, context);
}
#endif

unsigned char gb_fsctx_activate(gb_fsctx_t context)
{
    return call_handle(OP_ACTIVATE, context);
}

#ifndef GB_FSCTX_BATCH_ONLY
static unsigned char copy_entry(gb_fsctx_entry_t *entry)
{
    unsigned char i;
    if (F_STATUS != GB_FSCTX_OK || !F_AUX) return 0;
    for (i = 0; i < 11; i++) entry->name[i] = (char)F_TRANSFER[i];
    entry->attributes = F_ATTR;
    for (i = 0; i < 4; i++) ((unsigned char *)&entry->size)[i] = F_SIZE[i];
    return 1;
}

unsigned char gb_fsctx_dir_first(gb_fsctx_t context, gb_fsctx_entry_t *entry)
{
    set_handle(context);
    gb_fsctx_call(OP_DIR_FIRST);
    return copy_entry(entry);
}

unsigned char gb_fsctx_dir_next(gb_fsctx_t context, gb_fsctx_entry_t *entry)
{
    set_handle(context);
    gb_fsctx_call(OP_DIR_NEXT);
    return copy_entry(entry);
}
#endif

unsigned char gb_fsctx_dir_batch(gb_fsctx_t context, unsigned char first)
{
    set_handle(context);
    F_FLAGS = first;
    F_LENGTH = GB_FSCTX_DIRECTORY_BATCH;
    if (gb_fsctx_call(OP_DIR_BATCH) != GB_FSCTX_OK) return 0;
    return (unsigned char)F_ACTUAL;
}

#ifndef GB_FSCTX_DIRECTORY_ONLY
unsigned char gb_fsctx_rewind(gb_fsctx_t context)
{
    return call_handle(OP_REWIND, context);
}

unsigned int gb_fsctx_read(gb_fsctx_t context, char *buffer, unsigned int length)
{
    unsigned int i, got;
    if (length > GB_FSCTX_TRANSFER_MAX) length = GB_FSCTX_TRANSFER_MAX;
    set_handle(context);
    F_LENGTH = length;
    if (gb_fsctx_call(OP_READ) != GB_FSCTX_OK) return 0;
    got = F_ACTUAL;
    for (i = 0; i < got; i++) buffer[i] = (char)F_TRANSFER[i];
    return got;
}

unsigned char gb_fsctx_write(gb_fsctx_t context, const char *buffer,
                             unsigned int length)
{
    unsigned int i;
    if (length > GB_FSCTX_TRANSFER_MAX) return GB_FSCTX_ERR_BADARG;
    for (i = 0; i < length; i++) F_TRANSFER[i] = (unsigned char)buffer[i];
    set_handle(context);
    F_LENGTH = length;
    return gb_fsctx_call(OP_WRITE);
}
#endif

unsigned char gb_fsctx_free_kib(gb_fsctx_t context, unsigned int *kib)
{
    set_handle(context);
    if (gb_fsctx_call(OP_FREE_KIB) != GB_FSCTX_OK || !F_AUX) return 0;
    *kib = F_ACTUAL;
    return 1;
}

#ifndef GB_FSCTX_DIRECTORY_ONLY
unsigned char gb_fsctx_cancel(gb_fsctx_t context)
{
    return call_handle(OP_CANCEL, context);
}

unsigned char gb_fsctx_prepare_launch(gb_fsctx_t context, const char *name)
{
    if (!copy_name_in(name)) return GB_FSCTX_ERR_BADARG;
    return call_handle(OP_PREP_LAUNCH, context);
}

gb_fsctx_t gb_fsctx_adopt_launch(void)
{
    if (gb_fsctx_call(OP_ADOPT_LAUNCH) != GB_FSCTX_OK) return 0;
    return F_HANDLE;
}
#endif

unsigned char gb_fsctx_status(void)
{
    return F_STATUS;
}
