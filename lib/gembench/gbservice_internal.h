#ifndef GEMBENCH_GBSERVICE_INTERNAL_H
#define GEMBENCH_GBSERVICE_INTERNAL_H
#include "gbservice.h"
#ifndef GB_SERVICE_PLATFORM_HEADER
#ifdef GB_MSX2
#define GB_SERVICE_PLATFORM_HEADER "msx_service.h"
#else
#error "Select an explicit service-manager platform provider"
#endif
#endif
#include GB_SERVICE_PLATFORM_HEADER
#include "core/service_contract.h"
#include "core/service_internal.h"
#endif
