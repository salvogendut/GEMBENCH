#ifndef GEMBENCH_GBSERVICE_H
#define GEMBENCH_GBSERVICE_H

#include "gb.h"
#include "gbdefer.h"

/* Architecture Milestone 7 (#43): bounded shared-service lifecycle.
 *
 * The public identities and messages are platform-neutral. The first runtime
 * is MSX2-only and advertises GB_CAP_SERVICE_MANAGER through GB_SYSINFO v5.
 * Handles are generation tagged and remain valid only for their acquiring
 * application. */
#define GB_SERVICE_API_VERSION       1u
#define GB_SERVICE_PROVIDER_CAPACITY 2u
#define GB_SERVICE_LEASE_CAPACITY    3u

#define GB_SERVICE_NETWORK           1u
#define GB_SERVICE_NETWORK_APP       "NETSVC  APP"

typedef unsigned int gb_service_t;

#define GB_SERVICE_OK                 0u
#define GB_SERVICE_ERR_UNSUPPORTED    1u
#define GB_SERVICE_ERR_STALE          2u
#define GB_SERVICE_ERR_OWNER          3u
#define GB_SERVICE_ERR_FULL           4u
#define GB_SERVICE_ERR_BADARG         5u
#define GB_SERVICE_ERR_NOT_FOUND      6u
#define GB_SERVICE_ERR_BUSY           7u
#define GB_SERVICE_ERR_QUEUE          8u
#define GB_SERVICE_ERR_DUPLICATE      9u
#define GB_SERVICE_ERR_START         10u
#define GB_SERVICE_ERR_PROVIDER      11u
#define GB_SERVICE_ERR_CONTEXT       12u

/* GB_DEFER_SERVICE messages use the three application bytes as
 * operation/request-or-slot/value-or-generation. */
#define GB_SERVICE_MSG_ACQUIRE  1u
#define GB_SERVICE_MSG_REQUEST  2u
#define GB_SERVICE_MSG_RELEASE  3u
#define GB_SERVICE_MSG_STOP     4u
#define GB_SERVICE_MSG_RESPONSE 5u

#define GB_SERVICE_NET_PROBE 1u

/* Discovery never starts a provider and returns its generation-tagged
 * application endpoint, or zero. */
gb_owner_t gb_service_find(unsigned int service_id);

/* Acquire starts provider_app11 on first use. A successful call enqueues an
 * acquire notification and returns an application-owned lease. */
unsigned char gb_service_acquire(unsigned int service_id,
                                 const char *provider_app11,
                                 gb_service_t *lease);
unsigned char gb_service_request(gb_service_t lease,
                                 unsigned char request,
                                 unsigned char value);
unsigned char gb_service_release(gb_service_t lease);

/* Provider-side helpers. Providers register a normal deferred handler first,
 * publish as a windowless application, and use these calls only from root-task
 * startup or deferred delivery. */
unsigned char gb_service_provider_register(unsigned int service_id);
unsigned char gb_service_provider_unregister(unsigned int service_id);
unsigned char gb_service_provider_accept(unsigned int service_id,
                                         const gb_defer_message_t *message);
unsigned char gb_service_provider_references(unsigned int service_id);
unsigned char gb_service_provider_should_stop(unsigned int service_id);
unsigned char gb_service_reply(gb_owner_t receiver,
                               unsigned char request,
                               unsigned char status);

/* Desktop/root policy: reconcile stale owners and enqueue at most one final
 * stop per call. The release build invokes this from its always-live bar turn. */
void gb_service_collect(void);

#endif
