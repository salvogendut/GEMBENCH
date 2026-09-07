/* Kept at the original position in main.c to preserve native MSX output. */
#if defined(GB_MSX2) || defined(GB_PCW)
static void si_call(void) __naked
{
__asm
    ld   a,(_si_ink)
    ld   b,a
    ld   c,a
    ld   a,(_si_pen)
    call 0x8006          ; GB_SETINK (A = pen 0-4, B/C = CPC ink)
    ret
__endasm;
}
#else
static void si_call(void) __naked
{
__asm
    ld   a,(_si_ink)
    ld   b,a
    ld   c,a
    ld   a,(_si_pen)
    call 0xBC32          ; SCR SET INK (A = pen, B/C = ink)
    ret
__endasm;
}
static void sb_call(void) __naked
{
__asm
    ld   a,(_si_ink)
    ld   b,a
    ld   c,a
    call 0xBC38          ; SCR SET BORDER (B/C = ink)
    ret
__endasm;
}
#endif
