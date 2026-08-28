/* gbsound.c - opt-in, app-linked sound primitives.
 *
 * This unit deliberately owns no timer or sequence state. Applications drive
 * note duration from GB_MSG_FRAME and stop sound before closing. CPC and MSX
 * use PSG channel A. PCW uses the DK'tronics AY when detected and otherwise
 * falls back to its fixed-frequency built-in beeper.
 */
#include "gb.h"

#ifdef GB_MSX2
/* Base octave C3..B3 for the 1.789773 MHz MSX PSG clock. */
static const unsigned int note_periods[12] = {
    856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 452
};
#else
/* Base octave C3..B3 for the 1 MHz CPC and DK'tronics PSG clocks. */
static const unsigned int note_periods[12] = {
    478, 450, 426, 402, 380, 358, 338, 318, 300, 284, 268, 254
};
#endif

static unsigned int note_period(unsigned char note)
{
    unsigned int period;
    unsigned char octave = 0;
    if (note > 47) note = 47;
    while (note >= 12) {
        note = (unsigned char)(note - 12);
        octave++;
    }
    period = note_periods[note];
    while (octave--) period = (unsigned int)((period + 1) >> 1);
    return period;
}

#ifdef GB_PCW

#define PCW_SOUND_UNKNOWN 0
#define PCW_SOUND_BEEPER  1
#define PCW_SOUND_DKSOUND 2

static volatile unsigned char pcw_psg_reg;
static volatile unsigned char pcw_psg_value;
static volatile unsigned char pcw_psg_readback;
static unsigned char pcw_sound_backend;

