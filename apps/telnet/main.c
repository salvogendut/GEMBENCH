/* telnet - an ANSI/VT terminal + telnet client for GEOBENCH (#238).
 *
 * Fed by a TCP socket via the gb_net_* API (Net4CPC or M4 backend); speaks
 * RFC 854 telnet (IAC option negotiation) and parses ANSI/VT100 (cursor/erase/SGR), so
 * a real BBS / MUD / shell renders. Ported from cpc-sdcc examples/telnet (main.c IAC +
 * ansi.c + screen.c), keyboard via gb_getkey. Monochrome (white on blue).
 *
 * On the PCW target there is no GEOBENCH network module yet, so this builds as
 * serial-only over the CPS8256 Z80-DART (PerryFi / RS232). The TCP path stays
 * compiled for CPC, and the serial path still filters telnet IAC bytes so
 * PerryFi dial-outs to real telnet hosts render cleanly.
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
#ifdef GB_PCW
#define TELNET_HAS_NET        0
#define TELNET_HAS_FULLSCREEN 0
#else
#define TELNET_HAS_NET        1
#define TELNET_HAS_FULLSCREEN 1
#endif

#if TELNET_HAS_FULLSCREEN
#include "charset.h"        /* 8x8 ASCII glyphs for the Mode-2 80x25 renderer */
#endif

/* ---- terminal grid --------------------------------------------------------- */
/* The grid has two sizes: WINDOWED (Mode 1, 52x22, drawn through gb_text in the managed
 * window) and FULLSCREEN (Mode 2, 80x25, drawn straight to screen RAM with an 8x8
 * charset - the "proper telnet" view). COLS/ROWS are the ACTIVE dims (gcols/grows), so
 * all the term_write/ANSI/scroll code below is size-agnostic; only the renderer differs. */
#ifdef GB_PCW
#define WIN_COLS 58        /* 58 * 6px = 348px; fits the PCW CGA2 360px desktop */
#define WIN_ROWS 27        /* 23 + 27*8 = 239, inside the 248-line PCW desktop */
#else
#define WIN_COLS 52        /* 52 * 6px = 312px; inset 1 byte (4px) each side clears the frame */
#define WIN_ROWS 22        /* fits the content below the 14px title bar (178px / 8) */
#endif
#define FS_COLS  80        /* Mode 2: 640px / 8 = 80 cols */
#define FS_ROWS  25        /* Mode 2: 200px / 8 = 25 rows */
#if WIN_COLS > FS_COLS
#define GRID_MAX_COLS WIN_COLS
#else
#define GRID_MAX_COLS FS_COLS
#endif
#if WIN_ROWS > FS_ROWS
#define GRID_MAX_ROWS WIN_ROWS
#else
#define GRID_MAX_ROWS FS_ROWS
#endif
#define SEG  48            /* gb_text caps a string at 48 chars (gtd_copy) -> two windowed
                              segments per row; col 48 = 288px = byte 72 (4px-aligned) */

/* the windowed terminal lives in a screen-sized managed window; the grid sits in its
 * content area, just below the 14px title bar (the System top bar carries the menu). */
#define WIN_X 0
#define WIN_Y 8
#ifdef GB_PCW
#define WIN_W GB_COLS
#define WIN_H (GB_LINES - WIN_Y)
#else
#define WIN_W 80
#define WIN_H 192
#endif
#define GX    1            /* grid origin: byte column (inset 1 byte so the left frame survives) */
#define GY    (WIN_Y + 15) /* grid origin: pixel line, just below the 14px title bar */

/* connect dialog box (a centered modal popup, NOT painted into the terminal content) */
#define DLG_X 4
#define DLG_Y 76
#define DLG_W 72
#define DLG_H 46
/* the host:port input field: a bordered box inside the dialog, with a blinking caret */
#define FLD_X (DLG_X + 2)      /* field frame (byte col / line) */
#define FLD_Y (DLG_Y + 15)
#define FLD_W (DLG_W - 4)
#define FLD_H 13
#define IN_X  (DLG_X + 3)      /* text origin inside the field */
#define IN_Y  (DLG_Y + 18)

