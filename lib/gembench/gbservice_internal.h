#ifndef GEMBENCH_GBSERVICE_INTERNAL_H
#define GEMBENCH_GBSERVICE_INTERNAL_H

#include "gbservice.h"

#define GB_SERVICE_PROVIDER_BASE ((volatile unsigned char *)0xC884u)
#define GB_SERVICE_PROVIDER_SIZE 7u
#define GB_SERVICE_PROVIDER_MAX  GB_SERVICE_PROVIDER_CAPACITY
#define GB_SERVICE_P_ID          0u
#define GB_SERVICE_P_OWNER       2u
#define GB_SERVICE_P_STATE       4u
#define GB_SERVICE_P_REFS        5u
#define GB_SERVICE_P_GEN         6u

#define GB_SERVICE_LEASE_BASE ((volatile unsigned char *)0xC892u)
#define GB_SERVICE_LEASE_SIZE 4u
#define GB_SERVICE_LEASE_MAX  GB_SERVICE_LEASE_CAPACITY
#define GB_SERVICE_L_OWNER    0u
#define GB_SERVICE_L_PROVIDER 2u
#define GB_SERVICE_L_GEN      3u

#define GB_SERVICE_LOCK (*(volatile unsigned char *)0xC89Eu)
#define GB_SERVICE_DIAG (*(volatile unsigned char *)0xC89Fu)

#define GB_SERVICE_PROVIDER_FREE        0u
#define GB_SERVICE_PROVIDER_READY       1u
#define GB_SERVICE_PROVIDER_STOPPING    2u
#define GB_SERVICE_PROVIDER_STOP_QUEUED 3u

#define GB_SERVICE_OWNER_ACTIVE ((volatile unsigned char *)0xC2C0u)
#define GB_SERVICE_OWNER_GEN    ((volatile unsigned char *)0xC2C8u)
#define GB_SERVICE_OWNER_MAX 8u
#define GB_SERVICE_SCHED_CURRENT (*(volatile unsigned char *)0x1342u)

static volatile unsigned char *gb_service_provider_at(unsigned char slot)
{
    return GB_SERVICE_PROVIDER_BASE +
        (unsigned int)slot * GB_SERVICE_PROVIDER_SIZE;
}

static volatile unsigned char *gb_service_lease_at(unsigned char slot)
{
    return GB_SERVICE_LEASE_BASE +
        (unsigned int)slot * GB_SERVICE_LEASE_SIZE;
}

static unsigned int gb_service_word(const volatile unsigned char *p)
{
    return (unsigned int)p[0] | ((unsigned int)p[1] << 8);
}

#ifndef GB_SERVICE_INTERNAL_COLLECTOR
static void gb_service_put_word(volatile unsigned char *p, unsigned int value)
{
    p[0] = (unsigned char)value;
    p[1] = (unsigned char)(value >> 8);
}
#endif

static unsigned char gb_service_owner_valid(gb_owner_t owner)
{
    unsigned char low = (unsigned char)owner;
    unsigned char slot;

    if (!low || low > GB_SERVICE_OWNER_MAX) return 0;
    slot = (unsigned char)(low - 1u);
    return (unsigned char)(GB_SERVICE_OWNER_ACTIVE[slot] != 0u &&
        GB_SERVICE_OWNER_GEN[slot] == (unsigned char)(owner >> 8));
}

static void gb_service_clear_lease(unsigned char slot)
{
    volatile unsigned char *lease = gb_service_lease_at(slot);
    lease[GB_SERVICE_L_OWNER] = 0;
    lease[GB_SERVICE_L_OWNER + 1u] = 0;
    lease[GB_SERVICE_L_PROVIDER] = 0;
}

static void gb_service_clear_provider(unsigned char slot)
{
    volatile unsigned char *provider = gb_service_provider_at(slot);
    unsigned char i;

    provider[GB_SERVICE_P_ID] = 0;
    provider[GB_SERVICE_P_ID + 1u] = 0;
    provider[GB_SERVICE_P_OWNER] = 0;
    provider[GB_SERVICE_P_OWNER + 1u] = 0;
    provider[GB_SERVICE_P_STATE] = GB_SERVICE_PROVIDER_FREE;
    provider[GB_SERVICE_P_REFS] = 0;
    for (i = 0; i < GB_SERVICE_LEASE_MAX; i++) {
        volatile unsigned char *lease = gb_service_lease_at(i);
        if (lease[GB_SERVICE_L_OWNER] &&
            lease[GB_SERVICE_L_PROVIDER] == (unsigned char)(slot + 1u))
            gb_service_clear_lease(i);
    }
}

#ifndef GB_SERVICE_INTERNAL_COLLECTOR
static signed char gb_service_find_provider_slot(unsigned int service_id,
                                                  unsigned char ready_only)
{
    unsigned char i;
    for (i = 0; i < GB_SERVICE_PROVIDER_MAX; i++) {
        volatile unsigned char *provider = gb_service_provider_at(i);
        if (provider[GB_SERVICE_P_STATE] == GB_SERVICE_PROVIDER_FREE) continue;
        if (!gb_service_owner_valid(gb_service_word(
                provider + GB_SERVICE_P_OWNER))) {
            gb_service_clear_provider(i);
            continue;
        }
        if (gb_service_word(provider + GB_SERVICE_P_ID) == service_id &&
            (!ready_only ||
             provider[GB_SERVICE_P_STATE] == GB_SERVICE_PROVIDER_READY))
            return (signed char)i;
    }
    return -1;
}
#endif

static unsigned char gb_service_enter(void)
{
    if (GB_SERVICE_SCHED_CURRENT) return GB_SERVICE_ERR_CONTEXT;
    if (GB_SERVICE_LOCK) return GB_SERVICE_ERR_BUSY;
    GB_SERVICE_LOCK = 1;
    return GB_SERVICE_OK;
}

static void gb_service_leave(unsigned char status)
{
    GB_SERVICE_DIAG = status;
    GB_SERVICE_LOCK = 0;
}

static unsigned char gb_service_supported(void)
{
    const gb_sysinfo_t *info = gb_sysinfo();
    return (unsigned char)(info && info->size >= 20u && info->version >= 5u &&
        (info->capabilities & GB_CAP_SERVICE_MANAGER) != 0u);
}

static unsigned char gb_service_defer_status(unsigned char status)
{
    if (status == GB_DEFER_OK) return GB_SERVICE_OK;
    if (status == GB_DEFER_ERR_FULL) return GB_SERVICE_ERR_QUEUE;
    if (status == GB_DEFER_ERR_CONTEXT) return GB_SERVICE_ERR_CONTEXT;
    if (status == GB_DEFER_ERR_STALE || status == GB_DEFER_ERR_NO_HANDLER)
        return GB_SERVICE_ERR_PROVIDER;
    return GB_SERVICE_ERR_BADARG;
}

#endif
