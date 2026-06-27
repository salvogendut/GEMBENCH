/* telnet - a windowed ANSI/VT terminal + telnet client for GEOBENCH (#238 Phase 1).
 *
 * A fullscreen terminal: a 53x25 character grid in Mode 1, fed by a TCP socket via
 * the gb_net_* API (the paged GBNET.MOD W5100 driver). It speaks enough of RFC 854
 * telnet (IAC option negotiation) to log into a server, and parses ANSI/VT100 escape
 * sequences (cursor positioning, erase, SGR) so a real BBS / shell renders.
 *
 * Ported from cpc-sdcc examples/telnet (main.c + ansi.c + screen.c), with the direct
 * Mode-2 screen writes replaced by a GEOBENCH character grid drawn through gb_textrev,
 * and the firmware keyboard replaced by gb_getkey. Monochrome for now (white on black);
 * SGR colour is parsed but not painted.
 *
 * Connect target is entered as "host:port" (dotted IP for now - DNS is a later phase).
 * ESC ends the session. Test against tools/netspike/server.py on 127.0.0.1:2323.
 */
#include "gb.h"

#define WM_FS (*(volatile unsigned char *)0x130A)

/* ---- terminal grid --------------------------------------------------------- */
#define COLS 53            /* 53 * 6px = 318px (<= 320) */
#define ROWS 25            /* 25 * 8px = 200px           */
#define SEG  48            /* gb_text caps a string at 48 chars (gtd_copy) -> two
                              segments per row; col 48 = 288px = byte 72 (4px-aligned) */

static unsigned char grid[ROWS * COLS];
static unsigned char dirty[ROWS];
static unsigned char cur_row, cur_col;
static unsigned char saved_row, saved_col;     /* ANSI SCP/RCP */

static unsigned int cell(unsigned char r, unsigned char c) { return (unsigned int)r * COLS + c; }
static void mark(unsigned char r) { if (r < ROWS) dirty[r] = 1; }
static void mark_all(void) { unsigned char r; for (r = 0; r < ROWS; r++) dirty[r] = 1; }

static void term_cls(void)
{
    unsigned int i;
    for (i = 0; i < ROWS * COLS; i++) grid[i] = ' ';
    mark_all();
    cur_row = 0; cur_col = 0;
}

static void scroll_up(void)
{
    unsigned int i;
    for (i = 0; i < (unsigned int)(ROWS - 1) * COLS; i++) grid[i] = grid[i + COLS];
    for (i = (unsigned int)(ROWS - 1) * COLS; i < ROWS * COLS; i++) grid[i] = ' ';
    mark_all();
}

static void newline(void)
{
    if (cur_row < ROWS - 1) cur_row++;
    else scroll_up();
}

/* ---- ANSI / VT100 parser (ported from ansi.c, retargeted to the grid) -------- */
#define A_IDLE   0
#define A_ESC    1
#define A_CSI    2      /* ESC [ ... accumulating params */
#define A_ESC2   3      /* ESC + intermediate: swallow one final byte */
#define A_OSC    4      /* ESC ] : skip to BEL / ST */
#define A_OSC_E  5
#define A_SS3    6      /* ESC O : application cursor key */
#define MAXP     6

static unsigned char a_state;
static unsigned char param[MAXP], nparam, have_digit;

static unsigned char gp(unsigned char i, unsigned char def)
{
    if (i >= nparam || param[i] == 0) return def;
    return param[i];
}

static void erase_cells(unsigned char r, unsigned char c0, unsigned char c1)
{
    unsigned char c;
    for (c = c0; c < c1; c++) grid[cell(r, c)] = ' ';
    mark(r);
}

static void do_ed(unsigned char n)          /* erase display */
{
    unsigned char r;
    if (n == 2) { term_cls(); return; }
    if (n == 0) {                           /* cursor -> end of screen */
        erase_cells(cur_row, cur_col, COLS);
        for (r = cur_row + 1; r < ROWS; r++) erase_cells(r, 0, COLS);
    } else if (n == 1) {                     /* start -> cursor */
        for (r = 0; r < cur_row; r++) erase_cells(r, 0, COLS);
        erase_cells(cur_row, 0, cur_col + 1);
    }
}

