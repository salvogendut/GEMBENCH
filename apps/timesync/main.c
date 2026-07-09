/* TIMESYNC.APP - background PCW desktop time sync over PerryNet.
 *
 * Launched by the desktop when GEOBENCH.CFG has TIMESERVER=x.x.x.x. It registers
 * a small status popup, asks PerryNet for the firmware-maintained UTC clock,
 * sets the software clock, then detaches.
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
#define PN_OP_WIFI_STATUS  0x14
#define PN_OP_TIME_GET     0x60
#define PN_OP_ACK          0x80
#define PN_OP_EVENT        0x81

#define PN_STATUS_OK       0x00
#define PN_STATUS_BAD_OPCODE 0x02
#define PN_STATUS_BAD_LENGTH 0x03
#define PN_STATUS_BUSY     0x0A
#define PN_EVT_WIFI_UP     0x02
#define PN_EVT_WIFI_DOWN   0x03

#define ACK_SPINS          60000
#define ACK_TIMEOUT        180
#define TIME_ATTEMPTS      60
#define TIME_RETRY_DELAY   50
#define TIME_MAX_FRAMES    4500
#define WIFI_POLL_DELAY    50

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
    TS_WIFI_READY,
    TS_WAIT_WIFI_STATUS,
    TS_WAIT_TIME,
    TS_TIME_DELAY,
    TS_DONE
};

#define POP_W 34
#define POP_H 42
#define POP_X ((GB_COLS - POP_W) / 2)
#define POP_Y 86
#define POP_TEXT_X (POP_X + 4)
#define POP_STATUS_Y (POP_Y + 25)

static volatile unsigned char ser_io;
static volatile unsigned char soft_hour, soft_min, soft_sec;
static unsigned char tz_hours, tz_neg;
static unsigned char pn_seq, wait_seq, state, pn_wifi_up, wifi_connect_sent;
static unsigned char ack_status, ack_cached;
static unsigned char popup_drawn, status_dirty, close_delay, retry_delay, wifi_errors, time_attempts;
static unsigned int wait_frames, wifi_wait_frames, last_ack_len, life_frames;
static const char *status_text;
static unsigned char pn_frame[PN_FRAME_MAX];
static unsigned int pn_in_len;
static unsigned char pn_in_started, pn_in_esc, pn_in_overflow;

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

static void status_set(const char *s)
{
    status_text = s;
    status_dirty = 1;
}

static void draw_status(void)
{
    gb_fill((unsigned char)(POP_X + 2), POP_STATUS_Y, (unsigned char)(POP_W - 4), 8, 1);
    gb_textbw(POP_TEXT_X, POP_STATUS_Y, status_text);
}

static void ts_paint(void)
{
    gb_fill(POP_X, POP_Y, POP_W, POP_H, 1);
    gb_frame(POP_X, POP_Y, POP_W, POP_H, 2);
    gb_textbw(POP_TEXT_X, (unsigned char)(POP_Y + 7), "SYNCING CLOCK");
    gb_fill((unsigned char)(POP_X + 2), (unsigned char)(POP_Y + 19),
            (unsigned char)(POP_W - 4), 1, 2);
    draw_status();
    popup_drawn = 1;
    status_dirty = 0;
}

static void paint_dirty_status(void)
{
    if (!popup_drawn || !status_dirty) return;
    gb_curhide();
    draw_status();
    gb_curshow();
    status_dirty = 0;
}

static void finish(const char *s)
{
    status_set(s);
    close_delay = 150;
    state = TS_DONE;
}

static void dart_wr(unsigned char reg, unsigned char val)
{
    ser_io = reg; ser_out_ctrl();
    ser_io = val; ser_out_ctrl();
}

static void serial_hw_init(void)
{
    /* Direct-boot GEOBENCH cannot rely on CP/M SETSIO. Program CPS8256
     * channel A for 9600 8N1: 2MHz PIT / 16 / 13 = 9615 baud. */
    ser_io = 0x36; pit_out_ctrl(); ser_io = 13; pit_out_tx(); ser_io = 0; pit_out_tx();
    ser_io = 0x76; pit_out_ctrl(); ser_io = 13; pit_out_rx(); ser_io = 0; pit_out_rx();
    ser_io = 0x18; ser_out_ctrl();
    dart_wr(4, 0x44);
    dart_wr(3, 0xC1);
    dart_wr(5, 0x68);           /* TX enable + 8-bit TX, RTS/DTR inactive */
    dart_wr(1, 0x00);
}

