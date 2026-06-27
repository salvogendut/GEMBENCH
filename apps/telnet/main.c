/* telnet - an ANSI/VT terminal + telnet client for GEOBENCH (#238).
 *
 * Fed by a TCP socket via the gb_net_* API (the paged GBNET.MOD W5100 driver); speaks
 * RFC 854 telnet (IAC option negotiation) and parses ANSI/VT100 (cursor/erase/SGR), so
 * a real BBS / MUD / shell renders. Ported from cpc-sdcc examples/telnet (main.c IAC +
 * ansi.c + screen.c), keyboard via gb_getkey. Monochrome (white on blue).
 *
 * Two views share one grid + the telnet/ANSI logic (only the renderer + dims differ):
 *   - WINDOWED  - a screen-sized managed Mode-1 window, 52x22, drawn through gb_text;
 *                 the System top bar carries a "Telnet" menu (Connect / Disconnect /
 *                 Fullscreen / Transport). Connect is a modal popup; host or dotted IP,
 *                 :port (default 23), names resolved via DNS (gb_net_resolve).
 *   - FULLSCREEN- Telnet > Fullscreen switches to Mode 2 (640px) for a true 80x25
 *                 terminal drawn straight to screen RAM with an 8x8 charset; a takeover
 *                 loop runs the recv/keyboard pump until Ctrl-] / ESC / disconnect.
 */
#include "gb.h"
#include "charset.h"        /* 8x8 ASCII glyphs for the Mode-2 80x25 renderer */

/* ---- terminal grid --------------------------------------------------------- */
/* The grid has two sizes: WINDOWED (Mode 1, 52x22, drawn through gb_text in the managed
 * window) and FULLSCREEN (Mode 2, 80x25, drawn straight to screen RAM with an 8x8
 * charset - the "proper telnet" view). COLS/ROWS are the ACTIVE dims (gcols/grows), so
 * all the term_write/ANSI/scroll code below is size-agnostic; only the renderer differs. */
#define WIN_COLS 52        /* 52 * 6px = 312px; inset 1 byte (4px) each side clears the frame */
#define WIN_ROWS 22        /* fits the content below the 14px title bar (178px / 8) */
#define FS_COLS  80        /* Mode 2: 640px / 8 = 80 cols */
#define FS_ROWS  25        /* Mode 2: 200px / 8 = 25 rows */
#define SEG  48            /* gb_text caps a string at 48 chars (gtd_copy) -> two windowed
                              segments per row; col 48 = 288px = byte 72 (4px-aligned) */

/* the windowed terminal lives in a screen-sized managed window; the grid sits in its
 * content area, just below the 14px title bar (the System top bar carries the menu). */
#define WIN_X 0
#define WIN_Y 8
#define WIN_W 80
#define WIN_H 192
#define GX    1            /* grid origin: byte column (inset 1 byte so the left frame survives) */
#define GY    (WIN_Y + 15) /* grid origin: pixel line, just below the 14px title bar */

/* connect dialog box (a centered modal popup, NOT painted into the terminal content) */
#define DLG_X 4
#define DLG_Y 76
#define DLG_W 72
#define DLG_H 46

static unsigned char gcols = WIN_COLS, grows = WIN_ROWS;   /* active grid size */
static unsigned char fs_mode;                              /* 0 = windowed M1, 1 = fullscreen M2 */
#define COLS gcols
#define ROWS grows
static unsigned char grid[FS_COLS * FS_ROWS];              /* sized for the larger (M2) grid */
static unsigned char dirty[FS_ROWS];
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
    gb_text(bx, (unsigned char)(GY + r * 8), rowbuf);   /* white on blue (paper 0), opaque */
}

static void draw_row(unsigned char r)
{
    draw_seg(r, 0, SEG, GX);                  /* cols 0..47  -> byte GX      */
    draw_seg(r, SEG, COLS, GX + 72);          /* cols 48..52 -> byte GX + 72 */
}

/* -- fullscreen (Mode 2) renderer: an 8x8 glyph straight to screen RAM. The char
 * cell's top scan line is #C000 + row*80 + col; the 8 scan lines are 0x800 apart.
 * #C000..#FFFF is the always-mapped screen RAM (same as the screensavers write). */
static void render_char(unsigned char col, unsigned char row, unsigned char ch)
{
    unsigned int base = 0xC000u + (unsigned int)row * 80 + col;
    const unsigned char *g = fs_charset + (unsigned int)(ch - FS_GLYPH0) * 8;
    unsigned char i;
    for (i = 0; i < 8; i++) {
        *((volatile unsigned char *)base) = g[i];
        base += 0x800u;
    }
}

