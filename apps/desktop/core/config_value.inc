static unsigned int cfg_val(const char *key, unsigned char klen)
{
    const char *t = KCFG_TEXT;
    unsigned int len = KCFG_LEN, i;
    unsigned char j;
    for (i = 0; i + klen <= len; i++) {
        if (i && t[i-1] != '\r' && t[i-1] != '\n') continue;   /* line start only */
        for (j = 0; j < klen; j++) if (t[i+j] != key[j]) break;
        if (j == klen) return i + klen;
    }
    return len;
}
