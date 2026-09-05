/* Execute actual client/provider/collector policy, with no native addresses.
 * Host ABI sizes/timing are not Z80 ABI or emulator evidence. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_SERVICE_PLATFORM_HEADER "service_core_provider.h"
#include "../lib/gembench/gbservice_client.c"
#include "../lib/gembench/gbservice_provider.c"
#include "../lib/gembench/gbservice_collect.c"

volatile unsigned char service_memory[65536];
static gb_owner_t caller = 0x0101;
static gb_sysinfo_t information;
static unsigned char send_status, start_fails, sends;
static gb_defer_send_t last_message;

const gb_sysinfo_t *gb_sysinfo(void) { return &information; }
gb_owner_t gb_owner_current(void) { return caller; }
unsigned char gb_defer_send(const gb_defer_send_t *message)
{
    last_message = *message;
    sends++;
    return send_status;
}
void gb_wm_open(const char *name)
{
    gb_owner_t saved = caller;
    assert(name != NULL);
    if (start_fails) return;
    caller = 0x0102;
    assert(gb_service_provider_register(1) == GB_SERVICE_OK);
    caller = saved;
}
static void reset(void)
{
    unsigned char i;
    memset((void *)service_memory, 0, sizeof(service_memory));
    memset(&information, 0, sizeof(information));
    information.size = 20;
    information.version = 5;
    information.capabilities = GB_CAP_SERVICE_MANAGER;
    for (i = 0; i < GB_SERVICE_OWNER_MAX; i++) {
        GB_SERVICE_OWNER_ACTIVE[i] = 1;
        GB_SERVICE_OWNER_GEN[i] = 1;
    }
    caller = 0x0101;
    send_status = start_fails = sends = 0;
}
int main(void)
{
    gb_service_t a, b, c, d;
    gb_defer_message_t request;
    reset();
    information.capabilities = 0;
    assert(gb_service_acquire(1, "NETSVC  APP", &a) == GB_SERVICE_ERR_UNSUPPORTED);
    information.capabilities = GB_CAP_SERVICE_MANAGER;
    GB_SERVICE_SCHED_CURRENT = 1;
    assert(gb_service_acquire(1, "NETSVC  APP", &a) == GB_SERVICE_ERR_CONTEXT);
    GB_SERVICE_SCHED_CURRENT = 0;
    GB_SERVICE_LOCK = 1;
    assert(gb_service_acquire(1, "NETSVC  APP", &a) == GB_SERVICE_ERR_BUSY);
    GB_SERVICE_LOCK = 0;
    start_fails = 1;
    assert(gb_service_acquire(1, "NETSVC  APP", &a) == GB_SERVICE_ERR_START);
    assert(GB_SERVICE_PROVIDER_BASE[GB_SERVICE_P_STATE] == 0 && !GB_SERVICE_LOCK);
    start_fails = 0;
    assert(gb_service_acquire(1, "NETSVC  APP", &a) == GB_SERVICE_OK);
    assert(a == 0x0101 && last_message.p0 == GB_SERVICE_MSG_ACQUIRE);
    assert(gb_service_find(1) == 0x0102);
    assert(gb_service_acquire(1, "NETSVC  APP", &d) == GB_SERVICE_ERR_DUPLICATE);
    caller = 0x0103;
    assert(gb_service_request(a, 1, 0) == GB_SERVICE_ERR_OWNER);
    assert(gb_service_acquire(1, "NETSVC  APP", &b) == GB_SERVICE_OK);
    caller = 0x0104;
    send_status = GB_DEFER_ERR_FULL;
    assert(gb_service_acquire(1, "NETSVC  APP", &c) == GB_SERVICE_ERR_QUEUE);
    assert(!GB_SERVICE_LEASE_BASE[2 * GB_SERVICE_LEASE_SIZE]);
    send_status = GB_DEFER_OK;
    assert(gb_service_acquire(1, "NETSVC  APP", &c) == GB_SERVICE_OK);
    caller = 0x0105;
    assert(gb_service_acquire(1, "NETSVC  APP", &d) == GB_SERVICE_ERR_FULL);
    caller = 0x0102;
    assert(gb_service_provider_references(1) == 3);
    assert(gb_service_provider_unregister(1) == GB_SERVICE_ERR_BUSY);
    memset(&request, 0, sizeof(request));
    request.type = GB_DEFER_SERVICE;
    request.p0 = GB_SERVICE_MSG_REQUEST;
    request.sender = 0x0103;
    assert(gb_service_provider_accept(1, &request));
    request.sender = 0x0105;
    assert(!gb_service_provider_accept(1, &request));
    GB_SERVICE_OWNER_ACTIVE[2] = 0;  /* client B died */
    gb_service_collect();
    assert(gb_service_provider_references(1) == 2);
    caller = 0x0103;
    assert(gb_service_release(b) == GB_SERVICE_ERR_STALE);
    caller = 0x0104;
    assert(gb_service_release(c) == GB_SERVICE_OK);
    caller = 0x0101;
    send_status = GB_DEFER_ERR_FULL;
    assert(gb_service_release(a) == GB_SERVICE_OK); /* queue cannot pin lease */
    gb_service_collect();
    assert(GB_SERVICE_PROVIDER_BASE[GB_SERVICE_P_STATE] == GB_SERVICE_PROVIDER_STOPPING);
    send_status = GB_DEFER_OK;
    sends = 0;
    gb_service_collect();
    assert(sends == 1 && last_message.p0 == GB_SERVICE_MSG_STOP);
    assert(GB_SERVICE_PROVIDER_BASE[GB_SERVICE_P_STATE] == GB_SERVICE_PROVIDER_STOP_QUEUED);
    caller = 0x0102;
    assert(gb_service_provider_should_stop(1));
    assert(gb_service_provider_unregister(1) == GB_SERVICE_OK);
    assert(GB_SERVICE_PROVIDER_BASE[GB_SERVICE_P_GEN] == 1);
    caller = 0x0101;
    assert(gb_service_acquire(1, "NETSVC  APP", &d) == GB_SERVICE_OK);
    assert(d == 0x0201 && gb_service_request(a, 1, 0) == GB_SERVICE_ERR_STALE);
    GB_SERVICE_OWNER_GEN[1] = 2; /* provider owner was reused */
    gb_service_collect();
    assert(!GB_SERVICE_PROVIDER_BASE[GB_SERVICE_P_STATE]);
    assert(!GB_SERVICE_LEASE_BASE[GB_SERVICE_L_OWNER]);
    assert(GB_SERVICE_LEASE_BASE[GB_SERVICE_L_GEN] == 2);

    reset();
    GB_SERVICE_PROVIDER_BASE[GB_SERVICE_P_GEN] = 255;
    GB_SERVICE_LEASE_BASE[GB_SERVICE_L_GEN] = 255;
    assert(gb_service_acquire(1, "NETSVC  APP", &a) == GB_SERVICE_OK);
    assert(a == 0x0101 && GB_SERVICE_PROVIDER_BASE[GB_SERVICE_P_GEN] == 1);
    reset();
    caller = 0x0102;
    assert(gb_service_provider_register(1) == GB_SERVICE_OK);
    caller = 0x0103;
    assert(gb_service_provider_register(2) == GB_SERVICE_OK);
    caller = 0x0104;
    assert(gb_service_provider_register(3) == GB_SERVICE_ERR_FULL);
    gb_service_collect();
    assert(sends == 1);
    gb_service_collect();
    assert(sends == 2 && !GB_SERVICE_LOCK);
    puts("service core: PASS");
    return 0;
}
