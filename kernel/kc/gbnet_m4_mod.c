/* gbnet_m4_mod.c - M4-backed GBNET.MOD-compatible dispatcher (#259).
 *
 * This module preserves the app-facing gb_net_* ABI used by TELNET.APP, but
 * speaks Duke's M4 command protocol instead of the W5100/Net4CPC register bus.
 * Command IDs and packet shapes are anchored in /var/home/salvogendut/Dev/m4rom:
 * m4cmds.i plus M4ROM.s send_command/send_command2 and sock_info layout.
 */

/* ---- GEOBENCH network transfer area (fixed low RAM) --------------------- */
#define GBNET_OP   (*(volatile unsigned char *)0x1490)
#define GBNET_RES  (*(volatile unsigned char *)0x1491)
#define GBNET_RES2 (*(volatile unsigned int  *)0x1492)
#define GBNET_IP   ((unsigned char *)0x1494)
#define GBNET_PORT (*(volatile unsigned int  *)0x1498)
#define GBNET_LEN  (*(volatile unsigned int  *)0x149A)
#define GBNET_SOCK (*(volatile unsigned char *)0x149C)
#define GBNET_STATE (*(volatile unsigned char *)0x149D)
#define GBNET_RX   (*(volatile unsigned int  *)0x149E)
#define GBNET_BUF  ((unsigned char *)0x2200)

#define OP_INIT      1
#define OP_OPEN      2
#define OP_CONNECT   3
#define OP_SEND      4
#define OP_RECV      5
#define OP_CLOSE     6
#define OP_RXAVAIL   7
#define OP_CONNECTED 8
#define OP_RESOLVE   9

/* ---- M4 command protocol ------------------------------------------------- */
#define M4C_NETSOCKET  0x4331
#define M4C_NETCONNECT 0x4332
#define M4C_NETCLOSE   0x4333
#define M4C_NETSEND    0x4334
#define M4C_NETRECV    0x4335
#define M4C_NETHOSTIP  0x4336

#define M4_STATUS_IDLE       0
#define M4_STATUS_CONNECTING 1
#define M4_STATUS_SENDING    2
#define M4_STATUS_CLOSED     3
#define M4_STATUS_DNS_BUSY   5

/* Keep one-packet commands below M4ROM's one-byte packet-size ceiling. */
#define M4_MAX_IO 240U

volatile unsigned char m4_packet[256];
volatile unsigned char m4_resp[256];
volatile unsigned char m4_sock[16];
volatile unsigned char m4_sock_slot;

void m4_begin(void) __naked
{
    __asm
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        push    iy
        di
        ld      bc,#0x7F85
        out     (c),c
        ld      bc,#0xDF00
        ld      a,#6
        out     (c),a

        ld      hl,#_m4_packet
        ld      a,(hl)
        inc     a
        ld      bc,#0xFE00
00001$:
        inc     b
        outi
        dec     a
        jr      nz,00001$

        ld      bc,#0xFC00
        out     (c),c

        ld      hl,#0xE800
        ld      de,#_m4_resp
        ld      bc,#0x0100
        ldir

        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret
    __endasm;
}

void m4_finish(void) __naked
{
    __asm
        push    af
        push    bc
        ld      bc,#0xDF00
        ld      a,#7
        out     (c),a
        pop     bc
        pop     af
        ei
        ret
    __endasm;
}

void m4_copy_sock_live(void) __naked
{
    __asm
        push    af
        push    bc
        push    de
        push    hl

        ld      a,(_m4_sock_slot)
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        ld      h,#0xFE
        ld      de,#_m4_sock
        ld      bc,#16
        ldir

        pop     hl
        pop     de
        pop     bc
        pop     af
        ret
    __endasm;
}

static void pkt(unsigned int cmd, unsigned char size)
{
    m4_packet[0] = size;
    m4_packet[1] = (unsigned char)(cmd & 0xFF);
    m4_packet[2] = (unsigned char)(cmd >> 8);
}

static void copy_sock(unsigned char slot)
{
    m4_sock_slot = slot;
    m4_copy_sock_live();
    GBNET_STATE = m4_sock[0];
    GBNET_RX = (unsigned int)m4_sock[2] | ((unsigned int)m4_sock[3] << 8);
}

static unsigned char socket_alive(void)
{
    unsigned char s = GBNET_STATE;
    if (!GBNET_SOCK) return 0;
    return (s != M4_STATUS_CLOSED && s < 240) ? 1 : 0;
}

static unsigned char wait_socket_ready_live(unsigned char slot, unsigned char busy_status)
{
    unsigned char outer = 20;
    do {
        unsigned int spins = 60000U;
        do {
            copy_sock(slot);
            if (m4_sock[0] != busy_status)
                return m4_sock[0];
        } while (--spins);
    } while (--outer);
    return 255;
}

static unsigned char net_open_m4(void)
{
    pkt(M4C_NETSOCKET, 5);       /* cmd(2), domain, type, protocol */
    m4_packet[3] = 0;
    m4_packet[4] = 0;
    m4_packet[5] = 6;            /* TCP */
    m4_begin();
    if (m4_resp[3] == 255) { m4_finish(); return 0; }
    GBNET_SOCK = m4_resp[3];
    copy_sock(GBNET_SOCK);
    m4_finish();
    return 1;
}

