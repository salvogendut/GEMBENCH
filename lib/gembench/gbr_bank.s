;; MSX2 GBR mapper-service trampoline. The retired GB_BLITE slot is repurposed
;; only by the MSX kernel; CPC and PCW retain their inert legacy slot.
        .module gbr_bank_call
        .globl  _gbr_segment_call

        .area   _CODE
_gbr_segment_call:
        jp      0x8018