static void do_el(unsigned char n)          /* erase line */
{
    if (n == 2)      erase_cells(cur_row, 0, COLS);
    else if (n == 1) erase_cells(cur_row, 0, cur_col + 1);
    else             erase_cells(cur_row, cur_col, COLS);
}

static void ansi_dispatch(unsigned char cmd)
{
    unsigned char n, r, c;
    switch (cmd) {
    case 'A': n = gp(0, 1); cur_row = (cur_row >= n) ? cur_row - n : 0; break;
    case 'B': n = gp(0, 1); cur_row += n; if (cur_row >= ROWS) cur_row = ROWS - 1; break;
    case 'C': n = gp(0, 1); cur_col += n; if (cur_col >= COLS) cur_col = COLS - 1; break;
    case 'D': n = gp(0, 1); cur_col = (cur_col >= n) ? cur_col - n : 0; break;
    case 'H':
    case 'f':
        r = gp(0, 1); c = gp(1, 1);
        cur_row = (r > ROWS) ? ROWS - 1 : r - 1;
        cur_col = (c > COLS) ? COLS - 1 : c - 1;
        break;
    case 'J': do_ed(gp(0, 0)); break;
    case 'K': do_el(gp(0, 0)); break;
    case 'm': break;                         /* SGR: colour parsed elsewhere, not painted */
    case 's': saved_row = cur_row; saved_col = cur_col; break;
    case 'u': cur_row = saved_row; cur_col = saved_col; break;
    default:  break;
    }
}

static void ansi_feed(unsigned char c)
{
    unsigned char d;

    if (c == 27 && a_state != A_IDLE) { a_state = A_ESC; return; }

    switch (a_state) {
    case A_IDLE:
        if (c == 27) a_state = A_ESC;
        else if (c == 0x9B) { a_state = A_CSI; nparam = 0; have_digit = 0; param[0] = 0; }
        break;
    case A_ESC:
        if (c == '[')      { a_state = A_CSI; nparam = 0; have_digit = 0; param[0] = 0; }
        else if (c == 'O')   a_state = A_SS3;
        else if (c == 'c') { term_cls(); a_state = A_IDLE; }
        else if (c == ']')   a_state = A_OSC;
        else if (c >= 0x20 && c <= 0x2F) a_state = A_ESC2;
        else a_state = A_IDLE;
        break;
    case A_SS3:
        if (c == 'A' || c == 'B' || c == 'C' || c == 'D') ansi_dispatch(c);
        a_state = A_IDLE;
        break;
    case A_ESC2:
        a_state = A_IDLE;
        break;
    case A_OSC:
        if (c == 7) a_state = A_IDLE;
        else if (c == 27) a_state = A_OSC_E;
        break;
    case A_OSC_E:
        if (c == '\\') a_state = A_IDLE; else a_state = A_OSC;
        break;
    case A_CSI:
        if (c >= '0' && c <= '9') {
            d = c - '0';
            if (have_digit) param[nparam] = param[nparam] * 10 + d;
            else { param[nparam] = d; have_digit = 1; }
        } else if (c == ';') {
            if (nparam < MAXP - 1) nparam++;
            have_digit = 0; param[nparam] = 0;
        } else if (c == '?' || c == '>' || c == '<') {
            /* private prefix - ignore */
        } else if (c >= 0x20 && c <= 0x2F) {
            a_state = A_ESC2;
        } else if (c >= '@' && c <= '~') {
            if (have_digit || nparam > 0) { if (nparam < MAXP) nparam++; }
            ansi_dispatch(c);
            a_state = A_IDLE;
        } else {
            a_state = A_IDLE;
        }
        break;
    }
}

/* term_write: one display byte. ESC/CSI go to the ANSI parser; the rest land on the
 * grid at the cursor (mirrors screen.c screen_write). */
static void term_write(unsigned char c)
{
    if (a_state != A_IDLE || c == 27 || c == 0x9B) { ansi_feed(c); return; }
    if (c == '\r') { cur_col = 0; return; }
    if (c == '\n') { newline(); return; }
    if (c == 8)    { if (cur_col) cur_col--; return; }
    if (c == '\t') { cur_col = (cur_col + 8) & 0xF8; if (cur_col >= COLS) cur_col = COLS - 1; return; }
    if (c == 7)    return;                    /* BEL */
    if (c < 0x20 || c >= 0x7F) return;
    grid[cell(cur_row, cur_col)] = c;
    mark(cur_row);
    if (++cur_col >= COLS) { cur_col = 0; newline(); }
}

