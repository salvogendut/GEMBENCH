/* NETSVC.APP - first Architecture-M7 shared-service provider (#43).
 *
 * This deliberately starts with the MSX TCP/IP UNAPI control plane: clients
 * share provider discovery, lifetime, capability probing, failure rollback,
 * and final unload. Existing socket data paths remain client-local until a
 * later bounded bulk-transfer contract can preserve independent sessions. */
#include "gb.h"
#include "gbdefer.h"
#include "gbservice.h"

static void service_message(void)
{
    const gb_defer_message_t *message = gb_defer_current();

    if (!message || message->type != GB_DEFER_SERVICE) return;
    if (message->p0 == GB_SERVICE_MSG_REQUEST &&
        gb_service_provider_accept(GB_SERVICE_NETWORK, message)) {
        unsigned char result = GB_SERVICE_ERR_BADARG;
        if (message->p1 == GB_SERVICE_NET_PROBE)
            result = gb_net_init(0) ? GB_SERVICE_OK : GB_SERVICE_ERR_PROVIDER;
        (void)gb_service_reply(message->sender, message->p1, result);
        return;
    }
    if ((message->p0 == GB_SERVICE_MSG_RELEASE ||
         message->p0 == GB_SERVICE_MSG_STOP) &&
        gb_service_provider_should_stop(GB_SERVICE_NETWORK)) {
        if (gb_service_provider_unregister(GB_SERVICE_NETWORK) ==
            GB_SERVICE_OK)
            (void)gb_app_quit();
    }
}

void main(void)
{
    if (gb_defer_register(service_message) != GB_DEFER_OK) return;
    if (gb_service_provider_register(GB_SERVICE_NETWORK) != GB_SERVICE_OK) {
        (void)gb_defer_register(0);
        return;
    }
    if (gb_app_publish() != GB_APP_OK) {
        (void)gb_service_provider_unregister(GB_SERVICE_NETWORK);
        (void)gb_defer_register(0);
    }
}
