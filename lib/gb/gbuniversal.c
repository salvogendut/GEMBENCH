/* GEOBENCH-2 universal runtime accessors. Fixed mailbox addresses are private
 * to this SDK unit and are identical on every conforming kernel. */
#include "gbuniversal.h"

#define U_TIME       ((volatile unsigned char *)0x1240u)
#define U_MESSAGE    ((volatile unsigned char *)0x1302u)
#define U_BOOT_DRIVE (*(volatile unsigned char *)0x1336u)
#define U_DRAG_NAME  ((volatile unsigned char *)0x1423u)
#define U_DROP_CLAIM (*(volatile unsigned char *)0x142Fu)
#define U_LINE       ((volatile unsigned char *)0xC030u)
#define U_TEXT       ((volatile unsigned char *)0xC039u)
#define U_TIMER_DROP (*(volatile unsigned char *)0xC1ECu)
#define U_TIMER      ((volatile unsigned char *)0xC3CAu)

void gb_line_exec(void);
void gb_text_semantic_exec(void);

static const gb_sysinfo_v6_t *info_v6(void)
{
    const gb_sysinfo_t *legacy = gb_sysinfo();
    if (!legacy || legacy->size < GB_UNIVERSAL_SYSINFO_SIZE ||
        legacy->version < GB_UNIVERSAL_SYSINFO_VERSION) return 0;
    return (const gb_sysinfo_v6_t *)legacy;
}

const gb_sysinfo_v6_t *gb_universal_sysinfo(void)
{
    return info_v6();
}

unsigned char gb_universal_ready(void)
{
    const gb_sysinfo_v6_t *info = info_v6();
    unsigned int required_high = (unsigned int)(
        (GB_CAP_UNIVERSAL_LOADER | GB_CAP_RUNTIME_GEOMETRY) >> 16);
    return (unsigned char)(info &&
        info->universal_abi_major == GB_UNIVERSAL_ABI_MAJOR &&
        info->universal_profile == GB_UNIVERSAL_PROFILE_NATIVE_Z80 &&
        info->screen_columns != 0u && info->screen_lines != 0u &&
        info->pixels_per_column == 4u &&
        info->semantic_pens == 4u &&
        info->application_base == 0x4000u &&
        info->application_limit_exclusive == 0x7F00u &&
        info->kernel_table_base == 0x8000u &&
        (info->capabilities_high & required_high) == required_high);
}

unsigned char gb_has_capability(unsigned long capability)
{
    const gb_sysinfo_v6_t *info = info_v6();
    unsigned int low = (unsigned int)capability;
    unsigned int high = (unsigned int)(capability >> 16);
    if (!info) return 0;
    return (unsigned char)((info->capabilities_low & low) == low &&
                           (info->capabilities_high & high) == high);
}

unsigned char gb_screen_columns(void)
{
    const gb_sysinfo_v6_t *info = info_v6();
    return info ? info->screen_columns : 0;
}

unsigned char gb_screen_lines(void)
{
    const gb_sysinfo_v6_t *info = info_v6();
    return info ? info->screen_lines : 0;
}

unsigned int gb_screen_width_pixels(void)
{
    const gb_sysinfo_v6_t *info = info_v6();
    return info ? info->width_pixels : 0;
}

unsigned int gb_screen_height_pixels(void)
{
    const gb_sysinfo_v6_t *info = info_v6();
    return info ? info->height_pixels : 0;
}

unsigned char gb_screen_pixels_per_column(void)
{
    const gb_sysinfo_v6_t *info = info_v6();
    return info ? info->pixels_per_column : 0;
}

unsigned char gb_screen_semantic_pens(void)
{
    const gb_sysinfo_v6_t *info = info_v6();
    return info ? info->semantic_pens : 0;
}

unsigned int gb_pixel_aspect_x_256(void)
{
    const gb_sysinfo_v6_t *info = info_v6();
    /* Current reference displays: Screen 6 pixels are narrower than scanlines;
     * CPC/PCW bitmap pixels are treated as square by the portable UI. */
    return (info && info->platform == GB_PLATFORM_MSX2) ? 461u : 256u;
}

void gb_message_read(gb_msg_t *message)
{
    unsigned char i;
    unsigned char *out = (unsigned char *)message;
    if (!message) return;
    for (i = 0; i != sizeof(gb_msg_t); ++i) out[i] = U_MESSAGE[i];
}

