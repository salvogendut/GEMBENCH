#include "gbservice_internal.h"

static signed char find_client_lease(gb_owner_t owner,
                                     unsigned int service_id)
{
    unsigned char i;
    for (i = 0; i < GB_SERVICE_LEASE_MAX; i++) {
        volatile unsigned char *lease = gb_service_lease_at(i);
        unsigned char provider_slot;
        volatile unsigned char *provider;
        if (gb_service_word(lease + GB_SERVICE_L_OWNER) != owner) continue;
        provider_slot = lease[GB_SERVICE_L_PROVIDER];
        if (!provider_slot || provider_slot > GB_SERVICE_PROVIDER_MAX) continue;
        provider = gb_service_provider_at((unsigned char)(provider_slot - 1u));
        if (gb_service_word(provider + GB_SERVICE_P_ID) == service_id)
            return (signed char)i;
    }
    return -1;
}

static unsigned char validate_lease(gb_service_t handle, gb_owner_t owner,
                                    unsigned char *lease_slot,
                                    unsigned char *provider_slot)
{
    unsigned char low = (unsigned char)handle;
    volatile unsigned char *lease;
    volatile unsigned char *provider;
    if (!low || low > GB_SERVICE_LEASE_MAX) return GB_SERVICE_ERR_STALE;
    *lease_slot = (unsigned char)(low - 1u);
    lease = gb_service_lease_at(*lease_slot);
    if (!lease[GB_SERVICE_L_OWNER] ||
        lease[GB_SERVICE_L_GEN] != (unsigned char)(handle >> 8))
        return GB_SERVICE_ERR_STALE;
    if (gb_service_word(lease + GB_SERVICE_L_OWNER) != owner)
        return GB_SERVICE_ERR_OWNER;
    *provider_slot = lease[GB_SERVICE_L_PROVIDER];
    if (!*provider_slot || *provider_slot > GB_SERVICE_PROVIDER_MAX)
        return GB_SERVICE_ERR_STALE;
    provider = gb_service_provider_at((unsigned char)(*provider_slot - 1u));
    if (provider[GB_SERVICE_P_STATE] == GB_SERVICE_PROVIDER_FREE ||
        !gb_service_owner_valid(gb_service_word(
            provider + GB_SERVICE_P_OWNER)))
        return GB_SERVICE_ERR_PROVIDER;
    return GB_SERVICE_OK;
}

gb_owner_t gb_service_find(unsigned int service_id)
{
    signed char slot;
    gb_owner_t owner = 0;
    unsigned char status;

    if (!service_id || !gb_service_supported()) return 0;
    status = gb_service_enter();
    if (status != GB_SERVICE_OK) return 0;
    slot = gb_service_find_provider_slot(service_id, 1u);
    if (slot >= 0)
        owner = gb_service_word(gb_service_provider_at((unsigned char)slot) +
                                GB_SERVICE_P_OWNER);
    gb_service_leave(GB_SERVICE_OK);
    return owner;
}

unsigned char gb_service_acquire(unsigned int service_id,
                                 const char *provider_app11,
                                 gb_service_t *handle)
{
    gb_owner_t owner;
    signed char provider_slot;
    unsigned char lease_slot, gen, status;
    volatile unsigned char *provider;
    volatile unsigned char *lease;
    gb_defer_send_t message;

    if (handle) *handle = 0;
    if (!service_id || !provider_app11 || !handle)
        return GB_SERVICE_ERR_BADARG;
    if (!gb_service_supported()) return GB_SERVICE_ERR_UNSUPPORTED;
    owner = gb_owner_current();
    if (!gb_service_owner_valid(owner)) return GB_SERVICE_ERR_CONTEXT;

    status = gb_service_enter();
    if (status != GB_SERVICE_OK) return status;
    provider_slot = gb_service_find_provider_slot(service_id, 0u);
    if (provider_slot >= 0) {
        provider = gb_service_provider_at((unsigned char)provider_slot);
        if (provider[GB_SERVICE_P_STATE] == GB_SERVICE_PROVIDER_STOPPING &&
            provider[GB_SERVICE_P_REFS] == 0)
            provider[GB_SERVICE_P_STATE] = GB_SERVICE_PROVIDER_READY;
        else if (provider[GB_SERVICE_P_STATE] != GB_SERVICE_PROVIDER_READY) {
            gb_service_leave(GB_SERVICE_ERR_BUSY);
            return GB_SERVICE_ERR_BUSY;
        }
    }
    gb_service_leave(GB_SERVICE_OK);

    if (provider_slot < 0) {
        gb_wm_open(provider_app11);
        status = gb_service_enter();
        if (status != GB_SERVICE_OK) return status;
        provider_slot = gb_service_find_provider_slot(service_id, 1u);
        if (provider_slot < 0) {
            gb_service_leave(GB_SERVICE_ERR_START);
            return GB_SERVICE_ERR_START;
        }
        gb_service_leave(GB_SERVICE_OK);
    }

    status = gb_service_enter();
    if (status != GB_SERVICE_OK) return status;
    if (find_client_lease(owner, service_id) >= 0) {
        gb_service_leave(GB_SERVICE_ERR_DUPLICATE);
        return GB_SERVICE_ERR_DUPLICATE;
    }
    for (lease_slot = 0; lease_slot < GB_SERVICE_LEASE_MAX; lease_slot++)
        if (!gb_service_lease_at(lease_slot)[GB_SERVICE_L_OWNER]) break;
    if (lease_slot == GB_SERVICE_LEASE_MAX) {
        gb_service_leave(GB_SERVICE_ERR_FULL);
        return GB_SERVICE_ERR_FULL;
    }
    provider = gb_service_provider_at((unsigned char)provider_slot);
    if (provider[GB_SERVICE_P_STATE] != GB_SERVICE_PROVIDER_READY ||
        !gb_service_owner_valid(gb_service_word(
            provider + GB_SERVICE_P_OWNER))) {
        gb_service_leave(GB_SERVICE_ERR_PROVIDER);
        return GB_SERVICE_ERR_PROVIDER;
    }
    lease = gb_service_lease_at(lease_slot);
    gen = (unsigned char)(lease[GB_SERVICE_L_GEN] + 1u);
    if (!gen) gen = 1u;

    message.receiver = gb_service_word(provider + GB_SERVICE_P_OWNER);
    message.type = GB_DEFER_SERVICE;
    message.p0 = GB_SERVICE_MSG_ACQUIRE;
    message.p1 = (unsigned char)(lease_slot + 1u);
    message.p2 = gen;
    status = gb_service_defer_status(gb_defer_send(&message));
    if (status != GB_SERVICE_OK) {
        if (status == GB_SERVICE_ERR_PROVIDER)
            gb_service_clear_provider((unsigned char)provider_slot);
        gb_service_leave(status);
        return status;
    }

    gb_service_put_word(lease + GB_SERVICE_L_OWNER, owner);
    lease[GB_SERVICE_L_PROVIDER] = (unsigned char)(provider_slot + 1);
    lease[GB_SERVICE_L_GEN] = gen;
    provider[GB_SERVICE_P_REFS]++;
    *handle = (gb_service_t)(((unsigned int)gen << 8) |
                            (unsigned int)(lease_slot + 1u));
    gb_service_leave(GB_SERVICE_OK);
    return GB_SERVICE_OK;
}

