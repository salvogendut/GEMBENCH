#ifndef TEST_FILEPICK_CLIENT_PROVIDER_H
#define TEST_FILEPICK_CLIENT_PROVIDER_H
#include <stdint.h>
#define GB_FSCTX_CALLER_OWNED 1
extern unsigned char filepick_request[32], filepick_transfer[512];
#define GB_FSCTX_REQUEST filepick_request
#define GB_FSCTX_TRANSFER filepick_transfer
#define GB_FSCTX_WORD_AT(offset) (*(uint16_t *)(filepick_request + (offset)))
#endif
