/* MSX TCP/IP UNAPI backend for the shared gb_net_* app API.
 *
 * UNAPI implementations may replace page 1 while servicing a call, so all
 * buffers passed to them live in GEOBENCH low RAM. The app itself remains in
 * page 1 and is restored by the UNAPI RAM helper before execution resumes. */
#include "gb.h"

#ifndef GB_MSX2
#error gbnet_unapi_stub.c is for the MSX2 target only
#endif

#define EXTBIO_ARG          ((volatile unsigned char *)0xF847)
#define GBNET_BUF           ((volatile unsigned char *)0x2200)
#define GBNET_MAXIO         1024U
#define UNAPI_SEND_CHUNK    512U
#define UNAPI_DNS_WAITS     600U
#define UNAPI_CONNECT_WAITS 900U
#define UNAPI_BUFFER_WAITS  300U

#define UNAPI_DIRECT 1
#define UNAPI_MAPPED 2

#define TCPIP_GET_CAPAB 1
#define TCPIP_DNS_Q      6
#define TCPIP_DNS_S      7
#define TCPIP_TCP_OPEN  13
#define TCPIP_TCP_CLOSE 14
#define TCPIP_TCP_ABORT 15
#define TCPIP_TCP_STATE 16
#define TCPIP_TCP_SEND  17
#define TCPIP_TCP_RCV   18
#define TCPIP_WAIT      29

#define ERR_OK       0
#define ERR_NO_DATA  3
#define ERR_NO_CONN 11
#define ERR_BUFFER  13

#define TCP_SYN_SENT     2
#define TCP_SYN_RECEIVED 3
#define TCP_ESTABLISHED  4
#define TCP_CLOSE_WAIT   7

/* Register marshal block. These values are in the app page, but the assembly
 * bridge consumes them before page 1 is replaced and writes them only after it
 * has been restored. IY is encoded as slot:segment for CALL_MAP. */
volatile unsigned char gbua_fn, gbua_a, gbua_kind;
volatile unsigned int gbua_bc, gbua_de, gbua_hl;
volatile unsigned int gbua_entry, gbua_helper, gbua_iy;

static unsigned char unapi_ready;
static unsigned char tcp_handle;
static unsigned char recv_status = GB_NET_RX_IDLE;

/* Invoke EXTBIO with the marshalled AF/BC/DE/HL registers. */
static void gbua_extbio_impl(void) __naked
{
__asm
    push ix
    push iy
    ld   a,(_gbua_fn)
    ld   bc,(_gbua_bc)
    ld   de,(_gbua_de)
    ld   hl,(_gbua_hl)
    call #0xFFCA
    ld   (_gbua_a),a
    ld   (_gbua_bc),bc
    ld   (_gbua_de),de
    ld   (_gbua_hl),hl
    pop  iy
    pop  ix
    ret
__endasm;
}

/* Invoke the selected implementation directly (page 3) or through RAM
 * helper CALL_MAP (mapped page 1). The two RETs synthesize an indirect CALL
 * while preserving HL as an input register for the target routine. */
static void gbua_call_impl(void) __naked
{
__asm
    push ix
    push iy
    ld   a,(_gbua_kind)
    cp   #UNAPI_DIRECT
    jr   z,1$
    cp   #UNAPI_MAPPED
    jr   z,2$
    ld   a,#15
    ld   bc,#0
    ld   de,#0
    ld   hl,#0
    jr   4$
1$:
    ld   hl,#3$
    push hl
    ld   hl,(_gbua_entry)
    push hl
    jr   5$
2$:
    ld   iy,(_gbua_iy)
    ld   ix,(_gbua_entry)
    ld   hl,#3$
    push hl
    ld   hl,(_gbua_helper)
    push hl
5$:
    ld   a,(_gbua_fn)
    ld   bc,(_gbua_bc)
    ld   de,(_gbua_de)
    ld   hl,(_gbua_hl)
    ret
3$:
4$:
    ld   (_gbua_a),a
    ld   (_gbua_bc),bc
    ld   (_gbua_de),de
    ld   (_gbua_hl),hl
    pop  iy
    pop  ix
    ret
__endasm;
}

static void extbio_call(unsigned char fn, unsigned int bc,
                        unsigned int de, unsigned int hl)
{
    gbua_fn = fn; gbua_bc = bc; gbua_de = de; gbua_hl = hl;
    gbua_extbio_impl();
}

