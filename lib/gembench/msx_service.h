/* MSX2 app-linked service-manager fixed state (#74). No allocation here. */
#ifndef GEMBENCH_MSX_SERVICE_H
#define GEMBENCH_MSX_SERVICE_H
#define GB_SERVICE_PROVIDER_ADDRESS 0xC884u
#define GB_SERVICE_LEASE_ADDRESS 0xC892u
#define GB_SERVICE_LOCK_ADDRESS 0xC89Eu
#define GB_SERVICE_DIAG_ADDRESS 0xC89Fu
#define GB_SERVICE_OWNER_ACTIVE_ADDRESS 0xC2C0u
#define GB_SERVICE_OWNER_GEN_ADDRESS 0xC2C8u
#define GB_SERVICE_SCHED_ADDRESS 0x1342u
#define GB_SERVICE_PROVIDER_BASE ((volatile unsigned char *)GB_SERVICE_PROVIDER_ADDRESS)
#define GB_SERVICE_LEASE_BASE ((volatile unsigned char *)GB_SERVICE_LEASE_ADDRESS)
#define GB_SERVICE_LOCK (*(volatile unsigned char *)GB_SERVICE_LOCK_ADDRESS)
#define GB_SERVICE_DIAG (*(volatile unsigned char *)GB_SERVICE_DIAG_ADDRESS)
#define GB_SERVICE_OWNER_ACTIVE ((volatile unsigned char *)GB_SERVICE_OWNER_ACTIVE_ADDRESS)
#define GB_SERVICE_OWNER_GEN    ((volatile unsigned char *)GB_SERVICE_OWNER_GEN_ADDRESS)
#define GB_SERVICE_OWNER_MAX 8u
#define GB_SERVICE_SCHED_CURRENT (*(volatile unsigned char *)GB_SERVICE_SCHED_ADDRESS)
#endif