/* ---- rendering ------------------------------------------------------------- */
static char rowbuf[SEG + 1];

static void draw_seg(unsigned char r, unsigned char c0, unsigned char c1, unsigned char bx)
{
    unsigned char c, k = 0;
    for (c = c0; c < c1; c++) {
        unsigned char ch = grid[cell(r, c)];
        rowbuf[k++] = (ch >= 32 && ch < 127) ? (char)ch : ' ';
    }
    rowbuf[k] = 0;
    gb_textrev(bx, (unsigned char)(r * 8), rowbuf);
}

static void draw_row(unsigned char r)
{
    draw_seg(r, 0, SEG, 0);                   /* cols 0..47  -> byte 0  */
    draw_seg(r, SEG, COLS, 72);               /* cols 48..52 -> byte 72 */
}

static void render(void)
{
    unsigned char r;
    gb_curhide();
    for (r = 0; r < ROWS; r++)
        if (dirty[r]) { draw_row(r); dirty[r] = 0; }
    gb_curshow();
}

/* ---- telnet IAC ------------------------------------------------------------ */
#define IAC  0xFF
#define WILL 0xFB
#define WONT 0xFC
#define DO   0xFD
#define DONT 0xFE
#define SB   0xFA
#define SE   0xF0
#define OPT_ECHO  1
#define OPT_SGA   3
#define OPT_TTYPE 24
#define OPT_NAWS  31

#define IS_NORMAL 0
#define IS_IAC    1
#define IS_CMD    2
#define IS_SB     3
#define IS_SB_IAC 4

static unsigned char iac_state, iac_cmd, sb_opt, sb_cmd, sb_pos;
static unsigned char local_echo;

static void send3(unsigned char cmd, unsigned char opt)
{
    unsigned char r[3]; r[0] = IAC; r[1] = cmd; r[2] = opt;
    gb_net_send(r, 3);
}

static void send_ttype(void)
{
    unsigned char b[11];
    b[0] = IAC; b[1] = SB; b[2] = OPT_TTYPE; b[3] = 0;     /* IS */
    b[4] = 'v'; b[5] = 't'; b[6] = '1'; b[7] = '0'; b[8] = '0';
    b[9] = IAC; b[10] = SE;
    gb_net_send(b, 11);
}

static void send_naws(void)
{
    unsigned char b[9];
    b[0] = IAC; b[1] = SB; b[2] = OPT_NAWS;
    b[3] = 0; b[4] = COLS; b[5] = 0; b[6] = ROWS;
    b[7] = IAC; b[8] = SE;
    gb_net_send(b, 9);
}

/* feed one received byte through the telnet IAC machine; data bytes -> term_write. */
static void telnet_byte(unsigned char c)
{
    switch (iac_state) {
    case IS_NORMAL:
        if (c == IAC) iac_state = IS_IAC; else term_write(c);
        break;
    case IS_IAC:
        if (c == WILL || c == WONT || c == DO || c == DONT) { iac_cmd = c; iac_state = IS_CMD; }
        else if (c == SB) { sb_pos = 0; iac_state = IS_SB; }
        else if (c == IAC) { term_write(0xFF); iac_state = IS_NORMAL; }
        else iac_state = IS_NORMAL;          /* single-byte cmd - ignore */
        break;
    case IS_CMD:
        if (iac_cmd == WILL && c == OPT_ECHO)      { local_echo = 0; send3(DO, c); }
        else if (iac_cmd == WONT && c == OPT_ECHO) { local_echo = 1; send3(DONT, c); }
        else if (iac_cmd == WILL && c == OPT_SGA)  { send3(DO, c); }
        else if (iac_cmd == WILL)                  { send3(DONT, c); }
        else if (iac_cmd == DO) {
            if (c == OPT_NAWS)       { send3(WILL, c); send_naws(); }
            else if (c == OPT_TTYPE) { /* already offered WILL TTYPE */ }
            else if (c == OPT_SGA)   { send3(WILL, c); }
            else                       send3(WONT, c);
        }
        iac_state = IS_NORMAL;
        break;
    case IS_SB:
        if (c == IAC) iac_state = IS_SB_IAC;
        else if (sb_pos == 0) { sb_opt = c; sb_pos = 1; }
        else if (sb_pos == 1) { sb_cmd = c; sb_pos = 2; }
        break;
    case IS_SB_IAC:
        if (c == SE) {
            if (sb_opt == OPT_TTYPE && sb_cmd == 1) send_ttype();   /* SEND */
            iac_state = IS_NORMAL;
        } else if (c != IAC) iac_state = IS_SB;
        break;
    }
}

