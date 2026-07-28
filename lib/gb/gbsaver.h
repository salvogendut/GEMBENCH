/* gbsaver.h - persisted per-screensaver configuration contracts. */
#ifndef GBSAVER_H
#define GBSAVER_H

#define GB_STARFLD_SPEED_KEY      "STARFLD_SPEED="
#define GB_STARFLD_SPEED_DEFAULT  4
#define GB_STARFLD_SPEED_MIN      1
#define GB_STARFLD_SPEED_MAX      8

#define GB_STARFLD_STARS_KEY      "STARFLD_STARS="
#define GB_STARFLD_STARS_DEFAULT  64
#define GB_STARFLD_STARS_MIN      16
#define GB_STARFLD_STARS_MAX      96
#define GB_STARFLD_STARS_STEP     8

#define GB_XMATRIX_GLYPHS_KEY      "XMATRIX_GLYPHS="
#define GB_XMATRIX_GLYPHS_DEFAULT  0
#define GB_XMATRIX_GLYPHS_MIN      0
#define GB_XMATRIX_GLYPHS_MAX      1

#define GB_XMATRIX_SPEED_KEY      "XMATRIX_SPEED="
#define GB_XMATRIX_SPEED_DEFAULT  2
#define GB_XMATRIX_SPEED_MIN      1
#define GB_XMATRIX_SPEED_MAX      3

#define GB_XMATRIX_COLOR_KEY      "XMATRIX_COLOR="

/* CPC uses firmware hardware-ink numbers. */
#define GB_XMATRIX_CPC_COLOR_DEFAULT  18
#define GB_XMATRIX_CPC_COLOR_MIN      0
#define GB_XMATRIX_CPC_COLOR_MAX      26

/* Screen 7 palette indices 4..15 are stable across desktop themes. */
#define GB_XMATRIX_MSX_COLOR_DEFAULT  4
#define GB_XMATRIX_MSX_COLOR_MIN      4
#define GB_XMATRIX_MSX_COLOR_MAX      15

#endif
