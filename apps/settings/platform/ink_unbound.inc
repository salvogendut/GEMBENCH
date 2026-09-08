static void si_call(void) { settings_set_ink(si_pen, si_ink); }
#if !defined(GB_MSX2) && !defined(GB_PCW)
static void sb_call(void) { settings_set_ink(4, si_ink); }
#endif
