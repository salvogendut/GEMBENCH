/* Architecture M7 shared-service target probe (#43).
 *
 * Four separately loaded applications share this source. Client A drives the
 * scenario, B deliberately exits without releasing, C releases on command,
 * and D proves the bounded fourth acquire fails. Results live in fixed test
 * scratch so an emulator can verify cleanup after application pages unmap. */
#include "gb.h"
#include "gbdefer.h"
#include "gbservice.h"

#ifndef GB_SERVICE_TEST_ID
#define GB_SERVICE_TEST_ID 1
#endif

#define DIAG ((volatile unsigned char *)0xC040u)
#define D_MAGIC          0u
#define D_PHASE          1u
#define D_FAIL           2u
#define D_RESPONSES      3u
#define D_INITIAL_FREE   4u
#define D_ROLLBACK_FREE  5u
#define D_FAIL_START     6u
#define D_ACQUIRE_A      7u
#define D_DUPLICATE_A    8u
#define D_REQUEST_A      9u
#define D_ACQUIRE_B     10u
#define D_FOREIGN_B     11u
#define D_REQUEST_B     12u
#define D_ACQUIRE_C     13u
#define D_REQUEST_C     14u
#define D_ACQUIRE_D     15u
#define D_RELEASE_C     16u
#define D_RELEASE_A     17u
#define D_STALE_B       18u
#define D_REFS_LOADED   19u
#define D_REFS_B_GONE   20u
#define D_REFS_C_GONE   21u
#define D_REFS_A_GONE   22u
#define D_PROVIDER_SEEN 23u
#define D_PROVIDER_GONE 24u
#define D_OWNER_INITIAL 25u
#define D_OWNER_FINAL   26u
#define D_FINAL_LEASES  27u
#define D_HANDLE_A      28u
#define D_HANDLE_B      30u
#define D_HANDLE_C      32u
#define D_OWNER_A       34u
#define D_OWNER_B       36u
#define D_OWNER_C       38u
#define D_COMMAND       40u
#define D_RESPONSE_A    41u
#define D_RESPONSE_B    42u
#define D_RESPONSE_C    43u

#define RESPONSE_A 0x01u
#define RESPONSE_B 0x02u
#define RESPONSE_C 0x04u
#define CLIENT_COMMAND 0x44u

#define PROVIDERS ((volatile unsigned char *)0xC884u)
#define LEASES    ((volatile unsigned char *)0xC892u)

static gb_service_t service;
static gb_owner_t owner;
static unsigned char started;

static void put_word(unsigned char offset, unsigned int value)
{
    DIAG[offset] = (unsigned char)value;
    DIAG[offset + 1u] = (unsigned char)(value >> 8);
}

static unsigned int get_word(unsigned char offset)
{
    return (unsigned int)DIAG[offset] |
           ((unsigned int)DIAG[offset + 1u] << 8);
}

static unsigned char owner_valid(gb_owner_t value)
{
    unsigned char low = (unsigned char)value;
    unsigned char slot;
    if (!low || low > 8u) return 0;
    slot = (unsigned char)(low - 1u);
    return (unsigned char)(*((volatile unsigned char *)0xC2C0u + slot) &&
        *((volatile unsigned char *)0xC2C8u + slot) ==
            (unsigned char)(value >> 8));
}

static unsigned char owner_count(void)
{
    unsigned char i, count = 0;
    for (i = 0; i < 8u; i++)
        if (*((volatile unsigned char *)0xC2C0u + i)) count++;
    return count;
}

static unsigned char provider_refs(void)
{
    unsigned char i;
    for (i = 0; i < GB_SERVICE_PROVIDER_CAPACITY; i++) {
        volatile unsigned char *provider = PROVIDERS + (unsigned int)i * 7u;
        if (((unsigned int)provider[0] |
             ((unsigned int)provider[1] << 8)) == GB_SERVICE_NETWORK)
            return provider[5];
    }
    return 0xFFu;
}

static unsigned char live_leases(void)
{
    unsigned char i, count = 0;
    for (i = 0; i < GB_SERVICE_LEASE_CAPACITY; i++)
        if (LEASES[(unsigned int)i * 4u]) count++;
    return count;
}

static void fail(unsigned char code)
{
    if (!DIAG[D_FAIL]) DIAG[D_FAIL] = code;
    DIAG[D_PHASE] = 0xEEu;
}

