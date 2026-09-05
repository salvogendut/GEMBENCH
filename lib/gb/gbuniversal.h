/* gbuniversal.h - GEOBENCH-2 compile-once application SDK surface. */
#ifndef GB_UNIVERSAL_H
#define GB_UNIVERSAL_H

#ifndef GB_UNIVERSAL
#error "gbuniversal.h requires the GB_UNIVERSAL build profile"
#endif
#if defined(GB_MSX2) || defined(GB_PCW) || defined(PLATFORM_MSX) || \
    defined(PLATFORM_CPC) || defined(PLATFORM_PCW)
#error "GB_UNIVERSAL cannot be combined with a target build define"
#endif

#include "gb.h"

/* gb.h retains target-era defaults for legacy builds. Universal source must
 * use the functions below, so compiling an old GB_COLS-based layout fails. */
#undef GB_COLS
#undef GB_LINES
#undef GB_XPIX

/* Hide the small resident mailbox behind a source-level API. The universal
 * libgb implementation owns the fixed addresses required by the binary ABI. */
#undef gb_dragname
#undef gb_drop_claim
#undef gb_drop_release
#undef gb_drop_claimed
#undef gb_msg
#undef gb_pic_edit_buf
#undef gb_pic_edit_off
#undef gb_hour
#undef gb_min
#undef gb_sec
#undef gb_binmode
#undef gb_ksize
#undef gb_boot_drive
#undef gb_copybuf
#undef GB_COPYMAX

#define GB_PLATFORM_MSX2 1u
#define GB_PLATFORM_CPC  2u
#define GB_PLATFORM_PCW  3u

#define GB_PACKING_1BPP 1u

#define GB_CAP_UNIVERSAL_LOADER  0x00010000UL
#define GB_CAP_RUNTIME_GEOMETRY  0x00020000UL
#define GB_CAP_PORTABLE_DRAWING  0x00040000UL
#define GB_CAP_PORTABLE_INPUT    0x00080000UL
#define GB_CAP_PORTABLE_FS       0x00100000UL
#define GB_CAP_PACKAGE_RESOURCES 0x00200000UL
#define GB_CAP_BACKGROUND_TIMERS 0x00400000UL
#define GB_CAP_CALLER_PARAMETERS 0x00800000UL

#define GB_UNIVERSAL_ABI_MAJOR 2u
#define GB_UNIVERSAL_ABI_MINOR 1u
#define GB_UNIVERSAL_SYSINFO_VERSION 6u
#define GB_UNIVERSAL_SYSINFO_SIZE 48u
#define GB_UNIVERSAL_PROFILE_NATIVE_Z80 3u

/* Append-only view of GB_SYSINFO v6. The first 32 bytes exactly mirror
 * gb_sysinfo_t v5; using a distinct type keeps legacy builds at sizeof 32 until
 * the MSX2 reference kernel actually publishes the suffix. */
typedef struct {
    unsigned char size;
    unsigned char version;
    unsigned char abi_major;
    unsigned char abi_minor;
    unsigned char platform;
    unsigned char video_mode;
    unsigned int width_pixels;
    unsigned int height_pixels;
    unsigned char packing;
    unsigned char colours;
    unsigned char memory_pages;
    unsigned char pool_pages;
    unsigned char free_pages;
    unsigned char max_windows;
    unsigned int capabilities_low;
    unsigned int reserved;
    unsigned char max_applications;
    unsigned char application_record_version;
    unsigned char max_windows_per_application;
    unsigned char reserved2;
    unsigned char message_queue_capacity;
    unsigned char message_inline_bytes;
    unsigned char message_api_version;
    unsigned char reserved3;
    unsigned char filesystem_contexts;
    unsigned int filesystem_transfer_bytes;
    unsigned char filesystem_api_version;
    unsigned int capabilities_high;
    unsigned char screen_columns;
    unsigned char screen_lines;
    unsigned char pixels_per_column;
    unsigned char semantic_pens;
    unsigned int application_base;
    unsigned int application_limit_exclusive;
    unsigned int kernel_table_base;
    unsigned char universal_abi_major;
    unsigned char universal_abi_minor;
    unsigned char universal_profile;
    unsigned char reserved4;
} gb_sysinfo_v6_t;

/* Fail the target build if compiler packing ever changes the binary record. */
typedef char gb_sysinfo_v6_size_must_be_48[
    sizeof(gb_sysinfo_v6_t) == GB_UNIVERSAL_SYSINFO_SIZE ? 1 : -1
];

