/* serialspike - exercise the USIFAC II serial ports (&FBD0/&FBD1/&FBD8) standalone, to
 * de-risk #238 serial transport. Checks presence, sends a string, then prints whatever
 * the host sends back. Run in 1984 with usifac=true backend=tcp + a host client on the
 * port (tools/netspike/serclient.py). Built by build_serial.sh (cpcbios + crt0 only). */
#include "cpcbios.h"

static unsigned char sio;
static void s_status(void) __naked
{ __asm
    ld bc,#0xFBD1
    in a,(c)
    ld (_sio),a
    ret
__endasm; }
static void s_data_in(void) __naked
{ __asm
    ld bc,#0xFBD0
    in a,(c)
    ld (_sio),a
    ret
__endasm; }
static void s_data_out(void) __naked
{ __asm
    ld a,(_sio)
    ld bc,#0xFBD0
    out (c),a
    ret
__endasm; }
static void s_exists(void) __naked
{ __asm
    ld bc,#0xFBD8
    in a,(c)
    ld (_sio),a
    ret
__endasm; }

static void putc_ser(unsigned char c) { sio = c; s_data_out(); }

void main(void)
{
    unsigned int idle;
    cpc_set_mode(1);
    cpc_cls();
    cpc_print("SERIAL SPIKE\r\n");
    s_exists();
    if (sio == 0xFF) { cpc_print("NO USIFAC\r\n"); while (1) ; }
    cpc_print("usifac present\r\n");
    putc_ser('h'); putc_ser('i'); putc_ser('\r'); putc_ser('\n');
    cpc_print("sent hi; reading:\r\n");
    idle = 0;
    while (idle < 40000U) {
        s_status();
        if (sio == 0xFF) { s_data_in(); if (sio >= 0x20 || sio == '\r' || sio == '\n') cpc_print_char(sio); idle = 0; }
        else idle++;
    }
    cpc_print("\r\nDONE\r\n");
    while (1) ;
}