static unsigned char net_connect_m4(const unsigned char *ip, unsigned int port)
{
    unsigned char s;
    if (!GBNET_SOCK) return 0;
    pkt(M4C_NETCONNECT, 9);      /* cmd(2), socket, ip(4), port(2) */
    m4_packet[3] = GBNET_SOCK;
    m4_packet[4] = ip[0];
    m4_packet[5] = ip[1];
    m4_packet[6] = ip[2];
    m4_packet[7] = ip[3];
    m4_packet[8] = (unsigned char)(port & 0xFF);
    m4_packet[9] = (unsigned char)(port >> 8);
    m4_sock_slot = GBNET_SOCK;
    m4_begin();
    if (m4_resp[3] == 255) { m4_finish(); return 0; }
    s = wait_socket_ready_live(GBNET_SOCK, M4_STATUS_CONNECTING);
    m4_finish();
    return (s == M4_STATUS_IDLE) ? 1 : 0;
}

static unsigned char net_send_m4(const unsigned char *buf, unsigned int len)
{
    unsigned int i;
    unsigned char s;
    if (!GBNET_SOCK || len > M4_MAX_IO) return 0;
    pkt(M4C_NETSEND, (unsigned char)(len + 5));  /* cmd, socket, len, data */
    m4_packet[3] = GBNET_SOCK;
    m4_packet[4] = (unsigned char)(len & 0xFF);
    m4_packet[5] = (unsigned char)(len >> 8);
    for (i = 0; i < len; i++)
        m4_packet[6 + i] = buf[i];
    m4_sock_slot = GBNET_SOCK;
    m4_begin();
    s = wait_socket_ready_live(GBNET_SOCK, M4_STATUS_SENDING);
    m4_finish();
    return (m4_resp[3] == 0 && s == M4_STATUS_IDLE) ? 1 : 0;
}

static unsigned int net_recv_m4(unsigned char *buf, unsigned int maxlen)
{
    unsigned int want, actual, i;
    if (!GBNET_SOCK) return 0;
    if (GBNET_STATE == M4_STATUS_CLOSED || GBNET_STATE >= 240) return 0;
    want = maxlen;
    if (want > M4_MAX_IO) want = M4_MAX_IO;
    pkt(M4C_NETRECV, 5);        /* cmd(2), socket, wanted-size(2) */
    m4_packet[3] = GBNET_SOCK;
    m4_packet[4] = (unsigned char)(want & 0xFF);
    m4_packet[5] = (unsigned char)(want >> 8);
    m4_sock_slot = GBNET_SOCK;
    m4_begin();
    copy_sock(GBNET_SOCK);
    if (m4_resp[3] != 0) { m4_finish(); return 0; }
    actual = (unsigned int)m4_resp[4] | ((unsigned int)m4_resp[5] << 8);
    if (actual > maxlen) actual = maxlen;
    if (actual > M4_MAX_IO) actual = M4_MAX_IO;
    for (i = 0; i < actual; i++)
        buf[i] = m4_resp[6 + i];
    m4_finish();
    return actual;
}

static void net_close_m4(void)
{
    if (!GBNET_SOCK) return;
    pkt(M4C_NETCLOSE, 3);
    m4_packet[3] = GBNET_SOCK;
    m4_sock_slot = GBNET_SOCK;
    m4_begin();
    copy_sock(GBNET_SOCK);
    m4_finish();
    GBNET_SOCK = 0;
    GBNET_STATE = M4_STATUS_CLOSED;
    GBNET_RX = 0;
}

static unsigned int net_rxavail_m4(void)
{
    if (!GBNET_SOCK) return 0;
    if (GBNET_STATE == M4_STATUS_CLOSED || GBNET_STATE >= 240) return 0;
    return GBNET_RX;
}

static unsigned char net_resolve_m4(const char *host, unsigned char *ip4)
{
    unsigned int i = 0;
    unsigned char s;
    while (host[i] && i < M4_MAX_IO)
        i++;
    if (i == M4_MAX_IO) return 0;
    pkt(M4C_NETHOSTIP, (unsigned char)(i + 3));  /* cmd + host + NUL */
    for (i = 0; host[i]; i++)
        m4_packet[3 + i] = (unsigned char)host[i];
    m4_packet[3 + i] = 0;
    m4_sock_slot = 0;
    m4_begin();
    if (m4_resp[3] != 1) { m4_finish(); return 0; }
    s = wait_socket_ready_live(0, M4_STATUS_DNS_BUSY);
    if (s >= 240) { m4_finish(); return 0; }
    copy_sock(0);
    ip4[0] = m4_sock[4];
    ip4[1] = m4_sock[5];
    ip4[2] = m4_sock[6];
    ip4[3] = m4_sock[7];
    m4_finish();
    return 1;
}

void main(void)
{
    unsigned char op = GBNET_OP;
    if (op == OP_INIT) {
        GBNET_SOCK = 0;
        GBNET_STATE = M4_STATUS_CLOSED;
        GBNET_RX = 0;
        GBNET_RES = 1;          /* M4 owns TCP/IP configuration. */
    } else if (op == OP_OPEN) {
        GBNET_RES = net_open_m4();
    } else if (op == OP_CONNECT) {
        GBNET_RES = net_connect_m4(GBNET_IP, GBNET_PORT);
    } else if (op == OP_SEND) {
        GBNET_RES = net_send_m4(GBNET_BUF, GBNET_LEN);
    } else if (op == OP_RECV) {
        GBNET_RES2 = net_recv_m4(GBNET_BUF, GBNET_LEN);
        GBNET_RES = 1;
    } else if (op == OP_CLOSE) {
        net_close_m4();
        GBNET_RES = 1;
    } else if (op == OP_RXAVAIL) {
        GBNET_RES2 = net_rxavail_m4();
        GBNET_RES = 1;
    } else if (op == OP_CONNECTED) {
        GBNET_RES = socket_alive();
    } else if (op == OP_RESOLVE) {
        GBNET_RES = net_resolve_m4((const char *)GBNET_BUF, GBNET_IP);
    } else {
        GBNET_RES = 0;
    }
}
