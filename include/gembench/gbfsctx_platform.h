/* Select storage explicitly; the batch accessor and C wrapper must agree. */
#ifndef GEMBENCH_FSCTX_PLATFORM_H
#define GEMBENCH_FSCTX_PLATFORM_H
#ifndef GB_FSCTX_PLATFORM_HEADER
#ifdef GB_UNIVERSAL
#define GB_FSCTX_PLATFORM_HEADER "universal/gbfsctx_client.h"
#elif defined(GB_MSX2)
#define GB_FSCTX_PLATFORM_HEADER "msx/gbfsctx_client.h"
#else
#error "Select an explicit filesystem-client platform provider"
#endif
#endif
#include GB_FSCTX_PLATFORM_HEADER
#ifndef GB_FSCTX_CALLER_OWNED
#include "gbfsctx_contract.h"
#endif
#endif
