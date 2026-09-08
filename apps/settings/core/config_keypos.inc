static unsigned int cfg_keypos(const char *key)
{
    unsigned char kl = 0, j;
    unsigned int i;
    while (key[kl]) kl++;
    for (i = 0; i + kl <= cfglen; i++) {
        if (i && cfgbuf[i-1] != '\r' && cfgbuf[i-1] != '\n') continue;   /* line start only */
        for (j = 0; j < kl; j++) if (cfgbuf[i+j] != key[j]) break;
        if (j == kl) return i + kl;
    }
    return 0xFFFF;
}
