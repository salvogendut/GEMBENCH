/* NETTEST.APP - small GEOBENCH network diagnostic (#261).
 *
 * Runs a fixed TCP probe through the public gb_net_* API:
 *   init -> DNS example.com -> open -> connect :80 -> HTTP GET -> recv.
 * It is intentionally simple so it can validate whichever backend the kernel
 * selects (Albireo/Net4CPC or M4 native) without Telnet UI/input noise.
 */
#include "gb.h"

#define DEF_X    8
#define DEF_Y    18
#define DEF_W    64
#define DEF_H    132
#define TITLE_H  14
#define NLINES   13
#define LINELEN  48

#define STEP_INIT    1
#define STEP_DNS     2
#define STEP_OPEN    3
#define STEP_CONNECT 4
#define STEP_SEND    5
#define STEP_RECV    6
#define STEP_DONE    7
#define STEP_FAIL    8

static char lines[NLINES][LINELEN];
static unsigned char step, wait, opened, drawn;
static unsigned char ip[4];
static unsigned char rxbuf[128];

static const char host[] = "example.com";
static const unsigned char netcfg[22] = {
    192,168,99,50,  255,255,255,0,  192,168,99,1,  8,8,8,8,
    0xDE,0xAD,0xBE,0xEF,0x26,0x1A
};
static const unsigned char request[] =
    "GET / HTTP/1.0\r\n"
    "Host: example.com\r\n"
    "User-Agent: GEOBENCH-NETTEST\r\n"
    "Connection: close\r\n\r\n";

static void copy(char *dst, const char *src)
{
    unsigned char i = 0;
    while (src[i] && i < LINELEN - 1) {
        dst[i] = src[i];
        i++;
    }
    dst[i] = 0;
}

static char *put_dec(char *p, unsigned int v)
{
    unsigned int d = 10000;
    unsigned char started = 0;
    while (d) {
        unsigned char n = 0;
        while (v >= d) { v -= d; n++; }
        if (n || started || d == 1) {
            *p++ = (char)('0' + n);
            started = 1;
        }
        d /= 10;
    }
    *p = 0;
    return p;
}

static char *put_ip_byte(char *p, unsigned char v)
{
    unsigned char hundreds = 0, tens = 0;
    while (v >= 100) { v -= 100; hundreds++; }
    while (v >= 10) { v -= 10; tens++; }
    if (hundreds) *p++ = (char)('0' + hundreds);
    if (hundreds || tens) *p++ = (char)('0' + tens);
    *p++ = (char)('0' + v);
    *p = 0;
    return p;
}

static void draw_line(unsigned char n)
{
    unsigned char x = gb_wm_x();
    unsigned char y = gb_wm_y();
    unsigned char w = gb_wm_w();
    unsigned char yy = (unsigned char)(y + TITLE_H + 2 + n * 8);
    gb_fill((unsigned char)(x + 2), yy, (unsigned char)(w - 4), 8, 0);
    gb_text((unsigned char)(x + 2), yy, lines[n]);
}

static void log_line(unsigned char n, const char *s)
{
    if (n >= NLINES) return;
    copy(lines[n], s);
    if (drawn) draw_line(n);
}

static void log_ip(unsigned char n, const char *prefix)
{
    char t[LINELEN];
    char *p = t;
    unsigned char i = 0;
    while (prefix[i] && p < t + LINELEN - 1) *p++ = prefix[i++];
    p = put_ip_byte(p, ip[0]); *p++ = '.';
    p = put_ip_byte(p, ip[1]); *p++ = '.';
    p = put_ip_byte(p, ip[2]); *p++ = '.';
    p = put_ip_byte(p, ip[3]);
    *p = 0;
    log_line(n, t);
}

static void log_count(unsigned char n, const char *prefix, unsigned int count)
{
    char t[LINELEN];
    char *p = t;
    unsigned char i = 0;
    while (prefix[i] && p < t + LINELEN - 1) *p++ = prefix[i++];
    put_dec(p, count);
    log_line(n, t);
}

