#ifndef GEMBENCH_CPC_PATH83_H
#define GEMBENCH_CPC_PATH83_H

/* Match the portable chooser's deliberately bounded DOS 8.3 alphabet. */
static unsigned char cpc_path83_char(unsigned char ch)
{
    static const char punctuation[]="!#$%&'()-@^_`{}~";
    const char *p;
    if ((ch>='A' && ch<='Z') || (ch>='0' && ch<='9')) return 1;
    for (p=punctuation;*p;p++) if ((unsigned char)*p==ch) return 1;
    return 0;
}

/* Validate an absolute NUL-terminated path and return its byte length. Root is
 * length one. Each later component is BASE[.EXT], with 1..8 and 1..3 bytes.
 * A zero result means invalid or unterminated. */
static unsigned char cpc_path83_length(const volatile unsigned char *path,
                                       unsigned char capacity)
{
    unsigned char i,base=0,ext=0,dot=0,ch;
    if (!path || capacity<2u || path[0]!='/') return 0;
    for (i=1;i<capacity;i++) {
        ch=path[i];
        if (!ch || ch=='/') {
            if (i==1u && !ch) return 1; /* root */
            if (!base || (dot && !ext)) return 0;
            if (!ch) return i;
            base=ext=dot=0;
        } else if (ch=='.') {
            if (!base || dot) return 0;
            dot=1;
        } else {
            if (!cpc_path83_char(ch)) return 0;
            if (dot) { if (++ext>3u) return 0; }
            else if (++base>8u) return 0;
        }
    }
    return 0;
}

#endif