static void service_message(void)
{
    const gb_defer_message_t *message = gb_defer_current();
#if GB_SERVICE_TEST_ID == 3
    if (message && message->type == CLIENT_COMMAND) {
        DIAG[D_RELEASE_C] = gb_service_release(service);
        service = 0;
        (void)gb_app_quit();
        return;
    }
#endif
    if (!message || message->type != GB_DEFER_SERVICE ||
        message->p0 != GB_SERVICE_MSG_RESPONSE ||
        message->p1 != GB_SERVICE_NET_PROBE)
        return;

#if GB_SERVICE_TEST_ID == 1
    DIAG[D_RESPONSE_A] = message->p2;
    DIAG[D_RESPONSES] |= RESPONSE_A;
    /* Client C is topmost after the nested launches. Ask the deferred dispatcher
     * to raise A after this callback so its frame can continue orchestration. */
    gb_defer_activate();
#elif GB_SERVICE_TEST_ID == 2
    DIAG[D_RESPONSE_B] = message->p2;
    DIAG[D_RESPONSES] |= RESPONSE_B;
    /* No release: Desktop's collector must reclaim this stale-owner lease. */
    (void)gb_app_quit();
#elif GB_SERVICE_TEST_ID == 3
    DIAG[D_RESPONSE_C] = message->p2;
    DIAG[D_RESPONSES] |= RESPONSE_C;
#endif
}

#if GB_SERVICE_TEST_ID == 1
static void start_scenario(void)
{
    gb_service_t duplicate = 0xFFFFu;
    gb_service_t failed = 0xFFFFu;

    DIAG[D_INITIAL_FREE] = gb_sysinfo()->free_pages;
    DIAG[D_OWNER_INITIAL] = owner_count();
    DIAG[D_FAIL_START] = gb_service_acquire(0x7777u, "FAILSVC APP",
                                             &failed);
    DIAG[D_ROLLBACK_FREE] = gb_sysinfo()->free_pages;
    if (DIAG[D_FAIL_START] != GB_SERVICE_ERR_START || failed ||
        DIAG[D_INITIAL_FREE] != DIAG[D_ROLLBACK_FREE] ||
        DIAG[D_OWNER_INITIAL] != owner_count()) {
        fail(1u);
        return;
    }

    DIAG[D_ACQUIRE_A] = gb_service_acquire(
        GB_SERVICE_NETWORK, GB_SERVICE_NETWORK_APP, &service);
    put_word(D_HANDLE_A, service);
    DIAG[D_PROVIDER_SEEN] = (unsigned char)(gb_service_find(
        GB_SERVICE_NETWORK) != 0u);
    DIAG[D_DUPLICATE_A] = gb_service_acquire(
        GB_SERVICE_NETWORK, GB_SERVICE_NETWORK_APP, &duplicate);
    DIAG[D_REQUEST_A] = gb_service_request(service, GB_SERVICE_NET_PROBE, 0);
    if (DIAG[D_ACQUIRE_A] != GB_SERVICE_OK || !service ||
        !DIAG[D_PROVIDER_SEEN] ||
        DIAG[D_DUPLICATE_A] != GB_SERVICE_ERR_DUPLICATE || duplicate ||
        DIAG[D_REQUEST_A] != GB_SERVICE_OK) {
        fail(2u);
        return;
    }

    gb_wm_open("SVCTSTB APP");
    gb_wm_open("SVCTSTC APP");
    gb_wm_open("SVCTSTD APP");
    DIAG[D_REFS_LOADED] = provider_refs();
    if (DIAG[D_ACQUIRE_B] != GB_SERVICE_OK ||
        DIAG[D_FOREIGN_B] != GB_SERVICE_ERR_OWNER ||
        DIAG[D_REQUEST_B] != GB_SERVICE_OK ||
        DIAG[D_ACQUIRE_C] != GB_SERVICE_OK ||
        DIAG[D_REQUEST_C] != GB_SERVICE_OK ||
        DIAG[D_ACQUIRE_D] != GB_SERVICE_ERR_FULL ||
        DIAG[D_REFS_LOADED] != GB_SERVICE_LEASE_CAPACITY) {
        fail(3u);
        return;
    }
    DIAG[D_PHASE] = 2u;
}

