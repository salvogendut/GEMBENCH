/* TIMESYNC.APP - background PCW desktop NTP sync over PerryNet.
 *
 * Launched by the desktop when GEOBENCH.CFG has TIMESERVER=x.x.x.x. It registers
 * a zero-sized legacy window so the WM gives it an app page, performs a bounded
 * per-frame PerryNet UDP/NTP exchange, sets the software clock, then detaches.
 */
#include "gb.h"

#define KCFG_TEXT ((const char *)0x1000)
#define KCFG_LEN  (*(volatile unsigned int *)0x1200)

#define PN_END             0xC0
#define PN_ESC             0xDB
#define PN_ESC_END         0xDC
#define PN_ESC_ESC         0xDD
#define PN_VERSION         0x01
#define PN_MAX_PAYLOAD     512
#define PN_FRAME_MAX       520

#define PN_OP_HELLO        0x01
#define PN_OP_WIFI_CONNECT 0x12
#define PN_OP_UDP_OPEN     0x40
#define PN_OP_UDP_CLOSE    0x41
#define PN_OP_UDP_SEND     0x42
#define PN_OP_ACK          0x80
#define PN_OP_EVENT        0x81
#define PN_OP_UDP_DATA     0x83

#define PN_STATUS_OK       0x00
#define PN_EVT_UDP_ERROR   0x20

#define BYTE_BUDGET        96
#define ACK_TIMEOUT        25
#define NTP_TIMEOUT        250

#define WM_NWIN            (*(volatile unsigned char *)0x1350)
#define WM_FOCUS           (*(volatile unsigned char *)0x1351)
#define WM_TABLE           ((volatile unsigned char *)0x1352)
#define WM_ESZ             25
#define WM_FR_FLAGS        13
#define WM_Z               ((volatile unsigned char *)0x141A)
#define WM_FPREV           (*(volatile unsigned char *)0x1422)
#define APP_NPAGES         (*(volatile unsigned char *)0x1437)
#define APP_PAGES          ((volatile unsigned char *)0x1438)
#define APP_BUSY           ((volatile unsigned char *)0x1440)

enum {
    TS_START = 0,
    TS_WAIT_HELLO,
    TS_WAIT_WIFI,
    TS_WAIT_UDP_OPEN,
    TS_WAIT_SEND,
    TS_WAIT_NTP
};

static volatile unsigned char ser_io;
static volatile unsigned char soft_hour, soft_min, soft_sec;
static unsigned char server_ip[4];
static unsigned char tz_hours, tz_neg;
static unsigned char pn_seq, pn_udp_channel, wait_seq, state;
static unsigned int wait_frames, last_ack_len;
static unsigned char pn_frame[PN_FRAME_MAX];
static unsigned int pn_in_len;
static unsigned char pn_in_started, pn_in_esc, pn_in_overflow;
static unsigned char ntp[48];
static unsigned char udp_payload[54];

static void ser_in_data(void) __naked
{ __asm
    in a,(0xE0)
    ld (_ser_io),a
    ret
__endasm; }
static void ser_out_data(void) __naked
{ __asm
    ld a,(_ser_io)
    out (0xE0),a
    ret
__endasm; }
static void ser_in_status(void) __naked
{ __asm
    xor a
    out (0xE1),a
    in a,(0xE1)
    ld (_ser_io),a
    ret
__endasm; }
static void ser_out_ctrl(void) __naked
{ __asm
    ld a,(_ser_io)
    out (0xE1),a
    ret
__endasm; }
static void pit_out_tx(void) __naked
{ __asm
    ld a,(_ser_io)
    out (0xE4),a
    ret
__endasm; }
static void pit_out_rx(void) __naked
{ __asm
    ld a,(_ser_io)
    out (0xE5),a
    ret
__endasm; }
static void pit_out_ctrl(void) __naked
{ __asm
    ld a,(_ser_io)
    out (0xE7),a
    ret
__endasm; }

static void soft_poke(void) __naked
{ __asm
    ld   a, (_soft_hour)
    ld   b, a
    ld   a, (_soft_min)
    ld   c, a
    ld   a, (_soft_sec)
    ld   d, a
    call 0x802D
    ret
__endasm; }

static void set_soft_time(unsigned char h, unsigned char m, unsigned char s)
{
    soft_hour = h; soft_min = m; soft_sec = s; soft_poke();
}

