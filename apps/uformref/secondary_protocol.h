#ifndef GEMBENCH_UFORMREF_SECONDARY_PROTOCOL_H
#define GEMBENCH_UFORMREF_SECONDARY_PROTOCOL_H

/* Value-only record copied into and out of the sealed GBS4 computation bank. */
#define FORMREF_COMPUTE_VERSION       1u
#define FORMREF_COMPUTE_SIZE         40u
#define FORMREF_COMPUTE_NAME         2u
#define FORMREF_COMPUTE_SIGNATURE   15u
#define FORMREF_COMPUTE_SERIAL      16u
#define FORMREF_COMPUTE_AUTOSAVE    17u
#define FORMREF_COMPUTE_LAYOUT      30u
#define FORMREF_COMPUTE_BUTTON      39u

#define FORMREF_FLAG_AUTOSAVE        1u
#define FORMREF_FLAG_REFINED         2u
#define FORMREF_FLAG_RESOURCE        4u
#define FORMREF_COMPUTE_OK        0xA5u

#endif