static void pcw_beeper_on(void) __naked
{
__asm
    ld   a,#0x0B
    out  (#0xF8),a
    ret
__endasm;
}

static void pcw_beeper_off(void) __naked
{
__asm
    ld   a,#0x0C
    out  (#0xF8),a
    ret
__endasm;
}

static void pcw_psg_write_hw(void) __naked
{
__asm
    ld   a,(_pcw_psg_reg)
    out  (#0xAA),a
    ld   a,(_pcw_psg_value)
    out  (#0xAB),a
    ret
__endasm;
}

static void pcw_psg_read_hw(void) __naked
{
__asm
    ld   a,(_pcw_psg_reg)
    out  (#0xAA),a
    in   a,(#0xA9)
    ld   (_pcw_psg_readback),a
    ret
__endasm;
}

static void pcw_psg_write(unsigned char reg, unsigned char value)
{
    pcw_psg_reg = reg;
    pcw_psg_value = value;
    pcw_psg_write_hw();
}

static unsigned char pcw_psg_read(unsigned char reg)
{
    pcw_psg_reg = reg;
    pcw_psg_read_hw();
    return pcw_psg_readback;
}

static unsigned char pcw_has_dksound(void)
{
    unsigned char saved;
    unsigned char first;
    unsigned char second;

    if (pcw_sound_backend != PCW_SOUND_UNKNOWN)
        return pcw_sound_backend == PCW_SOUND_DKSOUND;

    saved = pcw_psg_read(0);
    pcw_psg_write(0, 0x55);
    first = pcw_psg_read(0);
    pcw_psg_write(0, 0xAA);
    second = pcw_psg_read(0);
    pcw_psg_write(0, saved);

    if (first == 0x55 && second == 0xAA)
        pcw_sound_backend = PCW_SOUND_DKSOUND;
    else
        pcw_sound_backend = PCW_SOUND_BEEPER;
    return pcw_sound_backend == PCW_SOUND_DKSOUND;
}

static unsigned char pcw_tone_mixer(void)
{
    /* Keep B/C unchanged, disable A noise, enable A tone and keep joystick input. */
    return (unsigned char)((pcw_psg_read(7) | 0x48) & 0xFE);
}

static unsigned char pcw_noise_mixer(void)
{
    /* Keep B/C unchanged, disable A tone, enable A noise and keep joystick input. */
    return (unsigned char)((pcw_psg_read(7) | 0x41) & 0xF7);
}

static unsigned char pcw_stopped_mixer(void)
{
    return (unsigned char)(pcw_psg_read(7) | 0x49);
}

unsigned char gb_sound_caps(void)
{
    return pcw_has_dksound() ? GB_SOUND_CAP_PSG : 0;
}

void gb_sound_tone(unsigned char note, unsigned char volume)
{
    unsigned int period;
    volume &= GB_SOUND_VOLUME_MAX;
    if (!volume) {
        gb_sound_stop();
        return;
    }
    if (!pcw_has_dksound()) {
        pcw_beeper_on();
        return;
    }
    pcw_beeper_off();
    period = note_period(note);
    pcw_psg_write(8, 0);
    pcw_psg_write(0, (unsigned char)period);
    pcw_psg_write(1, (unsigned char)(period >> 8));
    pcw_psg_write(7, pcw_tone_mixer());
    pcw_psg_write(8, volume);
}

void gb_sound_noise(unsigned char period, unsigned char volume)
{
    volume &= GB_SOUND_VOLUME_MAX;
    if (!volume) {
        gb_sound_stop();
        return;
    }
    if (!pcw_has_dksound()) {
        pcw_beeper_on();
        return;
    }
    pcw_beeper_off();
    period &= 0x1F;
    if (!period) period = 1;
    pcw_psg_write(8, 0);
    pcw_psg_write(6, period);
    pcw_psg_write(7, pcw_noise_mixer());
    pcw_psg_write(8, volume);
}

void gb_sound_stop(void)
{
    pcw_beeper_off();
    if (!pcw_has_dksound()) return;
    pcw_psg_write(8, 0);
    pcw_psg_write(7, pcw_stopped_mixer());
}

#else

static volatile unsigned char psg_reg, psg_value;

#ifdef GB_MSX2
static volatile unsigned char psg_mixer;

static void psg_write_hw(void) __naked
{
__asm
    ld   a,(_psg_reg)
    out  (#0xA0),a
    ld   a,(_psg_value)
    out  (#0xA1),a
    ret
__endasm;
}

static void psg_read_mixer(void) __naked
{
__asm
    ld   a,#7
    out  (#0xA0),a
    in   a,(#0xA2)
    ld   (_psg_mixer),a
    ret
__endasm;
}

#else
static void psg_write_hw(void) __naked
{
__asm
    ld   a,(_psg_value)
    ld   c,a
    ld   a,(_psg_reg)
    call #0xBD34
    ret
__endasm;
}

#endif

static void psg_write(unsigned char reg, unsigned char value)
{
    psg_reg = reg;
    psg_value = value;
    psg_write_hw();
}

static unsigned char tone_mixer(void)
{
#ifdef GB_MSX2
    psg_read_mixer();
    return (unsigned char)((psg_mixer | 0x08) & 0xFE);
#else
    return 0x3E;
#endif
}

static unsigned char noise_mixer(void)
{
#ifdef GB_MSX2
    psg_read_mixer();
    return (unsigned char)((psg_mixer | 0x01) & 0xF7);
#else
    return 0x37;
#endif
}

static unsigned char stopped_mixer(void)
{
#ifdef GB_MSX2
    psg_read_mixer();
    return (unsigned char)(psg_mixer | 0x09);
#else
    return 0x3F;
#endif
}

unsigned char gb_sound_caps(void)
{
    return GB_SOUND_CAP_PSG;
}

void gb_sound_tone(unsigned char note, unsigned char volume)
{
    unsigned int period;
    volume &= GB_SOUND_VOLUME_MAX;
    if (!volume) {
        gb_sound_stop();
        return;
    }
    period = note_period(note);
    psg_write(8, 0);
    psg_write(0, (unsigned char)period);
    psg_write(1, (unsigned char)(period >> 8));
    psg_write(7, tone_mixer());
    psg_write(8, volume);
}

void gb_sound_noise(unsigned char period, unsigned char volume)
{
    volume &= GB_SOUND_VOLUME_MAX;
    if (!volume) {
        gb_sound_stop();
        return;
    }
    period &= 0x1F;
    if (!period) period = 1;
    psg_write(8, 0);
    psg_write(6, period);
    psg_write(7, noise_mixer());
    psg_write(8, volume);
}

void gb_sound_stop(void)
{
    psg_write(8, 0);
    psg_write(7, stopped_mixer());
}

#endif
