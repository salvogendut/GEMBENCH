#ifndef GEMBENCH_GBCONFIG_H
#define GEMBENCH_GBCONFIG_H

/* Publish one successfully saved, bounded GEOBENCH.CFG image to the resident
 * raw configuration cache. The caller retains the buffer; zero length is
 * valid and the maximum is 512 bytes. This root-callback-only synchronous operation
 * never retains the pointer, reparses configuration or requests repaint. */
#ifdef __SDCC
unsigned char gb_config_publish(const char *text, unsigned int length) __sdcccall(1);
#else
unsigned char gb_config_publish(const char *text, unsigned int length);
#endif

#endif
