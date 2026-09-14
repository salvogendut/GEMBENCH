#include "gbfilepick.h"
#include <stddef.h>
typedef char chooser_is_161_bytes[sizeof(gb_filepick_t) == 161 ? 1 : -1];
typedef char row_is_12_bytes[sizeof(gb_filepick_row_t) == 12 ? 1 : -1];
/* Diagnostic readers use these offsets; this is SDK state, not a frozen ABI. */
typedef char path_offset[offsetof(gb_filepick_t,path) == 17 ? 1 : -1];
typedef char name_offset[offsetof(gb_filepick_t,name) == 65 ? 1 : -1];
