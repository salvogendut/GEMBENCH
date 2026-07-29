/* gbsound.c - opt-in, app-linked sound primitives.
 *
 * This unit deliberately owns no timer or sequence state. Applications drive
 * note duration from GB_MSG_FRAME and stop sound before closing. CPC and MSX
 * use PSG channel A; PCW falls back to its fixed-frequency built-in beeper.
 */
#include "gb.h"

#ifdef GB_PCW

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

void gb_sound_tone(unsigned char note, unsigned char volume)
{
    (void)note;
    volume &= GB_SOUND_VOLUME_MAX;
    if (volume) pcw_beeper_on();
    else pcw_beeper_off();
}

void gb_sound_noise(unsigned char period, unsigned char volume)
{
    (void)period;
    volume &= GB_SOUND_VOLUME_MAX;
    if (volume) pcw_beeper_on();
    else pcw_beeper_off();
}

void gb_sound_stop(void)
{
    pcw_beeper_off();
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

/* Base octave C3..B3 for the 1.789773 MHz MSX PSG clock. */
static const unsigned int note_periods[12] = {
    856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 452
};
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

/* Base octave C3..B3 for the 1 MHz CPC PSG clock. */
static const unsigned int note_periods[12] = {
    478, 450, 426, 402, 380, 358, 338, 318, 300, 284, 268, 254
};
#endif

static void psg_write(unsigned char reg, unsigned char value)
{
    psg_reg = reg;
    psg_value = value;
    psg_write_hw();
}

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