/* ---- connect target entry -------------------------------------------------- */
static unsigned char ip[4];
static unsigned int  port;
static char target[40];

/* parse "a.b.c.d[:port]" -> ip[]/port. Returns 1 on a valid dotted quad. */
static unsigned char parse_target(const char *s)
{
    unsigned char i, v;
    unsigned int p = 0;
    const char *q = s;
    for (i = 0; i < 4; i++) {
        if (*q < '0' || *q > '9') return 0;
        v = 0;
        while (*q >= '0' && *q <= '9') v = (unsigned char)(v * 10 + (*q++ - '0'));
        ip[i] = v;
        if (i < 3) { if (*q != '.') return 0; q++; }
    }
    if (*q == ':') { q++; while (*q >= '0' && *q <= '9') p = p * 10 + (*q++ - '0'); }
    port = p ? p : 23;
    return 1;
}

/* a small modal edit box on the connect screen; types into target[]. 1=Enter, 0=ESC. */
static unsigned char edit_target(void)
{
    unsigned char n = 0, fl, c, redraw = 1;
    while (target[n]) n++;
    while (gb_getkey()) ;
    while (1) {
        if (redraw) {
            gb_curhide();
            gb_fill(2, 48, 76, 8, 2);                 /* clear input line (black) */
            gb_textrev(2, 48, target);
            gb_curshow();
            redraw = 0;
        }
        fl = gb_poll();
        if (fl & GB_QUIT) { while (gb_poll() & GB_QUIT) ; return 0; }
        while ((c = gb_getkey()) != 0) {
            if (c == 0x0D) return (unsigned char)(n > 0);
            else if ((c == 8 || c == 0x7F) && n) { target[--n] = 0; redraw = 1; }
            else if (c >= 32 && c < 127 && n < sizeof(target) - 1) {
                target[n++] = (char)c; target[n] = 0; redraw = 1;
            }
        }
    }
}

static void msg(unsigned char line, const char *s) { gb_textrev(2, line, s); }  /* white on black */

/* a minimal click/key-to-dismiss error screen (avoids the GBUI dialog dependency). */
static void err_screen(const char *a, const char *b)
{
    gb_curhide();
    gb_fill(0, 0, 80, 200, 2);
    msg(8, a);
    if (b && *b) msg(24, b);
    msg(48, "Press a key...");
    gb_curshow();
    while (gb_getkey()) ;
    for (;;) {
        unsigned char f = gb_poll();
        if (f & (GB_CLICK | GB_QUIT)) break;
        if (gb_getkey()) break;
    }
}

/* host-socket mode ignores most of this; the chip just needs a MAC + a sane config. */
static const unsigned char netcfg[22] = {
    192,168,99,50,  255,255,255,0,  192,168,99,1,  192,168,99,1,
    0xDE,0xAD,0xBE,0xEF,0x00,0xFF
};

/* ---- session state machine ------------------------------------------------- */
#define ST_CONNECT 0       /* show dialog + connect on first frame */
#define ST_RUN     1
#define ST_DONE    2       /* disconnected; wait for a key to close */

static unsigned char state;
static unsigned char rbuf[256];

static void connect_screen(void)
{
    gb_curhide();
    gb_fill(0, 0, 80, 200, 2);                /* all black */
    msg(8,  "GEOBENCH TELNET");
    msg(24, "Connect to (host:port):");
    msg(40, "ESC cancels, ENTER connects");
    gb_curshow();
}