static void dart_wr(unsigned char reg, unsigned char val)
{
    ser_io = reg; ser_out_ctrl();
    ser_io = val; ser_out_ctrl();
}

static void serial_hw_init(void)
{
    ser_io = 0x36; pit_out_ctrl(); ser_io = 13; pit_out_tx(); ser_io = 0; pit_out_tx();
    ser_io = 0x76; pit_out_ctrl(); ser_io = 13; pit_out_rx(); ser_io = 0; pit_out_rx();
    ser_io = 0x18; ser_out_ctrl();
    dart_wr(4, 0x44);
    dart_wr(3, 0xC1);
    dart_wr(5, 0xEA);
}

static unsigned char serial_present(void)
{
    serial_hw_init();
    ser_in_status();
    return (unsigned char)(ser_io != 0x7F && ser_io != 0xFF);
}

static void serial_put(unsigned char b)
{
    do { ser_in_status(); } while (!(ser_io & 0x04));
    ser_io = b;
    ser_out_data();
}

static unsigned char serial_recv(unsigned char *b)
{
    ser_in_status();
    if (!(ser_io & 0x01)) return 0;
    ser_in_data();
    *b = ser_io;
    return 1;
}

static void serial_drain(void)
{
    unsigned char guard = 0, b;
    while (guard++ != 0xFF) {
        if (!serial_recv(&b)) break;
    }
}

static unsigned int pn_crc16(const unsigned char *data, unsigned int len)
{
    unsigned int crc = 0xFFFF;
    unsigned int i;
    unsigned char bit;
    for (i = 0; i < len; i++) {
        crc ^= (unsigned int)data[i] << 8;
        for (bit = 0; bit < 8; bit++)
            crc = (crc & 0x8000) ? (unsigned int)((crc << 1) ^ 0x1021)
                                 : (unsigned int)(crc << 1);
    }
    return crc;
}

static void pn_slip_put(unsigned char b)
{
    if (b == PN_END) {
        serial_put(PN_ESC);
        serial_put(PN_ESC_END);
    } else if (b == PN_ESC) {
        serial_put(PN_ESC);
        serial_put(PN_ESC_ESC);
    } else {
        serial_put(b);
    }
}

static unsigned char pn_tx(unsigned char op, unsigned char channel,
                           const unsigned char *payload, unsigned int len)
{
    unsigned int i, crc, pos = 0;
    unsigned char seq = ++pn_seq;
    if (len > PN_MAX_PAYLOAD) return 0;
    pn_frame[pos++] = PN_VERSION;
    pn_frame[pos++] = op;
    pn_frame[pos++] = seq;
    pn_frame[pos++] = channel;
    pn_frame[pos++] = (unsigned char)(len & 0xFF);
    pn_frame[pos++] = (unsigned char)(len >> 8);
    for (i = 0; i < len; i++) pn_frame[pos++] = payload[i];
    crc = pn_crc16(pn_frame, pos);
    pn_frame[pos++] = (unsigned char)(crc & 0xFF);
    pn_frame[pos++] = (unsigned char)(crc >> 8);
    serial_put(PN_END);
    for (i = 0; i < pos; i++) pn_slip_put(pn_frame[i]);
    serial_put(PN_END);
    return seq;
}

static unsigned char pn_finish_frame(unsigned char *op, unsigned char *seq,
                                     unsigned char *channel, unsigned int *len)
{
    unsigned int payload_len, total, expected_crc, actual_crc;
    if (pn_in_overflow || pn_in_len < 8) return 0;
    if (pn_frame[0] != PN_VERSION) return 0;
    payload_len = (unsigned int)pn_frame[4] | ((unsigned int)pn_frame[5] << 8);
    total = 6 + payload_len + 2;
    if (payload_len > PN_MAX_PAYLOAD || total != pn_in_len) return 0;
    expected_crc = (unsigned int)pn_frame[total - 2] | ((unsigned int)pn_frame[total - 1] << 8);
    actual_crc = pn_crc16(pn_frame, (unsigned int)(total - 2));
    if (expected_crc != actual_crc) return 0;
    *op = pn_frame[1];
    *seq = pn_frame[2];
    *channel = pn_frame[3];
    *len = payload_len;
    return 1;
}

