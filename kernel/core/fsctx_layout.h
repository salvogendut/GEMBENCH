/* Shared existing request/status and private record layout (#74).
 * The cursor tail is opaque to policy; its extent is supplied by the backend.
 * Keep synchronized with resident cleanup and frozen public FSCTX calls. */
#ifndef GEMBENCH_FSCTX_LAYOUT_H
#define GEMBENCH_FSCTX_LAYOUT_H
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
#define CTX_CURSOR      76u
#define CTX_PATH_CAP 48u
#define P_ACTIVE     0u
#define P_OWNER      1u
#define P_DRIVE      3u
#define P_NAME       4u
#define P_PATH       16u
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
#endif
