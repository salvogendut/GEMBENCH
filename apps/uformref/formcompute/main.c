/* Sealed computation only: no SDK calls, target state, pointers or drawing. */
#include "../secondary_protocol.h"

static unsigned char calls;

static void copy_text(unsigned char *destination, const char *source,
                      unsigned char capacity)
{
    unsigned char index = 0;
    while (source[index] && index + 1u < capacity) {
        destination[index] = (unsigned char)source[index];
        index++;
    }
    destination[index] = 0;
}

void secondary_main(unsigned char *block, unsigned int length)
{
    unsigned char flags;
    if (length != FORMREF_COMPUTE_SIZE ||
        block[0] != FORMREF_COMPUTE_VERSION)
        return;
    flags = block[1];
    block[FORMREF_COMPUTE_SIGNATURE] = FORMREF_COMPUTE_OK;
    block[FORMREF_COMPUTE_SERIAL] = ++calls;
    copy_text(block + FORMREF_COMPUTE_AUTOSAVE,
              (flags & FORMREF_FLAG_AUTOSAVE) ? "Autosave on" : "Autosave off",
              13u);
    copy_text(block + FORMREF_COMPUTE_LAYOUT,
              (flags & FORMREF_FLAG_REFINED) ? "Refined" : "Classic", 9u);
    block[FORMREF_COMPUTE_BUTTON] =
        (flags & FORMREF_FLAG_RESOURCE) ? 0u : 1u;
}
