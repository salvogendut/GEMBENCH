    unsigned char kl = 0, vl = 0;
    unsigned int p, end, i;
    while (key[kl]) kl++;
    while (val[vl]) vl++;
    if (cfglen == 0) return;                 /* no config loaded -> nothing to update */

    p = cfg_keypos(key);
    if (p == 0xFFFF) {                        /* no such key: append "KEY=val\r\n" */
        if (cfglen + kl + vl + 2 > sizeof(cfgbuf)) return;
        for (i = 0; i < kl; i++) cfgbuf[cfglen + i] = key[i];
        cfglen += kl;
        for (i = 0; i < vl; i++) cfgbuf[cfglen + i] = val[i];
        cfglen += vl;
        cfgbuf[cfglen++] = '\r'; cfgbuf[cfglen++] = '\n';
    } else {                                  /* replace the value in place */
        end = p;
        while (end < cfglen && cfgbuf[end] != '\r' && cfgbuf[end] != '\n') end++;
        if (vl > (unsigned char)(end - p)) {            /* grow: shift the tail right */
            unsigned int d = vl - (end - p);
            if (cfglen + d > sizeof(cfgbuf)) return;
            for (i = cfglen; i > end; i--) cfgbuf[i - 1 + d] = cfgbuf[i - 1];
            cfglen += d;
        } else if (vl < (unsigned char)(end - p)) {     /* shrink: shift the tail left */
            unsigned int d = (end - p) - vl;
            for (i = end; i < cfglen; i++) cfgbuf[i - d] = cfgbuf[i];
            cfglen -= d;
        }
        for (i = 0; i < vl; i++) cfgbuf[p + i] = val[i];
    }
