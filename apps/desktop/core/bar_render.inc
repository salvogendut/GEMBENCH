/* Shared Desktop bar renderer. Provider supplies MENU_DEF, KCFG_MEMSTR,
 * WM_FS, CLK_COL, geometry and the native libgb presentation/time calls.
 * Keep its state and delta-redraw policy identical for every target. */
static unsigned char bar_init, bar_hour, bar_min, bar_msig, bar_wasfs;

static unsigned char bin(unsigned char v)   /* raw RTC reg -> binary (gb_time) */
{
    return gb_binmode ? v : (unsigned char)((v >> 4) * 10 + (v & 15));
}
static void put2(char *p, unsigned char v) { p[0] = '0' + v / 10; p[1] = '0' + v % 10; }

/* bar_menu: the focused window's menu titles (MENU_DEF: count, then {col, 8-byte
   label}*count). Clear the title region first so a previous app's titles are gone. */
static void bar_menu(void)
{
    unsigned char n = MENU_DEF[0], i, j;
    char lbl[9];
    gb_curhide();
    gb_fill(8, 0, 46, 8, 1);                  /* white, cols 8..53 (RAM/footprint/clock kept) */
    for (i = 0; i < n && i < 4; i++) {
        for (j = 0; j < 8; j++) lbl[j] = MENU_DEF[2 + i * 9 + j];
        lbl[8] = 0;
        gb_textbw(MENU_DEF[1 + i * 9], 0, lbl);
    }
    gb_curshow();
}

static void bar_clock(unsigned char h, unsigned char m)
{
    char t[6];
    put2(t, bin(h)); t[2] = ':'; put2(t + 3, bin(m)); t[5] = 0;
    gb_curhide(); gb_textbw(CLK_COL, 0, t); gb_curshow();
}
