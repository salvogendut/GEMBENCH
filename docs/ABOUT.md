# About GEMBENCH

GEMBENCH is a native graphical desktop and application environment for MSX2.
It evolves the GeoBench Z80 foundation with interaction and architecture ideas
associated with Digital Research GEM while retaining its own ABI, file formats,
BSD-licensed implementation, and original artwork.

It is not an x86 GEM emulator, an AES compatibility layer, or a loader for
historical GEM applications.

## Hardware model

- Z80 at the normal MSX2 clock
- V9938 or V9958 with 128 KiB VRAM
- Screen 6 or Screen 7; Screen 7 is the GEMBENCH visual baseline
- at least 512 KiB mapper RAM
- MSX-DOS 2 or Nextor storage services
- keyboard, joystick, or MSX mouse input
- TCP/IP UNAPI networking when a provider is installed

GEMBENCH is MSX2-only. CPC and PCW support stopped on 31 August 2026; the last
multi-platform tree is retained on `archive/cpc-pcw-targets`. Details are in
[MSX2-ONLY.md](MSX2-ONLY.md).

## System shape

The resident Z80 kernel owns video, input, storage, windows, the compositor,
mapper pages, and a fixed jump-table API at `0x8000`. SDCC applications occupy
a mapper page at `0x4000–0x7FFF` and call the kernel through `lib/gb`.

Applications can own several windows, secondary mapper resources, filesystem
contexts, deferred endpoints, shared-service leases, timers, and typed scrap.
The scheduler prioritizes the focused application, runs visible background
workers at lower priority, and parks fully covered visual workers. The global
compositor emits only visible damage and clips repaint callbacks to exposed
regions.

GEMBENCH packages both its Paint variant and GB-BASIC in-tree. The standard
build therefore does not depend on sibling source repositories.

## Visual direction

The default desktop uses black, white, grey, and red. Screen 7 permits richer
application artwork while retaining semantic UI pens and the four-colour base.
The GEMBENCH kernel mark and desktop logo replace inherited GeoBench branding.

## Project layout

```text
apps/                  MSX2 applications and screensavers
assets/                canonical and MSX2-native visual assets
components/gb-basic/   bundled editor, interpreter, engine, and examples
include/gembench/      public GEMBENCH resource/application interfaces
kernel/                resident Z80 kernel and modules
lib/gb/                application ABI and C/assembly bindings
lib/gembench/          GEM-like resources and services
lib/msx/               V9938, input, mapper, and MSX-DOS backends
QA/MSX/                committed release staging and floppy images
tools/                 MSX2 build, validation, asset, and emulator tools
```

## License

GEMBENCH uses the BSD 3-Clause License. GEM and SymbOS are behavioural and
architectural references only; code and art must be independently implemented
unless separately reviewed material has compatible licensing and provenance.
