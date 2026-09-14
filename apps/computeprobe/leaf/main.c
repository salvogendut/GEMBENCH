/* Pure model fixture: persistent BSS, initialized data and a full 4-KiB array. */
static unsigned int calls;
static unsigned char cookie=0x5A;
static unsigned char document[4096];
void secondary_main(unsigned char *block,unsigned int length)
{
    unsigned int i;
    if(!calls) {
        for(i=0;i<4096;++i)if(document[i])cookie=0;
        document[0]=0x11;document[4095]=0x77;
    } else if(document[0]!=0x11 || document[4095]!=0x77)cookie=0;
    ++calls;
    block[0]=(unsigned char)calls;
    if(length>1)block[1]=cookie;
    for(i=2;i<length;++i)block[i]^=0xA5;
}
