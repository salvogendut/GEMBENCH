;; Diagnostic-only repaint timer for GEMBENCH's MSX2 baseline build.
;;
;; The RP-5C01 seconds-test bit advances the clock at 16,384 Hz in both
;; openMSX and 1983. A start/end pair of BCD seconds, minutes, and hours gives
;; a 61 us timebase with a 5.27-second unambiguous 24-hour window. Release
;; applications do not link this object. The diagnostic image uses a disposable
;; RTC because the accelerated clock intentionally changes its visible time.
        .module gbbaseline
        .globl  _gb_baseline_timer_start_full
        .globl  _gb_baseline_timer_start_damage
        .globl  _gb_baseline_timer_store_full
        .globl  _gb_baseline_timer_store_damage
        .globl  _gb_baseline_input_arm
        .globl  _gb_baseline_input_store_key

RTC_LATCH        = 0xB4
RTC_DATA         = 0xB5
RTC_MODE         = 13
RTC_TEST         = 14
RTC_MODE_KEEP    = 0x0C
RTC_TEST_SECONDS = 0x01
RTC_SAVED_MODE   = 0xC04C
RTC_SAVED_TEST   = 0xC04D
MSX_TICK         = 0xC000
SCHED_RUNNABLE   = 0x1344
INPUT_FLAGS      = 0xC02E
INPUT_KEY        = 0xC02F
POINTER_ARM      = 0xC04E
KEY_ARM          = 0xC052
KEY_ACK          = 0xC054
INPUT_RUNNABLE   = 0xC056

        .area   _CODE

;; Store block-0 time at HL as packed-BCD seconds, minutes, hours.
gb_baseline_rtc_read:
        ld      c, #0
gb_baseline_rtc_pair:
        ld      a, c
        out     (RTC_LATCH), a
        in      a, (RTC_DATA)
        and     #0x0F
        ld      e, a
        inc     c
        ld      a, c
        out     (RTC_LATCH), a
        in      a, (RTC_DATA)
        and     #0x0F
        rlca
        rlca
        rlca
        rlca
        or      e
        ld      (hl), a
        inc     hl
        inc     c
        ld      a, c
        cp      #6
        jr      nz, gb_baseline_rtc_pair
        ret

;; HL is the three-byte start destination.
gb_baseline_timer_begin:
        di
        ld      a, #RTC_MODE
        out     (RTC_LATCH), a
        in      a, (RTC_DATA)
        ld      (RTC_SAVED_MODE), a
        and     #RTC_MODE_KEEP       ; preserve timer/alarm bits, select block 0
        out     (RTC_DATA), a
        ld      a, #RTC_TEST
        out     (RTC_LATCH), a
        in      a, (RTC_DATA)
        ld      (RTC_SAVED_TEST), a
        xor     a
        out     (RTC_DATA), a        ; stop any pre-existing test mode
        call    gb_baseline_rtc_read
        ld      a, #RTC_TEST
        out     (RTC_LATCH), a
        ld      a, #RTC_TEST_SECONDS
        out     (RTC_DATA), a
        ei
        ret

;; HL is the three-byte end destination.
gb_baseline_timer_finish:
        di
        ld      a, #RTC_TEST
        out     (RTC_LATCH), a
        xor     a
        out     (RTC_DATA), a        ; freeze the accelerated clock before reading
        call    gb_baseline_rtc_read
        ld      a, #RTC_TEST
        out     (RTC_LATCH), a
        ld      a, (RTC_SAVED_TEST)
        out     (RTC_DATA), a
        ld      a, #RTC_MODE
        out     (RTC_LATCH), a
        ld      a, (RTC_SAVED_MODE)
        out     (RTC_DATA), a
        ei
        ret

_gb_baseline_timer_start_full:
        ld      hl, #0xC040
        jp      gb_baseline_timer_begin

_gb_baseline_timer_store_full:
        ld      hl, #0xC043
        jp      gb_baseline_timer_finish

_gb_baseline_timer_start_damage:
        ld      hl, #0xC046
        jp      gb_baseline_timer_begin

_gb_baseline_timer_store_damage:
        ld      hl, #0xC049
        jp      gb_baseline_timer_finish

;; Arm the emulator-driven input probes after the repaint samples finish.
;; The H.TIMI counter is the shared PAL-frame timebase; emulator scripts retain
;; their exact injection time and use these guest ticks as an independent check.
_gb_baseline_input_arm:
        di
        ld      hl, (MSX_TICK)
        ld      (POINTER_ARM), hl
        ld      (KEY_ARM), hl
        ld      a, (SCHED_RUNNABLE)
        ld      (INPUT_RUNNABLE), a
        ld      a, #1
        ld      (INPUT_FLAGS), a
        ei
        ret

;; A is the character whose visible acknowledgement has just been drawn.
_gb_baseline_input_store_key:
        di
        ld      (INPUT_KEY), a
        ld      hl, (MSX_TICK)
        ld      (KEY_ACK), hl
        ld      a, (INPUT_FLAGS)
        or      #4
        ld      (INPUT_FLAGS), a
        ei
        ret