void gb_message_set_p1(unsigned char value)
{
    U_MESSAGE[2] = value;
}

void gb_message_set_p2(unsigned char value)
{
    U_MESSAGE[3] = value;
}

void gb_time_read(gb_time_snapshot_t *snapshot)
{
    unsigned char i;
    unsigned char *out = (unsigned char *)snapshot;
    if (!snapshot) return;
    gb_time();
    for (i = 0; i != sizeof(gb_time_snapshot_t); ++i) out[i] = U_TIME[i];
}

void gb_time_observe(gb_time_snapshot_t *snapshot)
{
    unsigned char i;
    unsigned char *out = (unsigned char *)snapshot;
    if (!snapshot) return;
    for (i = 0; i != sizeof(gb_time_snapshot_t); ++i) out[i] = U_TIME[i];
}

unsigned char gb_boot_drive_current(void)
{
    return U_BOOT_DRIVE;
}

void gb_drag_name_read(char *name11)
{
    unsigned char i;
    if (!name11) return;
    for (i = 0; i != 11u; ++i) name11[i] = (char)U_DRAG_NAME[i];
}

void gb_drop_claim_current(void)
{
    U_DROP_CLAIM |= 0x80u;
}

void gb_drop_release_current(void)
{
    U_DROP_CLAIM &= 0x7Fu;
}

unsigned char gb_drop_is_claimed(void)
{
    return (unsigned char)((U_DROP_CLAIM & 0x80u) != 0u);
}

void gb_window_rect(gb_rect_t *rect)
{
    if (!rect) return;
    rect->x = gb_wm_x();
    rect->y = gb_wm_y();
    rect->w = gb_wm_w();
    rect->h = gb_wm_h();
}

static void put_word(volatile unsigned char *out, unsigned int value)
{
    out[0] = (unsigned char)value;
    out[1] = (unsigned char)(value >> 8);
}

void gb_line(unsigned int x0, unsigned int y0,
             unsigned int x1, unsigned int y1, unsigned char pen)
{
    put_word(U_LINE + 0, x0);
    put_word(U_LINE + 2, y0);
    put_word(U_LINE + 4, x1);
    put_word(U_LINE + 6, y1);
    U_LINE[8] = (unsigned char)(pen & 3u);
    gb_line_exec();
}

void gb_text_semantic(unsigned char x, unsigned char y, const char *text,
                      unsigned char pen, unsigned char paper)
{
    unsigned int pointer = (unsigned int)text;
    U_TEXT[0] = x;
    U_TEXT[1] = y;
    U_TEXT[2] = (unsigned char)(pen & 3u);
    U_TEXT[3] = (unsigned char)(paper & 3u);
    put_word(U_TEXT + 4, pointer);
    gb_text_semantic_exec();
}

unsigned char gb_timer_damage_for(gb_window_t window, unsigned char x,
                                  unsigned char y, unsigned char w,
                                  unsigned char h)
{
    unsigned char slot = (unsigned char)window;
    unsigned char generation = (unsigned char)(window >> 8);
    if (slot == 0u || slot > 8u || generation == 0u || w == 0u || h == 0u ||
        U_TIMER[0] != 0u) return 0u;
    U_TIMER[1] = x;
    U_TIMER[2] = y;
    U_TIMER[3] = w;
    U_TIMER[4] = h;
    U_TIMER[5] = generation;
    U_TIMER[0] = slot;             /* publish the complete request last */
    return 1u;
}

unsigned char gb_timer_active_for(gb_window_t window)
{
    return (unsigned char)(U_TIMER[0] ==
        (unsigned char)(0x80u | (unsigned char)window));
}

unsigned char gb_timer_take_dropped(gb_window_t window)
{
    unsigned char slot = (unsigned char)window;
    if (U_TIMER_DROP != slot) return 0u;
    U_TIMER_DROP = 0u;
    return 1u;
}

unsigned char gb_timer_busy(void)
{
    return (unsigned char)(U_TIMER[0] != 0u);
}

void gb_timer_cancel(gb_window_t window)
{
    unsigned char slot = (unsigned char)window;
    if (U_TIMER[0] == slot) U_TIMER[0] = 0u;
    if (U_TIMER_DROP == slot) U_TIMER_DROP = 0u;
}