static unsigned char serial_present(void)
{
    serial_hw_init();
    ser_in_status();
    return (unsigned char)(ser_io != 0x7F && ser_io != 0xFF);
}

static unsigned char serial_put(unsigned char b)
{
    unsigned int guard = 60000;
    while (guard--) {
        ser_in_status();
        if (ser_io & 0x04) {
            ser_io = b;
            ser_out_data();
            return 1;
        }
    }
    return 0;
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
    unsigned char b;
    unsigned int budget = 2048;
    unsigned int quiet = 60000;
    while (budget && quiet) {
        if (serial_recv(&b)) {
            budget--;
            quiet = 60000;
        } else {
            quiet--;
        }
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

static unsigned char pn_slip_put(unsigned char b)
{
    if (b == PN_END) {
        if (!serial_put(PN_ESC)) return 0;
        return serial_put(PN_ESC_END);
    } else if (b == PN_ESC) {
        if (!serial_put(PN_ESC)) return 0;
        return serial_put(PN_ESC_ESC);
    }
    return serial_put(b);
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
    if (!serial_put(PN_END)) return 0;
    for (i = 0; i < pos; i++) {
        if (!pn_slip_put(pn_frame[i])) return 0;
    }
    if (!serial_put(PN_END)) return 0;
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
                                   unsigned char *channel, unsigned int *len,
                                   unsigned int spins)
{
    unsigned char b;
    while (spins--) {
        if (!serial_recv(&b)) continue;
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

static unsigned char ack_poll(void)
{
    unsigned char op, seq, channel, status;
    unsigned int len;
    if (pn_read_frame(&op, &seq, &channel, &len, 1)) {
        if (op == PN_OP_ACK && seq == wait_seq) {
            if (!len) { ack_status = 0xFE; return 2; }
            status = pn_frame[6];
            ack_status = status;
            if (status != PN_STATUS_OK) return 2;
            last_ack_len = len - 1;
            return 1;
        }
        if (op == PN_OP_EVENT && channel == 0 && len) {
            if (pn_frame[6] == PN_EVT_WIFI_UP) pn_wifi_up = 1;
            else if (pn_frame[6] == PN_EVT_WIFI_DOWN) pn_wifi_up = 0;
        }
    }
    return 0;
}

static unsigned char ack_poll_spins(unsigned int spins)
{
    unsigned char r;
    while (spins--) {
        r = ack_poll();
        if (r) return r;
    }
    return 0;
}

static unsigned char ack_step(void)
{
    unsigned char r;
    if (ack_cached) {
        r = ack_cached;
        ack_cached = 0;
        return r;
    }
    r = ack_poll_spins(ACK_SPINS);
    if (r) return r;
    if (++wait_frames > ACK_TIMEOUT) { ack_status = 0xFF; return 2; }
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
    p = cfg_val("TIMESERVER=", 11);
    if (p >= len) return 0;
    if (t[p] == '\r' || t[p] == '\n') return 0;
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

static void apply_unix_time(unsigned long sec)
{
    unsigned long day;
    unsigned char h, m, s, n;
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

    /* Zero-sized background helper: detach without gb_wm_close(), whose repaint
     * path can run through the helper's bank after it has released its pages. */
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

    gb_wm_damage(POP_X, POP_Y, POP_W, POP_H);
    gb_restore_parent();

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
    if (!wait_seq) { finish("SERIAL TIMEOUT"); return; }
    wait_frames = 0;
    last_ack_len = 0;
    ack_status = 0xFF;
    ack_cached = ack_poll_spins(ACK_SPINS);
    state = next;
}

static void wifi_status_wait(void)
{
    status_set(wifi_connect_sent ? "WAITING FOR WIFI" : "CHECKING WIFI");
    send_wait(PN_OP_WIFI_STATUS, 0, 0, 0, TS_WAIT_WIFI_STATUS);
}

static void time_get_wait(void)
{
    if (!time_attempts) { finish("CLOCK NOT READY"); return; }
    time_attempts--;
    status_set("READING CLOCK");
    send_wait(PN_OP_TIME_GET, 0, 0, 0, TS_WAIT_TIME);
}

static void ts_frame(void)
{
    unsigned char r;
    paint_dirty_status();
    if (state == TS_DONE) {
        if (close_delay) close_delay--;
        else close_now();
        return;
    }
    if (++life_frames > TIME_MAX_FRAMES) {
        finish("CLOCK TIMEOUT");
        return;
    }
    if (state == TS_START) {
        if (!cfg_read()) { finish("NO TIME CONFIG"); return; }
        if (!serial_present()) { finish("NO PERRYNET"); return; }
        serial_drain();
        pn_seq = 0;
        pn_wifi_up = 0;
        wifi_connect_sent = 0;
        ack_cached = 0;
        retry_delay = 0;
        wifi_errors = 0;
        time_attempts = TIME_ATTEMPTS;
        life_frames = 0;
        wifi_wait_frames = 0;
        pn_in_len = 0;
        pn_in_started = pn_in_esc = pn_in_overflow = 0;
        status_set("CONTACT PERRYNET");
        send_wait(PN_OP_HELLO, 0, 0, 0, TS_WAIT_HELLO);
        return;
    }
    if (state == TS_WAIT_HELLO) {
        r = ack_step();
        if (r == 1) {
            wifi_errors = 0;
            time_get_wait();
        } else if (r == 2) {
            if (++wifi_errors > 8) finish("PERRYNET TIMEOUT");
            else {
                status_set("WAITING PERRYNET");
                send_wait(PN_OP_HELLO, 0, 0, 0, TS_WAIT_HELLO);
            }
        }
        return;
    }
    if (state == TS_WAIT_TIME) {
        r = ack_step();
        if (r == 1) {
            if (last_ack_len >= 5 && pn_frame[7]) {
                apply_unix_time(((unsigned long)pn_frame[8]) |
                                ((unsigned long)pn_frame[9] << 8) |
                                ((unsigned long)pn_frame[10] << 16) |
                                ((unsigned long)pn_frame[11] << 24));
                finish("CLOCK SYNCED");
            } else if (!wifi_connect_sent) {
                wifi_status_wait();
            } else {
                status_set("WAITING FOR TIME");
                retry_delay = TIME_RETRY_DELAY;
                state = TS_TIME_DELAY;
            }
        } else if (r == 2) {
            if (ack_status == PN_STATUS_BAD_OPCODE) { finish("NO TIME CMD"); return; }
            if (!wifi_connect_sent) wifi_status_wait();
            else {
                status_set("WAITING FOR TIME");
                retry_delay = TIME_RETRY_DELAY;
                state = TS_TIME_DELAY;
            }
        }
        return;
    }
    if (state == TS_TIME_DELAY) {
        if (retry_delay) retry_delay--;
        else time_get_wait();
        return;
    }
    if (state == TS_WAIT_WIFI) {
        r = ack_step();
        if (r == 1) {
            wifi_errors = 0;
            wifi_wait_frames = 0;
            state = TS_WIFI_READY;
            retry_delay = WIFI_POLL_DELAY;
        } else if (r) {
            if (++wifi_errors > 12) finish("WIFI TIMEOUT");
            else {
                state = TS_WIFI_READY;
                retry_delay = WIFI_POLL_DELAY;
            }
        }
        return;
    }
    if (state == TS_WIFI_READY) {
        if (pn_wifi_up) {
            wifi_connect_sent = 1;
            time_get_wait();
            return;
        }
        if (++wifi_wait_frames > 3000) { finish("WIFI TIMEOUT"); return; }
        if (retry_delay) { retry_delay--; return; }
        retry_delay = WIFI_POLL_DELAY;
        wifi_status_wait();
        return;
    }
    if (state == TS_WAIT_WIFI_STATUS) {
        r = ack_step();
        if (r == 1) {
            wifi_errors = 0;
            if (last_ack_len >= 2 && pn_frame[8]) {
                wifi_connect_sent = 1;
                time_get_wait();
            }
            else if (!wifi_connect_sent) {
                wifi_connect_sent = 1;
                status_set("STARTING WIFI");
                send_wait(PN_OP_WIFI_CONNECT, 0, 0, 0, TS_WAIT_WIFI);
            } else {
                state = TS_WIFI_READY;
            }
        } else if (r == 2) {
            if (++wifi_errors > 20) finish("WIFI TIMEOUT");
            else {
                state = TS_WIFI_READY;
                retry_delay = WIFI_POLL_DELAY;
            }
        }
        return;
    }
}

static const gb_win_t tswin = { 0, 8, GB_COLS, GB_LINES - 8, ts_frame, ts_paint, 0, 0 };

void main(void)
{
    state = TS_START;
    status_text = "STARTING";
    status_dirty = 0;
    popup_drawn = 0;
    life_frames = 0;
    gb_wm_add(&tswin);
    gb_wm_damage(POP_X, POP_Y, POP_W, POP_H);
    gb_restore_parent();
}