static void drive_scenario(void)
{
    unsigned char refs;
    gb_defer_send_t command;

    if (DIAG[D_PHASE] == 1u && !started) {
        started = 1;
        start_scenario();
        return;
    }
    if (DIAG[D_PHASE] == 2u &&
        (DIAG[D_RESPONSES] & (RESPONSE_A | RESPONSE_B | RESPONSE_C)) ==
            (RESPONSE_A | RESPONSE_B | RESPONSE_C) &&
        !owner_valid(get_word(D_OWNER_B))) {
        refs = provider_refs();
        if (refs != 2u) return; /* collector has not reconciled B yet */
        DIAG[D_REFS_B_GONE] = refs;
        DIAG[D_STALE_B] = gb_service_request(get_word(D_HANDLE_B),
                                              GB_SERVICE_NET_PROBE, 0);
        if (DIAG[D_STALE_B] != GB_SERVICE_ERR_STALE) {
            fail(4u);
            return;
        }
        command.receiver = get_word(D_OWNER_C);
        command.type = CLIENT_COMMAND;
        command.p0 = command.p1 = command.p2 = 0;
        if (gb_defer_send(&command) != GB_DEFER_OK) {
            fail(8u);
            return;
        }
        DIAG[D_COMMAND] = 1u;
        DIAG[D_PHASE] = 3u;
        return;
    }
    if (DIAG[D_PHASE] == 3u && DIAG[D_RELEASE_C] != 0xFFu) {
        DIAG[D_REFS_C_GONE] = provider_refs();
        if (DIAG[D_RELEASE_C] != GB_SERVICE_OK ||
            DIAG[D_REFS_C_GONE] != 1u) {
            fail(5u);
            return;
        }
        DIAG[D_RELEASE_A] = gb_service_release(service);
        service = 0;
        DIAG[D_REFS_A_GONE] = provider_refs();
        if (DIAG[D_RELEASE_A] != GB_SERVICE_OK || DIAG[D_REFS_A_GONE] != 0u) {
            fail(6u);
            return;
        }
        DIAG[D_PHASE] = 4u;
        return;
    }
    if (DIAG[D_PHASE] == 4u && gb_service_find(GB_SERVICE_NETWORK) == 0u) {
        DIAG[D_PROVIDER_GONE] = 1u;
        DIAG[D_FINAL_LEASES] = live_leases();
        DIAG[D_OWNER_FINAL] = owner_count();
        if (DIAG[D_FINAL_LEASES] ||
            DIAG[D_OWNER_FINAL] != DIAG[D_OWNER_INITIAL]) {
            fail(7u);
            return;
        }
        DIAG[D_PHASE] = 7u;
    }
}
#else
static void drive_scenario(void) { }
#endif

static void test_proc(void)
{
    switch (gb_msg.type) {
    case GB_MSG_DRAW:  break;
    case GB_MSG_FRAME: drive_scenario(); break;
    case GB_MSG_CLOSE:
        if (service) (void)gb_service_release(service);
        gb_wm_close();
        break;
    }
}

static const gb_mwin_t test_window = {
    (unsigned char)(6u + GB_SERVICE_TEST_ID * 8u),
    (unsigned char)(24u + GB_SERVICE_TEST_ID * 8u),
    24u, 36u, 0u, 0u, test_proc, "M7 service probe"
};

void main(void)
{
#if GB_SERVICE_TEST_ID == 1
    unsigned char i;
#elif GB_SERVICE_TEST_ID == 2
    gb_service_t foreign;
#endif

#if GB_SERVICE_TEST_ID == 1
    for (i = 0; i < 48u; i++) DIAG[i] = 0;
    DIAG[D_MAGIC] = 0xA7u;
    DIAG[D_PHASE] = 1u;
    DIAG[D_RELEASE_C] = 0xFFu;
#endif
    gb_wm_managed(&test_window);
    owner = gb_owner_current();
    if (gb_defer_register(service_message) != GB_DEFER_OK) {
        fail((unsigned char)(20u + GB_SERVICE_TEST_ID));
        return;
    }

#if GB_SERVICE_TEST_ID == 1
    put_word(D_OWNER_A, owner);
#elif GB_SERVICE_TEST_ID == 2
    put_word(D_OWNER_B, owner);
    DIAG[D_ACQUIRE_B] = gb_service_acquire(
        GB_SERVICE_NETWORK, GB_SERVICE_NETWORK_APP, &service);
    put_word(D_HANDLE_B, service);
    foreign = get_word(D_HANDLE_A);
    DIAG[D_FOREIGN_B] = gb_service_request(foreign, GB_SERVICE_NET_PROBE, 0);
    DIAG[D_REQUEST_B] = gb_service_request(service, GB_SERVICE_NET_PROBE, 0);
#elif GB_SERVICE_TEST_ID == 3
    put_word(D_OWNER_C, owner);
    DIAG[D_ACQUIRE_C] = gb_service_acquire(
        GB_SERVICE_NETWORK, GB_SERVICE_NETWORK_APP, &service);
    put_word(D_HANDLE_C, service);
    DIAG[D_REQUEST_C] = gb_service_request(service, GB_SERVICE_NET_PROBE, 0);
#else
    DIAG[D_ACQUIRE_D] = gb_service_acquire(
        GB_SERVICE_NETWORK, GB_SERVICE_NETWORK_APP, &service);
    if (service) (void)gb_service_release(service);
    gb_wm_close();
#endif
    gb_restore_parent();
}
