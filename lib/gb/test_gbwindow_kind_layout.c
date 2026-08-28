#include <stddef.h>

#define GB_MSX2 1
#include "gb.h"

typedef char gb_mwin_legacy_size_must_remain_12[
    sizeof(gb_mwin_t) == 12 ? 1 : -1
];
typedef char gb_mwin_kind_must_start_at_offset_12[
    offsetof(gb_mwin_kind_t, kind) == 12 ? 1 : -1
];
typedef char gb_mwin_kind_size_must_be_13[
    sizeof(gb_mwin_kind_t) == 13 ? 1 : -1
];