static void log_rx(unsigned int n)
{
    char t[LINELEN];
    char *p = t;
    unsigned int i = 0;
    t[0] = 'r'; t[1] = 'x'; t[2] = ':'; t[3] = ' ';
    p = t + 4;
    while (i < n && p < t + LINELEN - 1) {
        unsigned char c = rxbuf[i++];
        if (c == 13 || c == 10) break;
        if (c < 32 || c > 126) c = '.';
        *p++ = (char)c;
    }
    *p = 0;
    log_line(10, t);
}

static void fail(const char *msg)
{
    if (opened) gb_net_close();
    opened = 0;
    log_line(11, msg);
    log_line(12, "click window to retry");
    step = STEP_FAIL;
}

static void reset_test(void)
{
    unsigned char i;
    for (i = 0; i < NLINES; i++) lines[i][0] = 0;
    opened = 0;
    wait = 0;
    log_line(0, "NETTEST: example.com:80");
    log_line(1, "Backend is selected by the kernel");
    log_line(2, "Starting...");
    step = STEP_INIT;
}

static void draw(void)
{
    unsigned char i;
    unsigned char x = gb_wm_x();
    unsigned char y = gb_wm_y();
    unsigned char w = gb_wm_w();
    unsigned char h = gb_wm_h();
    gb_fill((unsigned char)(x + 1), (unsigned char)(y + TITLE_H),
            (unsigned char)(w - 2), (unsigned char)(h - TITLE_H - 1), 0);
    drawn = 1;
    for (i = 0; i < NLINES; i++) draw_line(i);
}

static void tick(void)
{
    unsigned int n;
    if (step == STEP_INIT) {
        log_line(2, "init...");
        if (!gb_net_init(netcfg)) { fail("FAIL: gb_net_init"); return; }
        log_line(2, "init ok");
        step = STEP_DNS;
    } else if (step == STEP_DNS) {
        log_line(3, "dns example.com...");
        if (!gb_net_resolve(host, ip)) { fail("FAIL: DNS"); return; }
        log_ip(3, "dns ok: ");
        step = STEP_OPEN;
    } else if (step == STEP_OPEN) {
        log_line(4, "open socket...");
        if (!gb_net_open()) { fail("FAIL: open socket"); return; }
        opened = 1;
        log_line(4, "open ok");
        step = STEP_CONNECT;
    } else if (step == STEP_CONNECT) {
        log_line(5, "connect port 80...");
        if (!gb_net_connect(ip, 80)) { fail("FAIL: connect"); return; }
        log_line(5, "connect ok");
        step = STEP_SEND;
    } else if (step == STEP_SEND) {
        log_line(6, "send HTTP GET...");
        if (!gb_net_send(request, sizeof(request) - 1)) { fail("FAIL: send"); return; }
        log_line(6, "send ok");
        log_line(7, "recv...");
        wait = 0;
        step = STEP_RECV;
    } else if (step == STEP_RECV) {
        n = gb_net_recv(rxbuf, sizeof(rxbuf));
        if (n) {
            log_count(8, "recv bytes: ", n);
            log_rx(n);
            gb_net_close();
            opened = 0;
            log_line(11, "PASS");
            log_line(12, "click window to retry");
            step = STEP_DONE;
        } else if (!gb_net_connected()) {
            fail("FAIL: closed with no data");
        } else if (++wait > 180) {
            fail("FAIL: recv timeout");
        }
    }
}

static void drag(void)
{
    unsigned char x = gb_wm_x();
    unsigned char y = gb_wm_y();
    if (gb_drag_window(&x, &y, gb_wm_w(), gb_wm_h())) {
        gb_wm_setpos(x, y);
        gb_restore_parent();
    }
}

static void proc(void)
{
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  draw(); break;
        case GB_MSG_FRAME: tick(); break;
        case GB_MSG_CLICK:
            if (step == STEP_DONE || step == STEP_FAIL) reset_test();
            break;
        case GB_MSG_CLOSE:
            if (opened) gb_net_close();
            gb_wm_close();
            break;
        case GB_MSG_DRAG:  drag(); break;
    }
}

static const gb_mwin_t nw = {
    DEF_X, DEF_Y, DEF_W, DEF_H, 0, 0, proc, "Net Test", 0
};

void main(void)
{
    drawn = 0;
    reset_test();
    gb_wm_managed(&nw);
    gb_restore_parent();
}