static unsigned char unapi_call(unsigned char fn, unsigned int bc,
                                unsigned int de, unsigned int hl)
{
    gbua_fn = fn; gbua_bc = bc; gbua_de = de; gbua_hl = hl;
    gbua_call_impl();
    return gbua_a;
}

static void unapi_wait(void)
{
    (void)unapi_call(TCPIP_WAIT, 0, 0, 0);
}

static unsigned char tcp_state(void)
{
    if (!tcp_handle || unapi_call(TCPIP_TCP_STATE,
            (unsigned int)tcp_handle << 8, 0, 0) != ERR_OK) return 0;
    return (unsigned char)(gbua_bc >> 8);
}

unsigned char gb_net_init(const unsigned char *cfg22)
{
    unsigned char slot, segment;
    (void)cfg22;                 /* UNAPI owns its network configuration. */
    if (unapi_ready) return 1;

    EXTBIO_ARG[0] = 'T'; EXTBIO_ARG[1] = 'C'; EXTBIO_ARG[2] = 'P';
    EXTBIO_ARG[3] = '/'; EXTBIO_ARG[4] = 'I'; EXTBIO_ARG[5] = 'P';
    EXTBIO_ARG[6] = 0;

    extbio_call(0, 0, 0x2222, 0);
    if (!(gbua_bc >> 8)) goto fail;

    extbio_call(1, 0, 0x2222, 0);
    slot = gbua_a;
    segment = (unsigned char)(gbua_bc >> 8);
    gbua_entry = gbua_hl;
    if (gbua_entry >= 0xC000U) {
        gbua_kind = UNAPI_DIRECT;
    } else {
        if (segment == 0xFF) goto fail; /* ROM-slot UNAPI is a later target. */
        extbio_call(0xFF, 0, 0x2222, 0);
        if (!gbua_hl) goto fail;
        gbua_helper = gbua_hl;
        gbua_iy = (unsigned int)segment | ((unsigned int)slot << 8);
        gbua_kind = UNAPI_MAPPED;
    }

    if (unapi_call(0, 0, 0, 0) != ERR_OK || gbua_de < 0x0100U)
        goto fail;
    if (unapi_call(TCPIP_GET_CAPAB, 0x0100, 0, 0) != ERR_OK ||
        !(gbua_hl & 0x0008U)) goto fail;       /* active TCP required */

    unapi_ready = 1;
    recv_status = GB_NET_RX_IDLE;
    return 1;
fail:
    gbua_kind = 0;
    recv_status = GB_NET_RX_ERROR;
    return 0;
}

unsigned char gb_net_open(void)
{
    if (!unapi_ready) return 0;
    if (tcp_handle) gb_net_close();
    recv_status = GB_NET_RX_IDLE;
    return 1;
}

unsigned char gb_net_connect(const unsigned char *ip, unsigned int port)
{
    unsigned int waits = UNAPI_CONNECT_WAITS;
    unsigned char state;
    if (!unapi_ready || tcp_handle) return 0;

    GBNET_BUF[0] = ip[0]; GBNET_BUF[1] = ip[1];
    GBNET_BUF[2] = ip[2]; GBNET_BUF[3] = ip[3];
    GBNET_BUF[4] = (unsigned char)port;
    GBNET_BUF[5] = (unsigned char)(port >> 8);
    GBNET_BUF[6] = 0xFF; GBNET_BUF[7] = 0xFF; /* random local port */
    GBNET_BUF[8] = 0; GBNET_BUF[9] = 0;       /* implementation timeout */
    GBNET_BUF[10] = 0;                         /* active, transient, no TLS */
    GBNET_BUF[11] = 0; GBNET_BUF[12] = 0;
    if (unapi_call(TCPIP_TCP_OPEN, 0, 0, 0x2200) != ERR_OK) goto fail;
    tcp_handle = (unsigned char)(gbua_bc >> 8);
    if (!tcp_handle) goto fail;

    while (waits--) {
        state = tcp_state();
        if (state == TCP_ESTABLISHED || state == TCP_CLOSE_WAIT) {
            recv_status = GB_NET_RX_IDLE;
            return 1;
        }
        if (state != TCP_SYN_SENT && state != TCP_SYN_RECEIVED) break;
        unapi_wait();
    }
    (void)unapi_call(TCPIP_TCP_ABORT, (unsigned int)tcp_handle << 8, 0, 0);
fail:
    tcp_handle = 0;
    recv_status = GB_NET_RX_ERROR;
    return 0;
}