typedef struct {
    unsigned char hour;
    unsigned char minute;
    unsigned char second;
    unsigned char binary;
} gb_time_snapshot_t;

typedef struct {
    unsigned char x;
    unsigned char y;
    unsigned char w;
    unsigned char h;
} gb_rect_t;

/* Portable extension of the frozen managed-window descriptor. Furniture and
 * move/resize gestures are kernel-owned, so the same descriptor works on each
 * conforming target without app-linked drag code. */
typedef struct {
    gb_mwin_t window;
    unsigned char kind;
} gb_mwin_kind_t;

/* The returned sysinfo pointer is resident/read-only for the process lifetime.
 * NULL means that the running kernel has not published the complete v6 suffix. */
const gb_sysinfo_v6_t *gb_universal_sysinfo(void);
unsigned char gb_universal_ready(void);
unsigned char gb_has_capability(unsigned long capability);

unsigned char gb_screen_columns(void);
unsigned char gb_screen_lines(void);
unsigned int gb_screen_width_pixels(void);
unsigned int gb_screen_height_pixels(void);
unsigned char gb_screen_pixels_per_column(void);
unsigned char gb_screen_semantic_pens(void);
unsigned int gb_pixel_aspect_x_256(void);

void gb_message_read(gb_msg_t *message);
void gb_message_set_p1(unsigned char value);
void gb_message_set_p2(unsigned char value);
void gb_time_read(gb_time_snapshot_t *snapshot);
void gb_time_observe(gb_time_snapshot_t *snapshot);
unsigned char gb_boot_drive_current(void);
void gb_drag_name_read(char *name11);
void gb_drop_claim_current(void);
void gb_drop_release_current(void);
unsigned char gb_drop_is_claimed(void);
void gb_window_rect(gb_rect_t *rect);

/* Pixel-coordinate semantic line. The call completes before returning. */
#define GB_PARAMS_SIZE 16u
#define GB_PARAMS_VERSION 1u
#define GB_PARAMS_LINE 1u
#define GB_PARAMS_TEXT 2u
#define GB_PARAMS_TIMER_DAMAGE 3u
#define GB_PARAMS_TIMER_ACTIVE 4u
#define GB_PARAMS_TIMER_DROPPED 5u
#define GB_PARAMS_TIMER_BUSY 6u
#define GB_PARAMS_TIMER_CANCEL 7u
#define GB_PARAMS_OK 0u
#define GB_PARAMS_BADARG 1u
#define GB_PARAMS_CONTEXT 2u
#define GB_PARAMS_STALE 3u
#define GB_PARAMS_OWNER 4u
#define GB_PARAMS_BUSY 5u
#define GB_PARAMS_UNSUPPORTED 6u
typedef struct {
    unsigned char operation;
    unsigned char version;
    unsigned char data[14];
} gb_params_t;
typedef char gb_params_size_must_be_16[sizeof(gb_params_t) == 16 ? 1 : -1];

/* Low-level ABI 2.1 call: record and pointed-to text must be in this app's
 * primary page below 0x7F00, not on the kernel-owned stack. High result byte
 * is GB_PARAMS_* status; low byte is a boolean. Prefer the typed wrappers,
 * which safely stage automatic/stack data before entering this service. */
unsigned int gb_parameters(const gb_params_t *request);

void gb_line(unsigned int x0, unsigned int y0,
             unsigned int x1, unsigned int y1, unsigned char pen);
void gb_text_semantic(unsigned char x, unsigned char y, const char *text,
                      unsigned char pen, unsigned char paper);

/* Small save-under dropdown used by compile-once top-bar menus. Call it from
 * GB_MSG_FRAME after a GB_MSG_MENU callback has armed the desired title. */
unsigned char gb_universal_popup(unsigned char x,
                                 const char *const *labels,
                                 unsigned char count);
unsigned char gb_universal_popup_active(void);
void gb_universal_popup_close(void);

/* Background visual timer contract. The worker only observes the root-owned
 * time snapshot and publishes bounded damage for its generation-tagged window.
 * Drawing remains in the normal root/compositor callback. */
unsigned char gb_timer_damage_for(gb_window_t window, unsigned char x,
                                  unsigned char y, unsigned char w,
                                  unsigned char h);
unsigned char gb_timer_active_for(gb_window_t window);
unsigned char gb_timer_take_dropped(gb_window_t window);
unsigned char gb_timer_busy(void);
void gb_timer_cancel(gb_window_t window);

void gb_wm_managed_kind(const gb_mwin_kind_t *desc);

#endif