static unsigned char pn_read_frame(unsigned char *op, unsigned char *seq,
                                   unsigned char *channel, unsigned int *len)
{
    unsigned char b;
    unsigned int budget = BYTE_BUDGET;
    while (budget--) {
        if (!serial_recv(&b)) break;
        if (b == PN_END) {
            if (pn_in_started && pn_in_len) {
                if (pn_finish_frame(op, seq, channel, len)) {
                    pn_in_len = 0;
                    pn_in_overflow = 0;
                    pn_in_esc = 0;
                    return 1;
                }
            }
            pn_in_started = 1;
            pn_in_len = 0;
            pn_in_esc = 0;
            pn_in_overflow = 0;
            continue;
        }
        if (!pn_in_started) pn_in_started = 1;
        if (b == PN_ESC) {
            pn_in_esc = 1;
            continue;
        }
        if (pn_in_esc) {
            if (b == PN_ESC_END) b = PN_END;
            else if (b == PN_ESC_ESC) b = PN_ESC;
            else { pn_in_esc = 0; continue; }
            pn_in_esc = 0;
        }
        if (pn_in_len < PN_FRAME_MAX) pn_frame[pn_in_len++] = b;
        else pn_in_overflow = 1;
    }
    return 0;
}

static unsigned char ack_step(void)
{
    unsigned char op, seq, channel, status;
    unsigned int len;
    if (pn_read_frame(&op, &seq, &channel, &len)) {
        if (op == PN_OP_ACK && seq == wait_seq) {
            if (!len) return 2;
            status = pn_frame[6];
            if (status != PN_STATUS_OK) return 2;
            last_ack_len = len - 1;
            return 1;
        }
        if (op == PN_OP_EVENT && channel == pn_udp_channel && len && pn_frame[6] == PN_EVT_UDP_ERROR)
            return 2;
    }
    if (++wait_frames > ACK_TIMEOUT) return 2;
    return 0;
}

static unsigned int cfg_val(const char *key, unsigned char klen)
{
    const char *t = KCFG_TEXT;
    unsigned int len = KCFG_LEN, i;
    unsigned char j;
    for (i = 0; i + klen <= len; i++) {
        if (i && t[i - 1] != '\r' && t[i - 1] != '\n') continue;
        for (j = 0; j < klen; j++) if (t[i + j] != key[j]) break;
        if (j == klen) return i + klen;
    }
    return len;
}

static unsigned char parse_num(unsigned int *p, unsigned char *out)
{
    const char *t = KCFG_TEXT;
    unsigned int len = KCFG_LEN;
    unsigned int v = 0;
    unsigned char any = 0;
    while (*p < len && t[*p] >= '0' && t[*p] <= '9') {
        v = (unsigned int)(v * 10 + (unsigned int)(t[*p] - '0'));
        if (v > 255) return 0;
        (*p)++;
        any = 1;
    }
    *out = (unsigned char)v;
    return any;
}

static unsigned char cfg_read(void)
{
    const char *t = KCFG_TEXT;
    unsigned int len = KCFG_LEN, p;
    unsigned char i;
    p = cfg_val("TIMESERVER=", 11);
    if (p >= len) return 0;
    for (i = 0; i < 4; i++) {
        if (!parse_num(&p, &server_ip[i])) return 0;
        if (i < 3) {
            if (p >= len || t[p] != '.') return 0;
            p++;
        }
    }
    tz_hours = 0;
    tz_neg = 0;
    p = cfg_val("TIMEZONE=", 9);
    if (p < len) {
        if (t[p] == '-') { tz_neg = 1; p++; }
        else if (t[p] == '+') p++;
        (void)parse_num(&p, &tz_hours);
        if (tz_hours > 14) tz_hours = 14;
    }
    return 1;
}

static void apply_ntp_time(const unsigned char *buf)
{
    unsigned long sec, day;
    unsigned char h, m, s, n;
    sec = ((unsigned long)buf[40] << 24) |
          ((unsigned long)buf[41] << 16) |
          ((unsigned long)buf[42] << 8) |
          (unsigned long)buf[43];
    sec -= 2208988800UL;
    day = sec % 86400UL;
    h = (unsigned char)(day / 3600UL);
    day %= 3600UL;
    m = (unsigned char)(day / 60UL);
    s = (unsigned char)(day % 60UL);
    for (n = 0; n < tz_hours; n++) {
        if (tz_neg) h = h ? (unsigned char)(h - 1) : 23;
        else { h++; if (h == 24) h = 0; }
    }
    set_soft_time(h, m, s);
}

