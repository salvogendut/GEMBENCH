#define GB_SERVICE_INTERNAL_COLLECTOR 1
#include "gbservice_internal.h"

void gb_service_collect(void)
{
    unsigned char i, refs[GB_SERVICE_PROVIDER_MAX];
    unsigned char status;
    gb_defer_send_t message;

    if (!gb_service_supported()) return;
    status = gb_service_enter();
    if (status != GB_SERVICE_OK) return;
    for (i = 0; i < GB_SERVICE_PROVIDER_MAX; i++) {
        volatile unsigned char *provider = gb_service_provider_at(i);
        refs[i] = 0;
        if (provider[GB_SERVICE_P_STATE] != GB_SERVICE_PROVIDER_FREE &&
            !gb_service_owner_valid(gb_service_word(
                provider + GB_SERVICE_P_OWNER)))
            gb_service_clear_provider(i);
    }
    for (i = 0; i < GB_SERVICE_LEASE_MAX; i++) {
        volatile unsigned char *lease = gb_service_lease_at(i);
        unsigned char provider_slot = lease[GB_SERVICE_L_PROVIDER];
        if (!lease[GB_SERVICE_L_OWNER]) continue;
        if (!gb_service_owner_valid(gb_service_word(
                lease + GB_SERVICE_L_OWNER)) ||
            !provider_slot || provider_slot > GB_SERVICE_PROVIDER_MAX ||
            gb_service_provider_at((unsigned char)(provider_slot - 1u))
                [GB_SERVICE_P_STATE] == GB_SERVICE_PROVIDER_FREE) {
            gb_service_clear_lease(i);
            continue;
        }
        refs[provider_slot - 1u]++;
    }
    for (i = 0; i < GB_SERVICE_PROVIDER_MAX; i++) {
        volatile unsigned char *provider = gb_service_provider_at(i);
        if (provider[GB_SERVICE_P_STATE] == GB_SERVICE_PROVIDER_FREE) continue;
        provider[GB_SERVICE_P_REFS] = refs[i];
        if (!refs[i] &&
            provider[GB_SERVICE_P_STATE] == GB_SERVICE_PROVIDER_READY)
            provider[GB_SERVICE_P_STATE] = GB_SERVICE_PROVIDER_STOPPING;
        if (!refs[i] &&
            provider[GB_SERVICE_P_STATE] == GB_SERVICE_PROVIDER_STOPPING) {
            message.receiver = gb_service_word(provider + GB_SERVICE_P_OWNER);
            message.type = GB_DEFER_SERVICE;
            message.p0 = GB_SERVICE_MSG_STOP;
            message.p1 = (unsigned char)(i + 1u);
            message.p2 = provider[GB_SERVICE_P_GEN];
            status = gb_service_defer_status(gb_defer_send(&message));
            if (status == GB_SERVICE_OK)
                provider[GB_SERVICE_P_STATE] =
                    GB_SERVICE_PROVIDER_STOP_QUEUED;
            else if (status == GB_SERVICE_ERR_PROVIDER)
                gb_service_clear_provider(i);
            break;                  /* at most one bounded stop attempt per turn */
        }
    }
    gb_service_leave(status == GB_SERVICE_OK ? GB_SERVICE_OK : status);
}
