static unsigned char ss_run_module(void) __naked
{
__asm
    ld a,#0x80
    call #0x80AE
    ld a,c
    ret
__endasm;
}
