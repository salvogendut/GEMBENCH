#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../kernel/kc/cpc_path83.h"

static void valid(const char *path)
{
    assert(cpc_path83_length((const unsigned char *)path,48)==strlen(path));
}
static void invalid(const char *path)
{
    assert(!cpc_path83_length((const unsigned char *)path,48));
}

int main(void)
{
    static const char punctuation[]="!#$%&'()-@^_`{}~";
    unsigned int i;
    valid("/");valid("/A");valid("/DIR.EXT");valid("/ABCDEF12.XYZ");
    valid("/DOCS/SUB.DIR/FILE1234.ABC");
    for (i=0;punctuation[i];i++) {
        char path[5]={'/',punctuation[i],'.','X',0};
        valid(path);assert(cpc_path83_char((unsigned char)punctuation[i]));
    }
    invalid("");invalid("A");invalid("//A");invalid("/A/");
    invalid("/.A");invalid("/A.");invalid("/A..B");
    invalid("/ABCDEFGHI");invalid("/A.ABCD");invalid("/lower");
    invalid("/A+B");invalid("/A B");invalid("/A/B//C");
    assert(!cpc_path83_length((const unsigned char *)"/ABC",4));
    puts("CPC path grammar: portable 8.3 components and punctuation PASS");
    return 0;
}
