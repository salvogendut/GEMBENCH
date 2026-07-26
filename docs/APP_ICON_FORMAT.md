# Embedded APP icon format

GEOBENCH applications may begin with an optional `GBAP` executable preamble.
The first three bytes remain a Z80 `JP` to the relocated application entry, so
the kernel continues launching every `.APP` at `#4000`. Headerless applications
remain valid and use their mapped or generic `.IST` icon.

All embedded icons are 32x32 pixels:

- codec `1`: portable four-colour CPC Mode-1 packing, 8 bytes per row and
  256 bytes total;
- codec `7`: native MSX Screen-7 packing, two four-bit pixels per byte,
  16 bytes per row and 512 bytes total.

## GBAP v1

V1 carries one codec-1 icon:

| Offset | Size | Meaning |
|---:|---:|---|
| 0 | 3 | `JP #4110` |
| 3 | 4 | ASCII `GBAP` |
| 7 | 1 | version `1` |
| 8 | 1 | codec `1` |
| 9 | 1 | packed row width `8` |
| 10 | 1 | height `32` |
| 11 | 2 | bitmap length `256` |
| 13 | 2 | bitmap offset `16` |
| 15 | 1 | reserved |
| 16 | 256 | canonical bitmap |

`APP_ICON=path/icon.asm` continues to generate this byte-identical format.

## GBAP v2

V2 adds an explicit resource directory:

| Offset | Size | Meaning |
|---:|---:|---|
| 0 | 3 | `JP` to `#4000 + preamble size` |
| 3 | 4 | ASCII `GBAP` |
| 7 | 1 | version `2` |
| 8 | 1 | resource count |
| 9 | 1 | directory entry size, currently `8` |
| 10 | 2 | complete preamble size |
| 12 | 2 | directory offset, currently `16` |
| 14 | 2 | reserved |

Each eight-byte directory entry is:

| Entry offset | Size | Meaning |
|---:|---:|---|
| 0 | 1 | codec |
| 1 | 1 | packed row width |
| 2 | 1 | height |
| 3 | 1 | flags, currently zero |
| 4 | 2 | bitmap length |
| 6 | 2 | bitmap offset from APP start |

Entry 0 is the required codec-1 fallback. Entry 1 may be codec 7. A dual
32x32 header is 800 bytes, relocates the entry to `#4320`, and is produced with:

```sh
APP_ICON=apps/example/icon.asm \
APP_ICON16=apps/example/icon16.asm \
tools/build_capp.sh apps/example build/EXAMPLE.RAW
```

The 16-colour ASM source declares its packing explicitly:

```asm
appicon16_mode  equ 7
appicon16_w     equ 16
appicon16_h     equ 32
appicon16
                db  #12,#34
                ; ...512 bytes total
```

File Manager selects codec 7 only while the MSX is running Screen 7. MSX
Screen 6, CPC, and PCW use codec 1. All targets preserve resources they do not
display when saving an APP.

`tools/iconedit.py` opens either ASM source and both resources inside a v2 APP.
Use Previous/Next to switch variants. `ICONED.APP` edits both variants on MSX
Screen 7; on other targets and in MSX Screen 6 it exposes the portable icon and
preserves the native resource. Its whole-document ceiling is 7,168 bytes.
ICONED borrows one expansion page while a document is open; low RAM is used only
for short filesystem and editor transfers, so File Manager repaints cannot
overwrite the document.
