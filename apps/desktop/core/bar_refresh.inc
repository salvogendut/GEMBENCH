/* Shared bar refresh fragment. Local msig/i and fullscreen idle state are
 * supplied by the root caller; no target-specific menu/redraw policy here. */
    gb_time();                                  /* also refreshes fixed bytes used by timer workers */
    if (*WM_FS) { bar_wasfs = 1; return; }    /* fullscreen: the borderless window owns lines 0-7 */
    if (bar_wasfs) {                          /* just exited fullscreen (e.g. the saver closed) -> */
        bar_wasfs = 0; bar_init = 0;          /* force a full bar redraw, and restart the idle count */
        ss_idle = 0; ss_lmx = gb_mx(); ss_lmy = gb_my();
    }
    if (!bar_init) {                          /* first frame: white strip + RAM size */
        gb_curhide();
        gb_fill(0, 0, GB_COLS, 8, 1);
        gb_textbw(1, 0, KCFG_MEMSTR);
        gb_curshow();
        bar_init = 1; bar_hour = 0xFF; bar_min = 0xFF; bar_msig = 0xFF;
    }
    msig = 0;                                  /* menu titles: redraw when MENU_DEF changes */
    for (i = 0; i < (unsigned char)(MENU_DEF[0] * 9 + 1) && i < 40; i++) msig += MENU_DEF[i];
    if (msig != bar_msig) { bar_msig = msig; bar_menu(); }
                                              /* clock: redraw when the displayed time changes */
    if (gb_hour != bar_hour || gb_min != bar_min) {
        bar_hour = gb_hour;
        bar_min = gb_min;
        bar_clock(gb_hour, gb_min);
    }
