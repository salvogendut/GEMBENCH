/* GEOBENCH-2.1 universal runtime accessors. Legacy low-RAM observations remain
 * private to this unit; drawing and timers use caller-owned GB_PARAMS records. */
#include "gbuniversal.h"

#define U_TIME       ((volatile unsigned char *)0x1240u)
#define U_MESSAGE    ((volatile unsigned char *)0x1302u)
#define U_BOOT_DRIVE (*(volatile unsigned char *)0x1336u)
#define U_DRAG_NAME  ((volatile unsigned char *)0x1423u)
#define U_DROP_CLAIM (*(volatile unsigned char *)0x142Fu)
/* Internal assembly bridge serializes a stack record into this app's primary
 * page. Root and worker calls cannot overwrite each other's in-flight data. */
unsigned int gb_uparam_call(const gb_params_t *request);

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
        (GB_CAP_UNIVERSAL_LOADER | GB_CAP_RUNTIME_GEOMETRY |
         GB_CAP_CALLER_PARAMETERS) >> 16);
    return (unsigned char)(info &&
        info->universal_abi_major == GB_UNIVERSAL_ABI_MAJOR &&
        info->universal_abi_minor >= GB_UNIVERSAL_ABI_MINOR &&
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
    gb_params_t request;
    request.operation = GB_PARAMS_LINE;
    request.version = GB_PARAMS_VERSION;
    put_word(request.data + 0, x0);
    put_word(request.data + 2, y0);
    put_word(request.data + 4, x1);
    put_word(request.data + 6, y1);
    request.data[8] = (unsigned char)(pen & 3u);
    (void)gb_uparam_call(&request);
}

void gb_text_semantic(unsigned char x, unsigned char y, const char *text,
                      unsigned char pen, unsigned char paper)
{
    gb_params_t request;
    unsigned char length = 0u;
    if (!text) return;
    while (length < 48u && text[length]) ++length;
    request.operation = GB_PARAMS_TEXT;
    request.version = GB_PARAMS_VERSION;
    request.data[0] = x;
    request.data[1] = y;
    request.data[2] = (unsigned char)(pen & 3u);
    request.data[3] = (unsigned char)(paper & 3u);
    put_word(request.data + 4, (unsigned int)text);
    request.data[6] = length;
    (void)gb_uparam_call(&request);
}

unsigned char gb_timer_damage_for(gb_window_t window, unsigned char x,
                                  unsigned char y, unsigned char w,
                                  unsigned char h)
{
    gb_params_t request;
    request.operation = GB_PARAMS_TIMER_DAMAGE;
    request.version = GB_PARAMS_VERSION;
    put_word(request.data, window);
    request.data[2] = x;
    request.data[3] = y;
    request.data[4] = w;
    request.data[5] = h;
    return (unsigned char)(gb_uparam_call(&request) == 1u);
}

static unsigned char timer_request(unsigned char operation, gb_window_t window)
{
    gb_params_t request;
    request.operation = operation;
    request.version = GB_PARAMS_VERSION;
    put_word(request.data, window);
    return (unsigned char)(gb_uparam_call(&request) == 1u);
}

unsigned char gb_timer_active_for(gb_window_t window)
{
    return timer_request(GB_PARAMS_TIMER_ACTIVE, window);
}

unsigned char gb_timer_take_dropped(gb_window_t window)
{
    return timer_request(GB_PARAMS_TIMER_DROPPED, window);
}

unsigned char gb_timer_busy(void)
{
    return timer_request(GB_PARAMS_TIMER_BUSY, 0u);
}

void gb_timer_cancel(gb_window_t window)
{
    (void)timer_request(GB_PARAMS_TIMER_CANCEL, window);
}
