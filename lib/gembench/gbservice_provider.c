#include "gbservice_internal.h"

static signed char current_provider(unsigned int service_id,
                                    gb_owner_t owner)
{
    signed char slot = gb_service_find_provider_slot(service_id, 0u);
    if (slot < 0) return -1;
    if (gb_service_word(gb_service_provider_at((unsigned char)slot) +
                        GB_SERVICE_P_OWNER) != owner) return -1;
    return slot;
}

unsigned char gb_service_provider_register(unsigned int service_id)
{
    gb_owner_t owner;
    signed char existing;
    unsigned char slot, status, gen;
    volatile unsigned char *provider;

    if (!service_id) return GB_SERVICE_ERR_BADARG;
    if (!gb_service_supported()) return GB_SERVICE_ERR_UNSUPPORTED;
    owner = gb_owner_current();
    if (!gb_service_owner_valid(owner)) return GB_SERVICE_ERR_CONTEXT;
    status = gb_service_enter();
    if (status != GB_SERVICE_OK) return status;
    existing = gb_service_find_provider_slot(service_id, 0u);
    if (existing >= 0) {
        gb_service_leave(GB_SERVICE_ERR_DUPLICATE);
        return GB_SERVICE_ERR_DUPLICATE;
    }
    for (slot = 0; slot < GB_SERVICE_PROVIDER_MAX; slot++)
        if (gb_service_provider_at(slot)[GB_SERVICE_P_STATE] ==
            GB_SERVICE_PROVIDER_FREE) break;
    if (slot == GB_SERVICE_PROVIDER_MAX) {
        gb_service_leave(GB_SERVICE_ERR_FULL);
        return GB_SERVICE_ERR_FULL;
    }
    provider = gb_service_provider_at(slot);
    gen = (unsigned char)(provider[GB_SERVICE_P_GEN] + 1u);
    if (!gen) gen = 1u;
    gb_service_put_word(provider + GB_SERVICE_P_ID, service_id);
    gb_service_put_word(provider + GB_SERVICE_P_OWNER, owner);
    provider[GB_SERVICE_P_STATE] = GB_SERVICE_PROVIDER_READY;
    provider[GB_SERVICE_P_REFS] = 0;
    provider[GB_SERVICE_P_GEN] = gen;
    gb_service_leave(GB_SERVICE_OK);
    return GB_SERVICE_OK;
}

unsigned char gb_service_provider_unregister(unsigned int service_id)
{
    gb_owner_t owner = gb_owner_current();
    signed char slot;
    unsigned char status = gb_service_enter();
    if (status != GB_SERVICE_OK) return status;
    slot = current_provider(service_id, owner);
    if (slot < 0) {
        gb_service_leave(GB_SERVICE_ERR_OWNER);
        return GB_SERVICE_ERR_OWNER;
    }
    if (gb_service_provider_at((unsigned char)slot)[GB_SERVICE_P_REFS]) {
        gb_service_leave(GB_SERVICE_ERR_BUSY);
        return GB_SERVICE_ERR_BUSY;
    }
    gb_service_clear_provider((unsigned char)slot);
    gb_service_leave(GB_SERVICE_OK);
    return GB_SERVICE_OK;
}

unsigned char gb_service_provider_accept(unsigned int service_id,
                                         const gb_defer_message_t *message)
{
    gb_owner_t owner = gb_owner_current();
    signed char slot;
    unsigned char i, status = gb_service_enter();
    if (status != GB_SERVICE_OK) return 0;
    if (!message) {
        gb_service_leave(GB_SERVICE_ERR_BADARG);
        return 0;
    }
    slot = current_provider(service_id, owner);
    if (slot >= 0 && message->type == GB_DEFER_SERVICE &&
        message->p0 == GB_SERVICE_MSG_REQUEST) {
        for (i = 0; i < GB_SERVICE_LEASE_MAX; i++) {
            volatile unsigned char *lease = gb_service_lease_at(i);
            if (gb_service_word(lease + GB_SERVICE_L_OWNER) == message->sender &&
                lease[GB_SERVICE_L_PROVIDER] == (unsigned char)(slot + 1)) {
                gb_service_leave(GB_SERVICE_OK);
                return 1;
            }
        }
    }
    gb_service_leave(GB_SERVICE_ERR_OWNER);
    return 0;
}

unsigned char gb_service_provider_references(unsigned int service_id)
{
    gb_owner_t owner = gb_owner_current();
    signed char slot;
    unsigned char refs = 0, status = gb_service_enter();
    if (status != GB_SERVICE_OK) return 0;
    slot = current_provider(service_id, owner);
    if (slot >= 0)
        refs = gb_service_provider_at((unsigned char)slot)[GB_SERVICE_P_REFS];
    gb_service_leave(GB_SERVICE_OK);
    return refs;
}

unsigned char gb_service_provider_should_stop(unsigned int service_id)
{
    gb_owner_t owner = gb_owner_current();
    signed char slot;
    unsigned char stop = 0, status = gb_service_enter();
    if (status != GB_SERVICE_OK) return 0;
    slot = current_provider(service_id, owner);
    if (slot >= 0) {
        volatile unsigned char *provider =
            gb_service_provider_at((unsigned char)slot);
        stop = (unsigned char)(!provider[GB_SERVICE_P_REFS] &&
            provider[GB_SERVICE_P_STATE] >= GB_SERVICE_PROVIDER_STOPPING);
    }
    gb_service_leave(GB_SERVICE_OK);
    return stop;
}

unsigned char gb_service_reply(gb_owner_t receiver,
                               unsigned char request,
                               unsigned char status)
{
    gb_defer_send_t message;
    message.receiver = receiver;
    message.type = GB_DEFER_SERVICE;
    message.p0 = GB_SERVICE_MSG_RESPONSE;
    message.p1 = request;
    message.p2 = status;
    return gb_service_defer_status(gb_defer_send(&message));
}
