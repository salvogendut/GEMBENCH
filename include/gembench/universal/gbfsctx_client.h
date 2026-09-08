/* Root-callback-only, non-reentrant universal client. Storage belongs to this
 * application's primary page. No native framebuffer or mailbox addresses. */
#ifndef GEMBENCH_UNIVERSAL_FSCTX_CLIENT_H
#define GEMBENCH_UNIVERSAL_FSCTX_CLIENT_H
#define GB_FSCTX_CALLER_OWNED 1
extern unsigned char gb_ufs_request[32];
extern unsigned char gb_ufs_transfer[512];
#define GB_FSCTX_REQUEST gb_ufs_request
#define GB_FSCTX_TRANSFER gb_ufs_transfer
#define GB_FSCTX_WORD_AT(offset) (*(unsigned int *)(gb_ufs_request + (offset)))
#endif