static void render_m2(void)
{
    unsigned char r, c;
    for (r = 0; r < grows; r++) {
        if (!dirty[r]) continue;
        for (c = 0; c < gcols; c++) {
            unsigned char ch = grid[(unsigned int)r * gcols + c];
            render_char(c, r, (unsigned char)((ch >= 32 && ch < 127) ? ch : ' '));
        }
        dirty[r] = 0;
    }
}

static void render(void)
{
    unsigned char r;
    if (fs_mode) { render_m2(); return; }      /* Mode 2: direct screen writes */
    gb_curhide();
    for (r = 0; r < ROWS; r++)
        if (dirty[r]) { draw_row(r); dirty[r] = 0; }
    gb_curshow();
}

/* SCR_SET_MODE: A = mode. Mode 2 = 640x200 2-colour (pens 0/1 keep the desktop's
 * blue/white inks, so no palette change is needed); Mode 1 = back to the desktop. */
static void scr_set_mode(unsigned char m) __naked
{
    (void)m;                       /* mode arrives in A (sdcccall(1) first byte arg) */
    __asm
        call #0xBC0E
        ret
    __endasm;
}
/* clear the whole screen RAM (#C000..#FFFF) to ink 0 */
static void m2_clear(void) __naked
{
    __asm
        ld hl,#0xC000
        ld de,#0xC001
        ld bc,#0x3FFF
        ld (hl),#0
        ldir
        ret
    __endasm;
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
static char target[64];
static char hostbuf[48];

/* split "host:port" -> hostbuf + port (default 23). Returns 1 if the host is non-empty. */
static unsigned char split_target(const char *s)
{
    unsigned char i = 0;
    while (s[i] && s[i] != ':' && i < sizeof(hostbuf) - 1) { hostbuf[i] = s[i]; i++; }
    hostbuf[i] = 0;
    if (i == 0) return 0;
    port = 23;
    if (s[i] == ':') {
        unsigned int p = 0;
        const char *q = s + i + 1;
        while (*q >= '0' && *q <= '9') p = p * 10 + (*q++ - '0');
        if (p) port = p;
    }
    return 1;
}

/* parse a bare dotted-decimal "a.b.c.d" -> out[4]. Returns 1 if it's a clean IPv4
 * (so a non-match falls through to DNS). */
static unsigned char parse_dotted(const char *s, unsigned char *out)
{
    unsigned char i, v;
    const char *q = s;
    for (i = 0; i < 4; i++) {
        if (*q < '0' || *q > '9') return 0;
        v = 0;
        while (*q >= '0' && *q <= '9') v = (unsigned char)(v * 10 + (*q++ - '0'));
        out[i] = v;
        if (i < 3) { if (*q != '.') return 0; q++; }
    }
    return (unsigned char)(*q == 0);
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
            gb_fill(DLG_X + 2, DLG_Y + 18, DLG_W - 4, 8, 1);   /* clear input line (white) */
            gb_textbw(DLG_X + 2, DLG_Y + 18, target);
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

/* draw the white dialog box with a black frame + a title line. */
static void dlg_open(const char *title)
{
    gb_curhide();
    gb_fill(DLG_X, DLG_Y, DLG_W, DLG_H, 1);          /* white interior */
    gb_frame(DLG_X, DLG_Y, DLG_W, DLG_H, 2);         /* black frame    */
    gb_textbw(DLG_X + 2, DLG_Y + 3, title);
    gb_curshow();
}

/* show an error in the dialog box; click/key dismisses. */
static void err_screen(const char *a, const char *b)
{
    dlg_open(a);
    gb_curhide();
    if (b && *b) gb_textbw(DLG_X + 2, DLG_Y + 18, b);
    gb_textbw(DLG_X + 2, DLG_Y + 32, "Press a key...");
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
    192,168,99,50,  255,255,255,0,  192,168,99,1,  8,8,8,8,   /* DNS = 8.8.8.8 */
    0xDE,0xAD,0xBE,0xEF,0x00,0xFF
};

/* ---- session state machine ------------------------------------------------- */
#define ST_IDLE 0          /* not connected; hint shown, Connect via the menu */
#define ST_RUN  1          /* connected; per-frame net pump */
#define ST_DONE 2          /* server disconnected; grid frozen, reconnect via the menu */

static unsigned char state;
static unsigned char rbuf[256];

/* recv-poll throttle (#238): each gb_net_recv is a GBNET.MOD disk load, so polling it
 * every frame hammers the disk on real HW. Poll every frame while data/typing flows,
 * then drop to every POLL_EVERY frames once idle (still ~16 Hz - imperceptible to type
 * against, far gentler on the drive). The kernel-side load-once cache would remove this
 * need, but doesn't fit the 1-byte resident headroom. */
#define POLL_EVERY  3
#define ACTIVE_HOLD 12          /* frames of full-speed polling after the last activity */
static unsigned char poll_ctr, active;

static void connect_screen(void)
{
    dlg_open("Connect to (host:port):");
    gb_curhide();
    gb_textbw(DLG_X + 2, DLG_Y + 32, "ENTER connect   ESC cancel");
    gb_curshow();
}

/* run the connect flow; returns 1 connected, 0 cancelled/failed (caller closes). */
static unsigned char do_connect(void)
{
    /* target starts blank (a static: empty on first launch, then it keeps the last
     * host you typed, so reconnecting is just ENTER). Edit it in the dialog below. */
    for (;;) {
        connect_screen();
        if (!edit_target()) return 0;
        if (!split_target(target)) continue;     /* empty host: just re-prompt */
        break;
    }
    dlg_open("Connecting...");
    if (!gb_net_init(netcfg)) { err_screen("No Net4CPC chip", "Check net4cpc config"); return 0; }
    /* a dotted IP is used as-is; anything else is resolved via DNS (UDP socket 1). */
    if (!parse_dotted(hostbuf, ip)) {
        dlg_open("Resolving...");
        gb_curhide();
        gb_textbw(DLG_X + 2, DLG_Y + 18, hostbuf);
        gb_curshow();
        if (!gb_net_resolve(hostbuf, ip)) { err_screen("DNS lookup failed", hostbuf); return 0; }
    }
    if (!gb_net_open())       { err_screen("Socket open failed", ""); return 0; }
    if (!gb_net_connect(ip, port)) { err_screen("Connect failed", "Host unreachable?"); return 0; }
    return 1;
}

/* pull whatever the server sent this frame through the telnet+ANSI pipeline.
 * Returns the byte count (0 = nothing this poll). */
static unsigned int pump_recv(void)
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
    return n;
}

/* send typed keys (CR -> CRLF; local echo when the server isn't echoing).
 * Returns 1 if anything was sent this frame. */
static unsigned char pump_keys(void)
{
    unsigned char k, sent = 0;
    while ((k = gb_getkey()) != 0) {
        sent = 1;
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
    return sent;
}

/* close the network connection (the window stays open; reconnect via the menu). */
static void close_session(void)
{
    if (state == ST_RUN || state == ST_DONE) gb_net_close();
    state = ST_IDLE;
}

static void start_session(void)
{
    state = ST_RUN;
    iac_state = IS_NORMAL; local_echo = 1; a_state = A_IDLE;
    poll_ctr = 0; active = ACTIVE_HOLD;       /* full-speed for the login banner */
    term_cls();
    send3(WILL, OPT_TTYPE);
    send3(WILL, OPT_NAWS);
}

/* ---- the Telnet top-bar menu (#238 Phase 2) -------------------------------- */
#define TR_NET    0
#define TR_SERIAL 1
static unsigned char transport;           /* TR_NET for now; Serial is a future backend */

static void action_connect(void)
{
    if (state == ST_RUN) gb_net_close();      /* reconnect drops the old socket */
    gb_modal_set(1);                          /* a self-polling dialog is up */
    if (do_connect()) start_session();
    else state = ST_IDLE;
    gb_modal_set(0);
}

/* ---- fullscreen Mode-2 80x25 terminal -------------------------------------- */
/* A takeover loop: switch the CPC to Mode 2 (640px) for a true 80x25 terminal and run
 * the recv/keyboard pump here until Ctrl-] / ESC / the server disconnects, then drop
 * back to Mode 1 and let the WM repaint the windowed view. */
static void run_fullscreen(void)
{
    unsigned char k, leave = 0;
    gb_modal_set(1);
    gb_curhide();
    fs_mode = 1; gcols = FS_COLS; grows = FS_ROWS;
    term_cls();
    send_naws();                              /* re-advertise 80x25 to the server */
    scr_set_mode(2);
    m2_clear();
    mark_all(); render();
    poll_ctr = 0; active = ACTIVE_HOLD;
    while (!leave) {
        if (gb_vsync()) leave = 1;            /* ESC held -> leave fullscreen */
        while ((k = gb_getkey()) != 0) {
            if (k == 0x1D || k == 0x1B) { leave = 1; break; }   /* Ctrl-] / ESC = exit */
            if (k == 0x0D) {
                unsigned char crlf[2]; crlf[0] = 0x0D; crlf[1] = 0x0A;
                if (local_echo) { term_write('\r'); term_write('\n'); }
                gb_net_send(crlf, 2); active = ACTIVE_HOLD;
            } else if (k >= 32 && k < 127) {
                if (local_echo) term_write(k);
                gb_net_send(&k, 1); active = ACTIVE_HOLD;
            } else if (k == 8 || k == 0x7F) {
                unsigned char b = 0x08; gb_net_send(&b, 1);
            }
        }
        if (active) { active--; if (pump_recv()) active = ACTIVE_HOLD; }
        else if (++poll_ctr >= POLL_EVERY) { poll_ctr = 0; if (pump_recv()) active = ACTIVE_HOLD; }
        if (state != ST_RUN) leave = 1;       /* server disconnected */
        render();
    }
    scr_set_mode(1);                          /* back to the Mode-1 desktop */
    fs_mode = 0; gcols = WIN_COLS; grows = WIN_ROWS;
    if (state == ST_RUN) send_naws();         /* re-advertise the smaller windowed size */
    term_cls();                               /* the M2 screen is gone; start the window fresh */
    gb_modal_set(0);
}

/* Telnet menu: Connect / Disconnect / Fullscreen 80x25 / transport (Serial stubbed). */
static const char *const telnet_items[4] = {
    "Connect...", "Disconnect", "Fullscreen 80x25", "Transport: Serial"
};
static void on_menu(unsigned char sel)
{
    if (sel == 0) action_connect();
    else if (sel == 1) close_session();
    else if (sel == 2) {
        if (state == ST_RUN) run_fullscreen();
        else gb_alert("Fullscreen needs", "a live connection");
    }
    else if (sel == 3) gb_alert("Serial transport", "not available yet");
}

/* a null document just enables the gb_menu_add framework (no File/Edit/View, #142). */
static const gb_doc_t telnetdoc = { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 };

/* ---- window callbacks (kernel-managed window) ------------------------------ */
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

/* draw the window content (the WM already drew the frame + "Telnet" title bar). */
static void draw_content(void)
{
    if (state == ST_IDLE) {                     /* blank terminal; connect via the dialog/menu */
        gb_curhide();
        gb_fill(GX, GY, (unsigned char)(WIN_W - 2 * GX), ROWS * 8, 0);   /* inside the frame */
        gb_curshow();
    } else {                                   /* ST_RUN / ST_DONE: paint the grid */
        mark_all();
        render();
    }
}

/* per-frame work while connected: throttled recv + keys + grid redraw. */
static void net_frame(void)
{
    if (state != ST_RUN) return;               /* idle/disconnected: menu-driven */
    if (pump_keys()) active = ACTIVE_HOLD;
    if (active) {
        active--;
        if (pump_recv()) active = ACTIVE_HOLD;
    } else if (++poll_ctr >= POLL_EVERY) {
        poll_ctr = 0;
        if (pump_recv()) active = ACTIVE_HOLD;
    }
    render();
}

static unsigned char launched;                 /* auto-open the connect dialog on the 1st frame */

static void t_frame(void)
{
#ifdef TELNET_DEMO
    if (state == ST_IDLE) {                 /* offline Mode-2 80x25 render check (takeover) */
        launched = 1;
        gb_curhide();
        fs_mode = 1; gcols = FS_COLS; grows = FS_ROWS;
        scr_set_mode(2); m2_clear();
        start_session(); demo_fill(); render();
        for (;;) gb_vsync();                /* hold the M2 screen (no WM interference) */
    }
#endif
    if (!launched) { launched = 1; action_connect(); gb_restore_parent(); return; }
    if (gb_doc_frame()) { gb_restore_parent(); return; }   /* a Telnet-menu action ran */
    net_frame();
}

/* the window's single handler (#148): switch on the message type. */
static void t_proc(void)
{
    switch (gb_msg.type) {
    case GB_MSG_DRAW:  draw_content(); break;
    case GB_MSG_FRAME: t_frame();      break;
    case GB_MSG_CLICK: break;                              /* no in-content gesture */
    case GB_MSG_CLOSE:
        if (state == ST_RUN) gb_net_close();
        gb_wm_close();
        break;
    case GB_MSG_DRAG:  break;                              /* screen-sized: not movable */
    case GB_MSG_MENU:
    case GB_MSG_DROP:  gb_doc_event(); break;
    }
}

static const gb_mwin_t tmw = {
    WIN_X, WIN_Y, WIN_W, WIN_H, 0, 0, t_proc, "Telnet"     /* min_w 0 = not resizable */
};

void main(void)
{
    state = ST_IDLE;
    transport = TR_NET;
    launched = 0;
    gb_wm_managed(&tmw);                        /* register (no draw yet) (#146) */
    gb_doc(&telnetdoc);                          /* enable the menu framework (#142) */
    gb_menu_add("Telnet", telnet_items, 4, on_menu);
    gb_restore_parent();                         /* first paint: WM chrome + draw_content */
}
