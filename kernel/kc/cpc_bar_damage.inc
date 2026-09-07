/* A root exposure callback may own only part of the bar. Render that part,
 * but do not claim the entire current menu/time was published: only the
 * ordinary full-clip bar tick can advance the global delta-refresh cache.
 * In particular, a focus change can occur between those two callbacks. */
void cpc_bar_damage(void)
{
    unsigned char init = bar_init, hour = bar_hour, minute = bar_min;
    unsigned char signature = bar_msig, fullscreen = bar_wasfs;
    cpc_bar_reset();
    cpc_bar_tick();
    bar_init = init; bar_hour = hour; bar_min = minute;
    bar_msig = signature; bar_wasfs = fullscreen;
}
