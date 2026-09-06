/* Existing Desktop callback: defer launch until the popup has unwound. */
static void accessory_action(unsigned char sel)
{
    if (sel < GB_DESK_ACCESSORY_COUNT) want_accessory = (unsigned char)(sel + 1);
}
