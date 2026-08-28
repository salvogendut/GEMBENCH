/* gbsettime.c - opt-in binary system-clock setter.
 *
 * CPC has no resident bytes to spare for a new handler. Its software clock
 * aliases GB_TIME_BUF, while the Dallas writes preserve Clock's existing RTC
 * support. MSX/PCW retain their compact kernel setter in the historical slot.
 */
#include "gb.h"

static volatile unsigned char set_hour, set_minute, set_second;

#if defined(GB_MSX2) || defined(GB_PCW)
static void set_platform_time(void) __naked
{
__asm
    ld   a, (_set_hour)
    ld   b, a
    ld   a, (_set_minute)
    ld   c, a
    ld   a, (_set_second)
    ld   d, a
    call 0x802D
    ret
__endasm;
}
#else
static volatile unsigned char rtc_reg, rtc_value;

static void rtc_write(void) __naked
{
__asm
    ld   a, (_rtc_reg)
    ld   bc, #0xFD15
    out  (c), a
    ld   a, (_rtc_value)
    ld   bc, #0xFD14
    out  (c), a
    ret
__endasm;
}

static unsigned char rtc_format(unsigned char value)
{
    if (gb_binmode) return value;
    return (unsigned char)(((value / 10) << 4) | (value % 10));
}

static void rtc_set(unsigned char reg, unsigned char value)
{
    rtc_reg = reg;
    rtc_value = rtc_format(value);
    rtc_write();
}

static void set_platform_time(void)
{
    /* k_time selects the RTC's binary/BCD mode, or marks the software clock
     * binary. GB_TIME_BUF is also the CPC software-clock backing store. */
    gb_time();
    gb_hour = set_hour;
    gb_min = set_minute;
    gb_sec = set_second;
    rtc_set(4, set_hour);
    rtc_set(2, set_minute);
    rtc_set(0, set_second);
}
#endif

void gb_set_time(unsigned char hour, unsigned char minute,
                 unsigned char second)
{
    if (hour >= 24 || minute >= 60 || second >= 60) return;
    set_hour = hour;
    set_minute = minute;
    set_second = second;
    set_platform_time();
}