unsigned char gb_service_request(gb_service_t handle,
                                 unsigned char request,
                                 unsigned char value)
{
    gb_owner_t owner;
    unsigned char lease_slot, provider_slot, status;
    volatile unsigned char *provider;
    gb_defer_send_t message;

    if (!request) return GB_SERVICE_ERR_BADARG;
    if (!gb_service_supported()) return GB_SERVICE_ERR_UNSUPPORTED;
    owner = gb_owner_current();
    status = gb_service_enter();
    if (status != GB_SERVICE_OK) return status;
    status = validate_lease(handle, owner, &lease_slot, &provider_slot);
    if (status != GB_SERVICE_OK) {
        gb_service_leave(status);
        return status;
    }
    provider = gb_service_provider_at((unsigned char)(provider_slot - 1u));
    if (provider[GB_SERVICE_P_STATE] != GB_SERVICE_PROVIDER_READY) {
        gb_service_leave(GB_SERVICE_ERR_BUSY);
        return GB_SERVICE_ERR_BUSY;
    }
    message.receiver = gb_service_word(provider + GB_SERVICE_P_OWNER);
    message.type = GB_DEFER_SERVICE;
    message.p0 = GB_SERVICE_MSG_REQUEST;
    message.p1 = request;
    message.p2 = value;
    status = gb_service_defer_status(gb_defer_send(&message));
    if (status == GB_SERVICE_ERR_PROVIDER)
        gb_service_clear_provider((unsigned char)(provider_slot - 1u));
    gb_service_leave(status);
    return status;
}

unsigned char gb_service_release(gb_service_t handle)
{
    gb_owner_t owner;
    unsigned char lease_slot, provider_slot, status;
    volatile unsigned char *provider;
    volatile unsigned char *lease;
    gb_defer_send_t message;

    if (!gb_service_supported()) return GB_SERVICE_ERR_UNSUPPORTED;
    owner = gb_owner_current();
    status = gb_service_enter();
    if (status != GB_SERVICE_OK) return status;
    status = validate_lease(handle, owner, &lease_slot, &provider_slot);
    if (status != GB_SERVICE_OK) {
        gb_service_leave(status);
        return status;
    }
    lease = gb_service_lease_at(lease_slot);
    provider = gb_service_provider_at((unsigned char)(provider_slot - 1u));
    message.receiver = gb_service_word(provider + GB_SERVICE_P_OWNER);
    message.type = GB_DEFER_SERVICE;
    message.p0 = GB_SERVICE_MSG_RELEASE;
    message.p1 = (unsigned char)(lease_slot + 1u);
    message.p2 = lease[GB_SERVICE_L_GEN];
    status = gb_service_defer_status(gb_defer_send(&message));
    /* A full control queue must not pin a client lease indefinitely. The
     * table is authoritative: clear the reference and let the root collector
     * retry a final STOP when queue space becomes available. */
    if (status != GB_SERVICE_OK && status != GB_SERVICE_ERR_PROVIDER &&
        status != GB_SERVICE_ERR_QUEUE) {
        gb_service_leave(status);
        return status;
    }
    gb_service_clear_lease(lease_slot);
    if (provider[GB_SERVICE_P_REFS]) provider[GB_SERVICE_P_REFS]--;
    if (!provider[GB_SERVICE_P_REFS])
        provider[GB_SERVICE_P_STATE] = GB_SERVICE_PROVIDER_STOPPING;
    if (status == GB_SERVICE_ERR_PROVIDER)
        gb_service_clear_provider((unsigned char)(provider_slot - 1u));
    gb_service_leave(GB_SERVICE_OK);
    return GB_SERVICE_OK;
}