static unsigned char gcols = WIN_COLS, grows = WIN_ROWS;   /* active grid size */
static unsigned char fs_mode;                              /* 0 = windowed M1, 1 = fullscreen M2 */
#define COLS gcols
#define ROWS grows
static unsigned char grid[GRID_MAX_COLS * GRID_MAX_ROWS];  /* sized for the larger active grid */
static unsigned char dirty[GRID_MAX_ROWS];
static unsigned char cur_row, cur_col;
static unsigned char saved_row, saved_col;     /* ANSI SCP/RCP */
static unsigned char pcur_row = 0xFF, pcur_col; /* last-drawn cursor cell (for erase) */

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

/* destructive backspace: step back one cell and blank it. Used both for a locally
 * echoed keypress and for a BS/DEL received from the host (a host that sends "BS
 * space BS" still lands correctly: the space rewrites the blank, the 2nd BS re-blanks). */
static void bs_local(void)
{
    if (cur_col) { cur_col--; grid[cell(cur_row, cur_col)] = ' '; mark(cur_row); }
}

/* term_write: one display byte. ESC/CSI go to the ANSI parser; the rest land on the
 * grid at the cursor (mirrors screen.c screen_write). */
static void term_write(unsigned char c)
{
    if (a_state != A_IDLE || c == 27 || c == 0x9B) { ansi_feed(c); return; }
    if (c == '\r') { cur_col = 0; return; }
    if (c == '\n') { newline(); return; }
    if (c == 8 || c == 0x7F) { bs_local(); return; }   /* BS / DEL: erase prev char */
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

#if TELNET_HAS_FULLSCREEN
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
#endif

/* -- the text cursor: a 1px underline at the bottom of the current cell, so the user
 * can see where typing lands. Drawn by direct screen-RAM writes (gb_fill is 4px-
 * granular; the cell pitch is 6px, so we need pixel placement). Red (pen 3) in the
 * Mode-1 window; Mode 2 is 2-colour, so it falls back to white there. */
#ifdef GB_PCW
static void draw_cursor_m1(void)
{
    unsigned char x = (unsigned char)(GX + ((unsigned int)cur_col * 6) / 4);
    unsigned char y = (unsigned char)(GY + cur_row * 8 + 7);
    gb_fill(x, y, 2, 1, 3);
}
#else
static void plot_m1(unsigned int x, unsigned char y)        /* set pixel (x,y) to pen 3 (red) */
{
    unsigned int addr = 0xC000u + (unsigned int)(y >> 3) * 80
                      + (unsigned int)(y & 7) * 0x800u + (x >> 2);
    unsigned char i = (unsigned char)(x & 3);               /* M1: pen bit0 @ 7-i, bit1 @ 3-i */
    *((volatile unsigned char *)addr) |= (unsigned char)((0x80u >> i) | (0x08u >> i));
}
static void draw_cursor_m1(void)
{
    unsigned int x0 = (unsigned int)GX * 4 + (unsigned int)cur_col * 6;
    unsigned char y = (unsigned char)(GY + cur_row * 8 + 7);
    unsigned char i;
    for (i = 0; i < 6; i++) plot_m1(x0 + i, y);
}
#endif
#if TELNET_HAS_FULLSCREEN
static void draw_cursor_m2(void)                            /* M2: one byte = 8 white pixels */
{
    *((volatile unsigned char *)(0xC000u + (unsigned int)cur_row * 80 + cur_col + 7 * 0x800u)) = 0xFF;
}
#endif

static void render(void)
{
    unsigned char r;
    if (pcur_row != cur_row || pcur_col != cur_col) {   /* cursor moved: re-render to wipe the old one */
        mark(pcur_row); mark(cur_row);
    }
#if TELNET_HAS_FULLSCREEN
    if (fs_mode) {                             /* Mode 2: direct screen writes */
        render_m2();
        draw_cursor_m2();
    } else {
#endif
        gb_curhide();
        for (r = 0; r < ROWS; r++)
            if (dirty[r]) { draw_row(r); dirty[r] = 0; }
        draw_cursor_m1();
        gb_curshow();
#if TELNET_HAS_FULLSCREEN
    }
#endif
    pcur_row = cur_row; pcur_col = cur_col;
}

#if TELNET_HAS_FULLSCREEN
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
#endif

/* ---- serial port (the second transport) ------------------------------------ */
#ifdef GB_PCW
/* PCW CPS8256 / Z80-DART channel A. This follows ../vterm's PerryFi-tested path:
 * 0xE0 data, 0xE1 control/status. Status is RR0 after writing WR0=0:
 * bit 0 = RX available, bit 2 = TX buffer empty. */
#else
/* CPC USIFAC II RS232 at &FBD0 (data) / &FBD1 (status: 0xFF = RX byte ready,
 * else empty) / &FBD8 (presence: != 0xFF means a board is there). */
#endif
static volatile unsigned char ser_io;            /* port I/O scratch (the asm reads/writes it) */
#ifdef GB_PCW
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
static unsigned char pcw_ser_inited;
static void dart_wr(unsigned char reg, unsigned char val)
{
    ser_io = reg; ser_out_ctrl();
    ser_io = val; ser_out_ctrl();
}
static void serial_hw_init(void)
{
    if (pcw_ser_inited) return;
    /* PerryFi uses 9600 8N1. The CPS8256 PIT feeds the DART clock; 12 is
     * the standard 1.8432MHz / 16 / 9600 divisor. */
    ser_io = 0x36; pit_out_ctrl(); ser_io = 12; pit_out_tx(); ser_io = 0; pit_out_tx();
    ser_io = 0x76; pit_out_ctrl(); ser_io = 12; pit_out_rx(); ser_io = 0; pit_out_rx();
    ser_io = 0x18; ser_out_ctrl();             /* channel reset */
    dart_wr(4, 0x44);                           /* async, x16 clock, 1 stop, no parity */
    dart_wr(3, 0xC1);                           /* RX enable, 8-bit chars */
    dart_wr(5, 0xEA);                           /* TX enable, RTS/DTR, 8-bit chars */
    pcw_ser_inited = 1;
}
static unsigned char serial_present(void)
{
    ser_in_status();
    return (unsigned char)(ser_io != 0x7F && ser_io != 0xFF);
}
static void serial_ctrl(unsigned char cmd)
{
    unsigned char guard = 0;
    (void)cmd;
    serial_hw_init();
    while (guard++ != 0xFF) {
        ser_in_status();
        if (!(ser_io & 0x01)) break;
        ser_in_data();
    }
}
static unsigned int serial_recv(unsigned char *buf, unsigned int max)
{
    unsigned int n = 0;
    while (n < max) {
        ser_in_status();
        if (!(ser_io & 0x01)) break;
        ser_in_data();
        buf[n++] = ser_io;
    }
    return n;
}
static unsigned char serial_send(const unsigned char *buf, unsigned int len)
{
    unsigned int i;
    for (i = 0; i < len; i++) {
        do { ser_in_status(); } while (!(ser_io & 0x04));
        ser_io = buf[i];
        ser_out_data();
    }
    return 1;
}
#else
static void ser_in_data(void) __naked
{ __asm
    ld bc,#0xFBD0
    in a,(c)
    ld (_ser_io),a
    ret
__endasm; }
static void ser_out_data(void) __naked
{ __asm
    ld a,(_ser_io)
    ld bc,#0xFBD0
    out (c),a
    ret
__endasm; }
static void ser_in_status(void) __naked
{ __asm
    ld bc,#0xFBD1
    in a,(c)
    ld (_ser_io),a
    ret
__endasm; }
static void ser_out_ctrl(void) __naked
{ __asm
    ld a,(_ser_io)
    ld bc,#0xFBD1
    out (c),a
    ret
__endasm; }
static void ser_in_exists(void) __naked
{ __asm
    ld bc,#0xFBD8
    in a,(c)
    ld (_ser_io),a
    ret
__endasm; }

/* presence: &FBD8 != 0xFF (an absent board / no MX4 reads back 0xFF). */
static unsigned char serial_present(void) { ser_in_exists(); return (unsigned char)(ser_io != 0xFF); }
static void serial_ctrl(unsigned char cmd) { ser_io = cmd; ser_out_ctrl(); }

/* recv: drain up to max bytes while status reads 0xFF (RX non-empty). Only call when
 * present - an absent board reports 0xFF forever, which would flood. */
static unsigned int serial_recv(unsigned char *buf, unsigned int max)
{
    unsigned int n = 0;
    while (n < max) {
        ser_in_status();
        if (ser_io != 0xFF) break;       /* RX empty */
        ser_in_data();
        buf[n++] = ser_io;
    }
    return n;
}
static unsigned char serial_send(const unsigned char *buf, unsigned int len)
{
    unsigned int i;
    for (i = 0; i < len; i++) { ser_io = buf[i]; ser_out_data(); }
    return 1;
}
#endif

/* ---- transport: GBNET (TCP) or serial; the pumps route through these -------- */
#define TR_NET    0
#define TR_SERIAL 1
static unsigned char transport;

static unsigned char transport_send_iac(const unsigned char *buf, unsigned int len)
{
    if (transport == TR_SERIAL) return serial_send(buf, len);
#if TELNET_HAS_NET
    return gb_net_send(buf, len);
#else
    (void)buf; (void)len;
    return 0;
#endif
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
    transport_send_iac(r, 3);
}

static void send_ttype(void)
{
    unsigned char b[11];
    b[0] = IAC; b[1] = SB; b[2] = OPT_TTYPE; b[3] = 0;     /* IS */
    b[4] = 'v'; b[5] = 't'; b[6] = '1'; b[7] = '0'; b[8] = '0';
    b[9] = IAC; b[10] = SE;
    transport_send_iac(b, 11);
}

static void send_naws(void)
{
    unsigned char b[9];
    b[0] = IAC; b[1] = SB; b[2] = OPT_NAWS;
    b[3] = 0; b[4] = COLS; b[5] = 0; b[6] = ROWS;
    b[7] = IAC; b[8] = SE;
    transport_send_iac(b, 9);
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

#if TELNET_HAS_NET
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

/* the caret sits just after the last typed char (~6px/char from the field origin). */
#define CARET_X(n) ((unsigned char)(IN_X + ((unsigned int)(n) * 6) / 4))

/* a modal edit field on the connect dialog: a bordered box + a blinking caret. Types
 * into target[]; ENTER -> 1 (non-empty), ESC -> 0. */
static unsigned char edit_target(void)
{
    unsigned char n = 0, fl, c, redraw = 1, blink = 0, caret = 1;
    while (target[n]) n++;
    while (gb_getkey()) ;
    gb_curhide();
    gb_frame(FLD_X, FLD_Y, FLD_W, FLD_H, 2);                 /* the input field box */
    gb_curshow();
    while (1) {
        if (redraw) {                                        /* text changed: full redraw */
            gb_curhide();
            gb_fill(FLD_X + 1, FLD_Y + 1, FLD_W - 2, FLD_H - 2, 1);   /* clear interior */
            gb_textbw(IN_X, IN_Y, target);
            caret = 1; blink = 0;
            gb_fill(CARET_X(n), IN_Y, 1, 8, 2);              /* solid caret */
            gb_curshow();
            redraw = 0;
        }
        fl = gb_poll();
        if (fl & GB_QUIT) { while (gb_poll() & GB_QUIT) ; return 0; }
        if (++blink >= 14) {                                 /* ~0.3s caret blink */
            blink = 0; caret ^= 1;
            gb_curhide();
            gb_fill(CARET_X(n), IN_Y, 1, 8, (unsigned char)(caret ? 2 : 1));
            gb_curshow();
        }
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
#endif

/* ---- session state machine ------------------------------------------------- */
#define ST_IDLE 0          /* not connected; hint shown, Connect via the menu */
#define ST_RUN  1          /* connected; per-frame net pump */
#define ST_DONE 2          /* server disconnected; grid frozen, reconnect via the menu */

static unsigned char state;
static unsigned char rbuf[256];

/* recv-poll throttle (#238/#259): each gb_net_recv is a paged module call, so polling it
 * every frame hammers the disk on real HW. Poll every frame while data/typing flows,
 * then drop to every POLL_EVERY frames once idle (still ~16 Hz - imperceptible to type
 * against, far gentler on the drive). The kernel-side load-once cache would remove this
 * need, but doesn't fit the 1-byte resident headroom. */
#define POLL_EVERY  3
#define ACTIVE_HOLD 12          /* frames of full-speed polling after the last activity */
static unsigned char poll_ctr, active;

static unsigned char want_fs;          /* the 80x25 toggle: a connect enters Mode-2 fullscreen */
static void fs_label(void);            /* refresh the menu's [x]/[ ] checkbox */

/* Hint for paged services that must touch the Gate Array ROM/mode register.
 * High bit = valid, low bits = active CPC screen mode. The M4 network module
 * uses this while Telnet owns Mode 2 fullscreen, because firmware's mode shadow
 * is not reliable across the paged-module boundary. */
#define GB_VIDEO_MODE_HINT (*(volatile unsigned char *)0x14FF)
#define GB_VIDEO_MODE_VALID 0x80

static unsigned int t_recv(unsigned char *buf, unsigned int max)
{
    if (transport == TR_SERIAL) return serial_recv(buf, max);
#if TELNET_HAS_NET
    return gb_net_recv(buf, max);
#else
    (void)buf; (void)max;
    return 0;
#endif
}
static unsigned char t_send(const unsigned char *buf, unsigned int len)
{
    if (transport == TR_SERIAL) return serial_send(buf, len);
#if TELNET_HAS_NET
    return gb_net_send(buf, len);
#else
    (void)buf; (void)len;
    return 0;
#endif
}
static unsigned char t_connected(void)
{
    if (transport == TR_SERIAL) return serial_present();
#if TELNET_HAS_NET
    return gb_net_connected();
#else
    return 0;
#endif
}

#if TELNET_HAS_NET
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
    if (!gb_net_init(netcfg)) { err_screen("Network init failed", "Check network hardware"); return 0; }
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
#endif

/* pull whatever the server sent this frame through the telnet+ANSI pipeline.
 * Returns the byte count (0 = nothing this poll). */
static unsigned int pump_recv(void)
{
    unsigned int n, i;
    n = t_recv(rbuf, sizeof(rbuf));
    if (n) {
        for (i = 0; i < n; i++) {
            telnet_byte(rbuf[i]);                              /* IAC/telnet + ANSI */
        }
    } else if (!t_connected()) {
        term_write('\r'); term_write('\n');
        { const char *m = "** Disconnected - press a key **"; while (*m) term_write(*m++); }
        state = ST_DONE;
    }
    return n;
}

/* send one typed key (Enter = CR on serial, CRLF on telnet; local echo if enabled). */
static void send_key(unsigned char k)
{
    if (k == 0x0D) {
        if (local_echo) { term_write('\r'); term_write('\n'); }
        if (transport == TR_SERIAL) { unsigned char cr = 0x0D; t_send(&cr, 1); }
        else { unsigned char crlf[2]; crlf[0] = 0x0D; crlf[1] = 0x0A; t_send(crlf, 2); }
    } else if (k >= 32 && k < 127) {
        if (local_echo) term_write(k);
        t_send(&k, 1);
    } else if (k == 8 || k == 0x7F) {
        if (local_echo) bs_local();           /* erase locally when we echo */
        { unsigned char b = 0x08; t_send(&b, 1); }   /* and tell the host */
    }
}

/* Returns 1 if anything was sent this frame. */
static unsigned char pump_keys(void)
{
    unsigned char k, sent = 0;
    while ((k = gb_getkey()) != 0) { sent = 1; send_key(k); }
    return sent;
}

/* end the session (the window stays open; reconnect via the menu). */
static void close_session(void)
{
#if TELNET_HAS_NET
    if (transport == TR_NET && (state == ST_RUN || state == ST_DONE)) gb_net_close();
#endif
    state = ST_IDLE;
}

/* common session start (transport-agnostic); the caller does the transport-specific
 * handshake (telnet WILL options for TCP; nothing for the raw serial pipe). */
static void start_session(void)
{
    state = ST_RUN;
    a_state = A_IDLE;
    poll_ctr = 0; active = ACTIVE_HOLD;       /* full-speed for the login banner */
    term_cls();
}

/* ---- the Telnet top-bar menu (#238) ---------------------------------------- */
#if TELNET_HAS_NET
/* Connect over TCP: host:port dialog + DNS, then the telnet WILL handshake. */
static void action_connect(void)
{
    if (state == ST_RUN && transport == TR_NET) gb_net_close();
    gb_modal_set(1);                          /* a self-polling dialog is up */
    if (do_connect()) {
        transport = TR_NET;
        iac_state = IS_NORMAL; local_echo = 1;
        start_session();
        send3(WILL, OPT_TTYPE);
        send3(WILL, OPT_NAWS);
    } else state = ST_IDLE;
    gb_modal_set(0);
}
#endif

/* Connect over the serial port: no host, just open the raw byte pipe. */
static void action_connect_serial(void)
{
    if (!serial_present()) { gb_alert("No serial", "board detected"); return; }
    transport = TR_SERIAL;
    serial_ctrl(1);                           /* clear any stale RX */
    local_echo = 0;                           /* modems/serial hosts echo - avoid double chars */
    iac_state = IS_NORMAL;
    start_session();
}

#if TELNET_HAS_FULLSCREEN
/* ---- fullscreen Mode-2 80x25 terminal -------------------------------------- */
/* A takeover loop: switch the CPC to Mode 2 (640px) for a true 80x25 terminal and run
 * the recv/keyboard pump here until Ctrl-] / ESC / the server disconnects, then drop
 * back to Mode 1 and let the WM repaint the windowed view. */
static void run_fullscreen(void)
{
    unsigned char k, leave = 0;
    gb_modal_set(1);
    gb_curhide();
    GB_VIDEO_MODE_HINT = (unsigned char)(GB_VIDEO_MODE_VALID | 2);
    fs_mode = 1; gcols = FS_COLS; grows = FS_ROWS;
    term_cls();
    scr_set_mode(2);
    m2_clear();
    if (transport == TR_NET) send_naws();     /* re-advertise 80x25 (telnet only) */
    mark_all(); render();
    poll_ctr = 0; active = ACTIVE_HOLD;
    while (!leave) {
        /* (#274: the old gb_vsync() ESC test was a retired no-op - always "no ESC";
         * Ctrl-]/ESC below is the real exit, and the loop is recv-throttled.) */
        while ((k = gb_getkey()) != 0) {
            if (k == 0x1D || k == 0x1B) { leave = 1; break; }   /* Ctrl-] / ESC = exit */
            send_key(k); active = ACTIVE_HOLD;
        }
        if (active) { active--; if (pump_recv()) active = ACTIVE_HOLD; }
        else if (++poll_ctr >= POLL_EVERY) { poll_ctr = 0; if (pump_recv()) active = ACTIVE_HOLD; }
        if (state != ST_RUN) leave = 1;       /* disconnected */
        render();
    }
    GB_VIDEO_MODE_HINT = (unsigned char)(GB_VIDEO_MODE_VALID | 1);
    scr_set_mode(1);                          /* back to the Mode-1 desktop */
    fs_mode = 0; gcols = WIN_COLS; grows = WIN_ROWS;
    want_fs = 0; fs_label();                  /* exiting fullscreen turns the toggle off */
    if (state == ST_RUN && transport == TR_NET) send_naws();   /* re-advertise the windowed size */
    GB_VIDEO_MODE_HINT = 0;
    term_cls();                               /* the M2 screen is gone; start the window fresh */
    gb_modal_set(0);
}
#endif

/* Telnet menu: TCP connect / serial connect / disconnect / 80x25 toggle. The user drives
 * everything here (no auto-connect at launch). The 80x25 item is a toggle: when on, a
 * connect goes straight into the Mode-2 fullscreen view (exit it with Ctrl-] / ESC). */
/* item [3] carries a [x]/[ ] checkbox reflecting the 80x25 toggle (refreshed before the
 * menu opens, since gb_popup reads these label pointers live). */
#if TELNET_HAS_NET
static const char *telnet_items[4] = {
    "Connect (net)...", "Connect serial", "Disconnect", "80x25 fullscreen [ ]"
};
static void fs_label(void) { telnet_items[3] = want_fs ? "80x25 fullscreen [x]"
                                                        : "80x25 fullscreen [ ]"; }
static void on_menu(unsigned char sel)
{
    if (sel == 0) { action_connect();         if (want_fs && state == ST_RUN) run_fullscreen(); }
    else if (sel == 1) { action_connect_serial(); if (want_fs && state == ST_RUN) run_fullscreen(); }
    else if (sel == 2) close_session();
    else if (sel == 3) {                       /* toggle the 80x25 (Mode-2) preference */
        want_fs ^= 1;
        fs_label();
        if (want_fs && state == ST_RUN) run_fullscreen();        /* enter now if connected */
        else gb_alert("80x25 fullscreen", want_fs ? "ON - connect to use it" : "OFF");
    }
}
#else
static const char *telnet_items[2] = {
    "Connect serial", "Disconnect"
};
static void fs_label(void) { }
static void on_menu(unsigned char sel)
{
    if (sel == 0) action_connect_serial();
    else if (sel == 1) close_session();
}
#endif

/* a null document just enables the gb_menu_add framework (no File/Edit/View, #142). */
static const gb_doc_t telnetdoc = { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 };

/* ---- window callbacks (kernel-managed window) ------------------------------ */
#if defined(TELNET_DEMO) && TELNET_HAS_FULLSCREEN
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
    if (state == ST_IDLE) {                     /* idle: a hint; the user drives the menu */
        gb_curhide();
        gb_fill(GX, GY, (unsigned char)(WIN_W - 2 * GX), ROWS * 8, 0);   /* inside the frame */
        gb_text(2, GY + 8,  "GEOBENCH Telnet");
        gb_text(2, GY + 24, "Open the Telnet menu to begin");
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

static void t_frame(void)
{
#if defined(TELNET_DEMO) && TELNET_HAS_FULLSCREEN
    if (state == ST_IDLE) {                 /* offline Mode-2 80x25 render check (takeover) */
        gb_curhide();
        fs_mode = 1; gcols = FS_COLS; grows = FS_ROWS;
        scr_set_mode(2); m2_clear();
        start_session(); demo_fill(); render();
        for (;;) ;                          /* hold the M2 screen (no WM interference) */
    }
#endif
    /* idle on launch - the user drives everything from the Telnet menu (no auto-connect) */
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
#if TELNET_HAS_NET
        if (state == ST_RUN) gb_net_close();
#endif
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
#if TELNET_HAS_NET
    transport = TR_NET;
    want_fs = 1; fs_label();                    /* 80x25 fullscreen is on by default (checked) */
#else
    transport = TR_SERIAL;
    want_fs = 0; fs_label();
#endif
    gb_wm_managed(&tmw);                        /* register (no draw yet) (#146) */
    gb_doc(&telnetdoc);                          /* enable the menu framework (#142) */
#if TELNET_HAS_NET
    gb_menu_add("Telnet", (const char *const *)telnet_items, 4, on_menu);
#else
    gb_menu_add("Telnet", (const char *const *)telnet_items, 2, on_menu);
#endif
    gb_restore_parent();                         /* first paint: WM chrome + draw_content */
}
