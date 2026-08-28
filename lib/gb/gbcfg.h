/* gbcfg.h - tiny read-only GEOBENCH.CFG helpers for apps and screensavers.
 *
 * The kernel keeps the current config text at #1000 and its length at #1200.
 * Values are deliberately parsed from a caller-supplied buffer first so the
 * rules are host-testable and Settings can inspect its editable copy.
 */
#ifndef GBCFG_H
#define GBCFG_H

static unsigned char gbcfg_u8_from(const char *text, unsigned int len,
                                   const char *key, unsigned char defval,
                                   unsigned char minval, unsigned char maxval)
{
    unsigned int i, p, value;
    unsigned char j, keylen = 0, digit, got, bad, result = defval;

    while (key[keylen]) keylen++;
    for (i = 0; i + keylen <= len; i++) {
        if (i && text[i - 1] != '\r' && text[i - 1] != '\n') continue;
        for (j = 0; j < keylen; j++)
            if (text[i + j] != key[j]) break;
        if (j != keylen) continue;

        p = i + keylen;
        value = 0;
        got = bad = 0;
        while (p < len && text[p] >= '0' && text[p] <= '9') {
            digit = (unsigned char)(text[p++] - '0');
            got = 1;
            if (value > 25 || (value == 25 && digit > 5)) bad = 1;
            else value = value * 10 + digit;
        }
        if (p < len && text[p] != '\r' && text[p] != '\n') bad = 1;
        if (!got || bad || value < minval || value > maxval)
            result = defval;
        else
            result = (unsigned char)value;
    }
    return result;
}

#ifndef GBCFG_HOST_TEST
#define GBCFG_TEXT ((const char *)0x1000)
#define GBCFG_LEN  (*(volatile unsigned int *)0x1200)

static unsigned char gbcfg_u8(const char *key, unsigned char defval,
                              unsigned char minval, unsigned char maxval)
{
    return gbcfg_u8_from(GBCFG_TEXT, GBCFG_LEN, key, defval, minval, maxval);
}
#endif

#endif