/* run the connect flow; returns 1 connected, 0 cancelled/failed (caller closes). */
static unsigned char do_connect(void)
{
    /* default target = the local test server */
    target[0] = 0;
    {
        static const char def[] = "127.0.0.1:2323";
        unsigned char i = 0;
        while (def[i]) { target[i] = def[i]; i++; }
        target[i] = 0;
    }
    for (;;) {
        connect_screen();
        if (!edit_target()) return 0;
        if (!parse_target(target)) { msg(64, "Enter a dotted IP (DNS later)"); continue; }
        break;
    }
    gb_curhide();
    gb_fill(0, 0, 80, 200, 2);
    msg(8, "Connecting...");
    gb_curshow();
    if (!gb_net_init(netcfg)) { err_screen("No Net4CPC chip", "Check net4cpc config"); return 0; }
    if (!gb_net_open())       { err_screen("Socket open failed", ""); return 0; }
    if (!gb_net_connect(ip, port)) { err_screen("Connect failed", "Host unreachable?"); return 0; }
    return 1;
}

/* pull whatever the server sent this frame through the telnet+ANSI pipeline. */
static void pump_recv(void)
{
    unsigned int n, i;
    n = gb_net_recv(rbuf, sizeof(rbuf));
    if (n) {
        for (i = 0; i < n; i++) telnet_byte(rbuf[i]);
    } else if (!gb_net_connected()) {
        term_write('\r'); term_write('\n');
        { const char *m = "** Disconnected - press a key **"; while (*m) term_write(*m++); }
        state = ST_DONE;
    }
}

/* send typed keys (CR -> CRLF; local echo when the server isn't echoing). */
static void pump_keys(void)
{
    unsigned char k;
    while ((k = gb_getkey()) != 0) {
        if (k == 0x0D) {
            unsigned char crlf[2]; crlf[0] = 0x0D; crlf[1] = 0x0A;
            if (local_echo) { term_write('\r'); term_write('\n'); }
            gb_net_send(crlf, 2);
        } else if (k >= 32 && k < 127) {
            if (local_echo) term_write(k);
            gb_net_send(&k, 1);
        } else if (k == 8 || k == 0x7F) {
            unsigned char b = 0x08;
            gb_net_send(&b, 1);
        }
    }
}

static void close_session(void)
{
    gb_net_close();
    WM_FS = 0;
    gb_wm_close();
}

/* ---- window callbacks (cooperative, fullscreen) ---------------------------- */
#ifdef TELNET_DEMO
/* offline render check (no net): drive term_write with a pattern that exercises the
 * full 53-col width (incl. the cols-48..52 second segment), wrap, and a scroll. */
static void demo_fill(void)
{
    unsigned int r, c;
    a_state = A_IDLE; iac_state = IS_NORMAL; local_echo = 1;
    term_cls();
    for (r = 0; r < 30; r++) {                 /* > ROWS so it scrolls */
        char hdr[8];
        hdr[0] = 'R'; hdr[1] = (char)('0' + (r / 10)); hdr[2] = (char)('0' + (r % 10));
        hdr[3] = ':'; hdr[4] = ' '; hdr[5] = 0;
        { char *p = hdr; while (*p) term_write(*p++); }
        for (c = 5; c < COLS; c++) term_write((unsigned char)('0' + (c % 10)));
        term_write('\r'); term_write('\n');
    }
    /* a marker at the far right edge of the grid (col 52) on the last row */
    cur_row = ROWS - 1; cur_col = COLS - 4;
    term_write('E'); term_write('N'); term_write('D'); term_write('!');
}
#endif

static void t_frame(void)
{
    if (state == ST_CONNECT) {
#ifdef TELNET_DEMO
        state = ST_RUN; demo_fill(); render(); return;
#endif
        if (!do_connect()) { WM_FS = 0; gb_wm_close(); return; }
        state = ST_RUN;
        iac_state = IS_NORMAL; local_echo = 1; a_state = A_IDLE;
        term_cls();
        send3(WILL, OPT_TTYPE);
        send3(WILL, OPT_NAWS);
        render();
        return;
    }
    if (gb_flags() & GB_QUIT) { close_session(); return; }
    if (state == ST_DONE) {
        if (gb_getkey()) close_session();
        render();
        return;
    }
    pump_recv();
    pump_keys();
    render();
}

static void t_repaint(void)
{
    if (state == ST_RUN || state == ST_DONE) { mark_all(); render(); }
}

static const gb_win_t twin = { 0, 0, 80, 200, t_frame, t_repaint, 0, 0 };

void main(void)
{
    state = ST_CONNECT;
    WM_FS = 1;
    gb_curhide();
    gb_fill(0, 0, 80, 200, 2);
    gb_curshow();
    gb_wm_add(&twin);
}
