# GEOBENCH applications

Each application is an SDCC Z80 binary built for MSX2 at
`0x4000–0x7FFF`. It calls the resident kernel through `lib/gb` and may opt into
the resource and service libraries explicitly.

The full distribution build is authoritative:

```sh
make geobench-msx
```

For a direct build, always select MSX2:

```sh
APPDEFS="-DGB_MSX2" DATA_LOC=0x7000 \
  tools/build_capp.sh apps/myapp build/msx/MYAPP.RAW
```

The builder rejects non-MSX2 application targets and verifies that loaded code,
data/BSS, and optional worker stacks fit below `0x8000`.

## Major applications

- `desktop` — root shell, icons, menus, compositor, accessories, and service
  collection;
- `filemgr` — drives, directories, list/icon views, file operations, launch
  contexts, and shell discovery;
- `notepad` — text documents, menus, bounded I/O, and typed scrap;
- `paint` — GEOBENCH-owned multi-window Paint;
- `settings` — colours, visual resources, and MSX video configuration;
- `viewer`, `browser`, `telnet` — pictures, HTTP content, and terminal access;
- `iconed` — icon-set and MSX2 sprite editing;
- `clock`, `calculator`, `shell`, `mahjong`, `xaos`, `diskutil` — desktop tools;
- saver directories — `.SAV` workers and optional same-stem `.MOD` setup UIs.

Bundled GB-BASIC lives under `components/gb-basic/` because it contains two
applications, an engine overlay, examples, and its own component documentation.

## Optional build profiles

`tools/build_capp.sh` links only requested facilities. Common flags include:

- `DOC=1`, `DIALOGS=1`, `WIDGETS=1`, `FORM=1`;
- `GBR_OBJECTS=1`, `GBR_MENUS=1`, `GBR_EMBEDDED=1`;
- `GB_VDI_BASE=1`, `GB_EVENTS=1`, `GB_REGIONS=1`;
- `GB_SCRAP=1`, `GB_SHELL_CLIENT=1`, `GB_SHELL_TARGET=1`;
- `GB_DEFER=1`, `GB_FSCTX=1`, `GB_SERVICE_CLIENT=1`;
- `GB_TIMER=1`, `TASK=1`.

Profiles have dependency checks and fixed-capacity runtime contracts. Follow an
existing application with the same ownership pattern instead of enabling a
broad set speculatively.

## Application packages

`APP_ICON=` embeds the canonical four-pen icon. An adjacent `icon16.asm` adds a
native Screen 7 icon. `APP_MANIFEST=` creates a guarded GBAP v3 package, and
`APP_SECONDARY=` adds a verified secondary mapper payload.

Public APIs and frozen contracts are documented in `include/gembench/`,
`lib/gb/gb.h`, and `docs/gembench/ABI-V1.md`.