unsigned char gb_net_send(const unsigned char *buf, unsigned int len)
{
    unsigned int done = 0;
    if (!tcp_handle || len > GBNET_MAXIO) return 0;
    while (done < len) {
        unsigned int i, chunk = len - done;
        unsigned int waits = UNAPI_BUFFER_WAITS;
        if (chunk > UNAPI_SEND_CHUNK) chunk = UNAPI_SEND_CHUNK;
        for (i = 0; i < chunk; i++) GBNET_BUF[i] = buf[done + i];
        for (;;) {
            unsigned char err = unapi_call(TCPIP_TCP_SEND,
                ((unsigned int)tcp_handle << 8) | 1U, 0x2200, chunk);
            if (err == ERR_OK) break;
            if (err != ERR_BUFFER || !waits--) return 0;
            unapi_wait();
        }
        done += chunk;
    }
    return 1;
}

unsigned int gb_net_recv(unsigned char *buf, unsigned int maxlen)
{
    unsigned int i, n;
    unsigned char err, state;
    if (!tcp_handle) { recv_status = GB_NET_RX_CLOSED; return 0; }
    if (maxlen > GBNET_MAXIO) maxlen = GBNET_MAXIO;
    if (!maxlen) { recv_status = GB_NET_RX_IDLE; return 0; }

    err = unapi_call(TCPIP_TCP_RCV, (unsigned int)tcp_handle << 8,
                     0x2200, maxlen);
    if (err != ERR_OK && err != ERR_NO_DATA) {
        recv_status = err == ERR_NO_CONN ? GB_NET_RX_CLOSED : GB_NET_RX_ERROR;
        if (recv_status == GB_NET_RX_CLOSED) tcp_handle = 0;
        return 0;
    }
    if (err == ERR_OK) {
        n = gbua_bc;
        if (n > maxlen) n = maxlen;
        for (i = 0; i < n; i++) buf[i] = GBNET_BUF[i];
        if (n) { recv_status = GB_NET_RX_DATA; return n; }
    }

    state = tcp_state();
    if (state == TCP_ESTABLISHED || state == TCP_SYN_SENT ||
        state == TCP_SYN_RECEIVED) recv_status = GB_NET_RX_IDLE;
    else {
        recv_status = GB_NET_RX_CLOSED;
        (void)unapi_call(TCPIP_TCP_ABORT,
                         (unsigned int)tcp_handle << 8, 0, 0);
        tcp_handle = 0;
    }
    return 0;
}

unsigned char gb_net_recv_status(void) { return recv_status; }

void gb_net_close(void)
{
    if (tcp_handle)
        (void)unapi_call(TCPIP_TCP_ABORT, (unsigned int)tcp_handle << 8, 0, 0);
    tcp_handle = 0;
    recv_status = GB_NET_RX_CLOSED;
}

unsigned int gb_net_rxavail(void)
{
    if (!tcp_handle || unapi_call(TCPIP_TCP_STATE,
            (unsigned int)tcp_handle << 8, 0, 0) != ERR_OK) return 0;
    return gbua_hl;
}

unsigned char gb_net_connected(void)
{
    unsigned char state = tcp_state();
    return (unsigned char)(state == TCP_ESTABLISHED || state == TCP_CLOSE_WAIT);
}

unsigned char gb_net_resolve(const char *host, unsigned char *ip4)
{
    unsigned int i = 0, waits = UNAPI_DNS_WAITS;
    if (!unapi_ready) return 0;
    while (host[i] && i < 255U) { GBNET_BUF[i] = (unsigned char)host[i]; i++; }
    if (host[i]) return 0;
    GBNET_BUF[i] = 0;
    if (unapi_call(TCPIP_DNS_Q, 0, 0, 0x2200) != ERR_OK) return 0;
    while (waits--) {
        if (unapi_call(TCPIP_DNS_S, 0, 0, 0) != ERR_OK) return 0;
        if ((unsigned char)(gbua_bc >> 8) == 2) {
            ip4[0] = (unsigned char)gbua_hl;
            ip4[1] = (unsigned char)(gbua_hl >> 8);
            ip4[2] = (unsigned char)gbua_de;
            ip4[3] = (unsigned char)(gbua_de >> 8);
            return 1;
        }
        if ((unsigned char)(gbua_bc >> 8) != 1) return 0;
        unapi_wait();
    }
    return 0;
}