static void close_now(void)
{
    unsigned char slot, page, n, i, j;
    volatile unsigned char *entry;
    if (pn_udp_channel)
        (void)pn_tx(PN_OP_UDP_CLOSE, pn_udp_channel, 0, 0);
    pn_udp_channel = 0;

    /* This helper never paints, so detach without the normal full close repaint. */
    slot = WM_FOCUS;
    if (!slot) return;
    entry = WM_TABLE + (unsigned int)slot * WM_ESZ;
    page = entry[0];
    entry[WM_FR_FLAGS] = 0;

    n = WM_NWIN;
    for (i = 0, j = 0; i < n; i++) {
        if (WM_Z[i] != slot) WM_Z[j++] = WM_Z[i];
    }
    if (!j) {
        WM_Z[0] = 0;
        j = 1;
    }
    WM_NWIN = j;
    WM_FOCUS = WM_Z[j - 1];
    WM_FPREV = 0xFF;

    n = APP_NPAGES;
    if (n > 8) n = 8;
    for (i = 0; i < n; i++) {
        if (APP_PAGES[i] == page) {
            APP_BUSY[i] = 0;
            break;
        }
    }
}

static void send_wait(unsigned char op, unsigned char channel,
                      const unsigned char *payload, unsigned int len,
                      unsigned char next)
{
    wait_seq = pn_tx(op, channel, payload, len);
    if (!wait_seq) { close_now(); return; }
    wait_frames = 0;
    last_ack_len = 0;
    state = next;
}

static void ts_frame(void)
{
    unsigned char r, op, seq, channel, payload[6];
    unsigned int len;
    if (state == TS_START) {
        if (!cfg_read() || !serial_present()) { close_now(); return; }
        serial_drain();
        pn_seq = 0;
        pn_udp_channel = 0;
        pn_in_len = 0;
        pn_in_started = pn_in_esc = pn_in_overflow = 0;
        send_wait(PN_OP_HELLO, 0, 0, 0, TS_WAIT_HELLO);
        return;
    }
    if (state == TS_WAIT_HELLO) {
        r = ack_step();
        if (r == 1) send_wait(PN_OP_WIFI_CONNECT, 0, 0, 0, TS_WAIT_WIFI);
        else if (r == 2) close_now();
        return;
    }
    if (state == TS_WAIT_WIFI) {
        r = ack_step();
        if (r == 1) {
            payload[0] = 0; payload[1] = 0;
            send_wait(PN_OP_UDP_OPEN, 0, payload, 2, TS_WAIT_UDP_OPEN);
        } else if (r) close_now();
        return;
    }
    if (state == TS_WAIT_UDP_OPEN) {
        r = ack_step();
        if (r == 1 && last_ack_len >= 3) {
            pn_udp_channel = pn_frame[7];
            udp_payload[0] = server_ip[0]; udp_payload[1] = server_ip[1];
            udp_payload[2] = server_ip[2]; udp_payload[3] = server_ip[3];
            udp_payload[4] = 123; udp_payload[5] = 0;
            for (len = 0; len < sizeof(ntp); len++) ntp[len] = 0;
            ntp[0] = 0x1B;
            for (len = 0; len < sizeof(ntp); len++) udp_payload[6 + len] = ntp[len];
            send_wait(PN_OP_UDP_SEND, pn_udp_channel, udp_payload, sizeof(udp_payload), TS_WAIT_SEND);
        } else if (r) close_now();
        return;
    }
    if (state == TS_WAIT_SEND) {
        r = ack_step();
        if (r == 1) { wait_frames = 0; state = TS_WAIT_NTP; }
        else if (r == 2) close_now();
        return;
    }
    if (state == TS_WAIT_NTP) {
        if (pn_read_frame(&op, &seq, &channel, &len)) {
            (void)seq;
            if (op == PN_OP_UDP_DATA && channel == pn_udp_channel && len >= 54) {
                apply_ntp_time(pn_frame + 12);
                close_now();
                return;
            }
            if (op == PN_OP_EVENT && channel == pn_udp_channel && len && pn_frame[6] == PN_EVT_UDP_ERROR) {
                close_now();
                return;
            }
        }
        if (++wait_frames > NTP_TIMEOUT) close_now();
        return;
    }
}

static void ts_paint(void) { }
static const gb_win_t tswin = { 0, 0, 0, 0, ts_frame, ts_paint, 0, 0 };

void main(void)
{
    state = TS_START;
    gb_wm_add(&tswin);
}
