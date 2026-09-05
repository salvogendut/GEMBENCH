/* Native MSX2 filesystem-client state. Not a universal APP binding (#75). */
#ifndef GEMBENCH_MSX_FSCTX_CLIENT_H
#define GEMBENCH_MSX_FSCTX_CLIENT_H
#define GB_FSCTX_REQUEST_ADDRESS 0xC3D0u
#define GB_FSCTX_TRANSFER_ADDRESS 0xC400u
#define GB_FSCTX_REQUEST ((volatile unsigned char *)GB_FSCTX_REQUEST_ADDRESS)
#define GB_FSCTX_TRANSFER ((volatile unsigned char *)GB_FSCTX_TRANSFER_ADDRESS)
#define GB_FSCTX_WORD_AT(offset) (*(volatile unsigned int *)(GB_FSCTX_REQUEST_ADDRESS + (offset)))
#endif
