# About GEOBENCH

GEOBENCH is a native graphical desktop and application environment for Z80
machines, with a production MSX2 target and an experimental CPC reference
port. It combines its Z80 foundation with interaction and architecture ideas
associated with Digital Research GEM while retaining its own ABI, file formats,
BSD-licensed implementation, and original artwork.

It is not an x86 GEM emulator, an AES compatibility layer, or a loader for
historical GEM applications.

## Hardware model

- Z80 at the normal MSX2 clock
- V9938 or V9958 with 128 KiB VRAM
- Screen 6 or Screen 7; Screen 7 is the primary visual baseline
- at least 512 KiB mapper RAM
- MSX-DOS 2 or Nextor storage services
- keyboard, joystick, or MSX mouse input
- TCP/IP UNAPI networking when a provider is installed

The current release remains MSX2. CPC Gate 3 now supplies a 512 KiB Mode-1
reference build around one compile-once native application ABI; PCW remains on
the archived multi-platform tree at `archive/cpc-pcw-targets` until Gate 5.
See [MSX2-ONLY.md](MSX2-ONLY.md) and the
[universal ABI proposal](UNIVERSAL-APPLICATION-ABI.md).

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

GEOBENCH packages both its Paint variant and GB-BASIC in-tree. The standard
build therefore does not depend on sibling source repositories.

## Visual direction

The default desktop uses the canonical GEOBENCH blue, white, black, and red
logical pens. Screen 7 permits richer application artwork while retaining
those semantic UI roles. The lollipop mark supplies the boot splash, wallpaper,
and kernel/module icon.

## Project layout

```text
apps/                  MSX2 applications and screensavers
assets/                canonical and target-native visual assets
components/gb-basic/   bundled editor, interpreter, engine, and examples
include/gembench/      frozen resource/application interface namespace
kernel/                resident Z80 kernel and modules
lib/gb/                application ABI and C/assembly bindings
lib/gembench/          GEM-like resources and services
lib/msx/               V9938, input, mapper, and MSX-DOS backends
QA/MSX/                committed release staging and floppy images
QA/CPC/                experimental CPC card and floppy staging
tools/                 build, validation, asset, and emulator tools
```

## License

GEOBENCH uses the BSD 3-Clause License. GEM and SymbOS are behavioural and
architectural references only; code and art must be independently implemented
unless separately reviewed material has compatible licensing and provenance.
