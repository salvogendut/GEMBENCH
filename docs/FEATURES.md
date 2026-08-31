# GEOBENCH features

GEOBENCH is an MSX2 desktop with its blue, white, black, and red base theme,
Screen 6/7 support, mapper-backed applications, and MSX-DOS 2/Nextor storage.

## Desktop and system

- draggable desktop icons, folders, trash, menus, and configurable wallpaper;
- managed windows with kernel-owned furniture, focus, move, resize,
  maximize/restore, and exact visible-region repaint;
- focused/visible worker scheduling and parking of fully covered visual work;
- Desk accessories with stable IDs, activation, close, and page release;
- Settings for visual assets, colours, MSX video mode, and system choices;
- clock/top bar, screensavers, sound, file associations, and multiple drives.

## Applications

- File Manager with list/icon views, sorting, scrolling, navigation, copy, move,
  delete, launch contexts, and live-app reuse;
- Notepad with document menus, bounded I/O, typed text scrap, and shell service;
- GEOBENCH-owned multi-window Paint;
- Viewer and Browser with bounded image/content rendering;
- Icon editor for icon sets and MSX2 sprites;
- Telnet and Browser networking through TCP/IP UNAPI;
- Clock, Calculator, Shell, Mahjong, Disk Utility, fractal generator, and a
  collection of configurable screensavers;
- bundled GB-BASIC editor, interpreter, low-RAM engine, and examples.

## GEM-inspired architecture

- deterministic GBR1 resource compiler and allocation-free reader;
- object trees, forms, menus, stable IDs, bindings, focus, and hit testing;
- VDI-lite semantic drawing contexts and explicit raster bindings;
- versioned GBAP application manifests and secondary mapper resources;
- multiple windows per application owner;
- generation-safe page, window, context, and service handles;
- bounded deferred messages, shell discovery, typed scrap, filesystem
  contexts, shared-service leases, and app timers;
- frozen `GEMBENCH-1` resource and managed-window compatibility ABI.

## Formats

The desktop loads `.APP`, `.SAV`, `.MOD`, `.GBR`, `.PIC`, `.IST`, `.SPR`,
`.FNT`, `.BDP`, `.TBR`, and `.GDT` resources. Canonical four-pen assets use the
historical Mode-1 byte packing and are decoded by the MSX2 kernel; native
Screen 7 variants may supply sixteen-colour resources.

GEOBENCH has no active CPC or PCW target. See
[MSX2-ONLY.md](MSX2-ONLY.md) for the preservation branch and policy.
