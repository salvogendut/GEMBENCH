/* Private CPC provider for the unmodified shared context policy. All policy
 * state remains fixed while the module lives in reserved data bank F7. */
#ifndef GEMBENCH_CPC_FSCTX_H
#define GEMBENCH_CPC_FSCTX_H
#define FSCTX_REQUEST_ADDRESS 0x2400u
#define FSCTX_TRANSFER_ADDRESS 0x1500u
#define FSCTX_TABLE_ADDRESS 0x2600u
#define FSCTX_PENDING_ADDRESS 0x2460u
#define FSCTX_DIAG_ADDRESS 0x24A0u
#define FSCTX_CURSOR_ADDRESS 0x2420u
#define FSCTX_CURSOR_SIZE 64u
#define FSCTX_DRIVE_MAX 1u
#define U8(a) (*(volatile unsigned char *)(a))
#define U16(a) (*(volatile unsigned int *)(a))
#define REQ_OP U8(FSCTX_REQUEST_ADDRESS)
#define REQ_STATUS U8(FSCTX_REQUEST_ADDRESS+1)
#define REQ_HANDLE U16(FSCTX_REQUEST_ADDRESS+2)
#define REQ_OWNER U16(FSCTX_REQUEST_ADDRESS+4)
#define REQ_DRIVE U8(FSCTX_REQUEST_ADDRESS+6)
#define REQ_FLAGS U8(FSCTX_REQUEST_ADDRESS+7)
#define REQ_LENGTH U16(FSCTX_REQUEST_ADDRESS+8)
#define REQ_ACTUAL U16(FSCTX_REQUEST_ADDRESS+10)
#define REQ_OFFSET ((volatile unsigned char *)FSCTX_REQUEST_ADDRESS+12)
#define REQ_SIZE ((volatile unsigned char *)FSCTX_REQUEST_ADDRESS+16)
#define REQ_ATTR U8(FSCTX_REQUEST_ADDRESS+20)
#define REQ_AUX U8(FSCTX_REQUEST_ADDRESS+21)
#define XFER ((volatile unsigned char *)FSCTX_TRANSFER_ADDRESS)
#define CTX_BASE ((volatile unsigned char *)FSCTX_TABLE_ADDRESS)
#define PENDING ((volatile unsigned char *)FSCTX_PENDING_ADDRESS)
#define FSCTX_CURSOR ((volatile unsigned char *)FSCTX_CURSOR_ADDRESS)
#define DIAG_OP U8(FSCTX_DIAG_ADDRESS)
#define DIAG_STATUS U8(FSCTX_DIAG_ADDRESS+1)
#define DIAG_CALLS U16(FSCTX_DIAG_ADDRESS+2)
#define CPC_SELECTED (*(volatile unsigned char * volatile *)0x24A4u)
#define CPC_IO_STATUS U8(0x24A6u)
#define CPC_COMMAND_END U16(0x24A8u)
#define CPC_PATH ((volatile unsigned char *)0x24C0u)
#define CPC_FILE ((volatile unsigned char *)0x2500u)
#define CPC_PACKET ((volatile unsigned char *)0x6000u)
#define CPC_IO_PATH ((volatile unsigned char *)0x6020u)
#define CPC_BUFFER ((volatile unsigned char *)0x6080u)
#define CPC_COMMAND ((volatile unsigned char *)0x1BA0u)
#define CPC_RESPONSE ((volatile unsigned char *)0x1B00u)
extern unsigned char cpc_fs_exchange(void) __sdcccall(0);
extern unsigned int cpc_fs_read128(void) __sdcccall(0);
static unsigned char cpc_fs_activate(void);
static unsigned int cpc_fs_read(void);
#define FSCTX_SELECT_CONTEXT(ctx) do { CPC_SELECTED=(ctx); } while (0)
#define FSCTX_CHANGE_DIRECTORY() cpc_fs_activate()
#define FSCTX_READ_CHUNK(ctx,got) do { (void)(ctx); got=cpc_fs_read(); } while (0)
#ifdef CPC_FS_DIRECTORY
#define CPC_DIR_STATUS U8(0x24B0u)
#define CPC_DIR_LIVE U8(0x24B1u)
#define CPC_DIR_ENTRY ((volatile unsigned char *)0x2540u)
#define CPC_DIR_LIMIT 1024u
static char *cpc_fs_directory(unsigned char first);
#define FSCTX_DIRECTORY_FIRST() cpc_fs_directory(1u)
#define FSCTX_DIRECTORY_NEXT() cpc_fs_directory(0u)
#define FSCTX_DIRECTORY_STATUS() CPC_DIR_STATUS
#define FSCTX_ENTRY_NAME() ((char *)0x2540u)
#define FSCTX_ENTRY_ATTR U8(0x254Bu)
#define FSCTX_ENTRY_SIZE ((volatile unsigned char *)0x254Cu)
#else
/* The resident gate explicitly returns UNSUPPORTED for directory/write/free
 * operations. These unreachable bindings keep the shared source unchanged;
 * they must never be exposed as successful empty directories or writes. */
#define FSCTX_DIRECTORY_FIRST() ((char *)0)
#define FSCTX_DIRECTORY_NEXT() ((char *)0)
#define FSCTX_ENTRY_NAME() ((char *)0x14DCu)
#define FSCTX_ENTRY_ATTR U8(0x14E7u)
#define FSCTX_ENTRY_SIZE ((volatile unsigned char *)0x14E8u)
#endif
#define FSCTX_FREE_KIB(out) 0u
#define FSCTX_WRITE_CHUNK(ctx,ok) do { (void)(ctx); ok=0; } while (0)
#endif
