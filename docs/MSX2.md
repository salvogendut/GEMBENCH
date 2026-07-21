# The MSX2 target

The same OS, cross-built for the MSX2 (issue #287). It is **one source tree, two
platforms**: the resident kernel assembles from the same `kernel/` sources under
`-DPLATFORM_MSX`, and the apps compile from the same `main.c` files under
`-DGB_MSX2` — the platform differences live in the kernel's video/input/storage
back-ends, not in the apps.

GEOBENCH on real MSX2 hardware (a 1chipMSX / "1chipbook", 4080K detected): the
desktop with the File Manager, the Viewer showing `PENGUIN.PIC`, and the analog
Clock — all co-resident under the kernel window manager on a V9938 Screen 6.

![GEOBENCH on MSX2 hardware](../screenshots/msx_1chipbook.jpg)

- **Runs under MSX-DOS 2 / Nextor** as a plain `GBMSX.COM` executable — no custom
  boot ROM. Storage goes through BDOS file calls, so anything Nextor mounts
  (Sunrise IDE, SD interfaces, …) works.
- **Video:** V9938 **Screen 6** (512×212, 4 colours) — the closest analogue of the
  CPC's Mode 1 — with a **hardware sprite pointer** and VDP-command drawing
  (`GB_SETINK` palette mapping, `GB_LINE`).
- **Input:** joystick / keyboard pointer, plus the standard **MSX mouse** (GTPAD).
  The clock is 50/60 Hz aware.
- **Ported so far:** Desktop, File Manager, Notepad, Settings, ICONED, Paint,
  Viewer (with portable `.PIC` files translated while drawing), Shell, XAOS, Mahjong,
  Clock, Browser, Telnet, and **all 16 screensavers**. NETTEST and WGET are not
  built for MSX yet.
- **Assets:** icon sets in `assets/iconsets/*.IST` are stored in canonical Mode-1
  bytes and decoded to Screen 6 at runtime by the kernel. Backdrop tiles use the
  same canonical bytes and are converted when loaded. Pictures use the portable [GBPC v2 format](PIC_FORMAT.md):
  the same canonical Mode-1 `.PIC` bytes are staged on every platform and the MSX
  kernel translates them while drawing. MSX pictures live once under root-level `PICS/`;
  development diagnostics such as `GBSPIKE.COM` are kept under `DIAG/`.

Build and test in **openMSX** (emulating a Philips NMS 8250 with the Sunrise IDE
Nextor extension and a 512K RAM expansion):

```bash
bash tools/fetch_msx_deps.sh       # one-time: Nextor system files + NMS 8250 ROMs
bash tools/build_kernel_msx.sh     # GBMSX.COM + QA/MSX staging + bootable QA/GBMSX.IMG
tools/run_msx.sh                   # interactive session
MSX_SHOTS="25 40" tools/run_msx.sh # headless: screenshots into build/msx/
```

`run_msx.sh` uses a native `openmsx` from `$PATH`, the Flatpak
(`org.openmsx.openMSX`) as a fallback, or an explicit `OPENMSX="…"` override.

## Browser and Telnet networking

The MSX Browser and Telnet apps discover a standard **TCP/IP UNAPI**
implementation at runtime. The transport is linked into those app banks; it
does not consume resident kernel headroom. This initial version supports UNAPI
implementations in mapped RAM (through the standard RAM helper) or page 3.
Page-1 ROM-slot implementations are not supported yet. A mapped implementation
uses one mapper segment of its own, so the usual 512K expansion remains the
recommended setup when networking and several windows are used together.

[openMSXnet](https://github.com/antxiko/openMSXnet) is the initial emulator
target. It needs both its custom openMSX build with the `unapinet` extension and
its `UNAPINET.COM` TSR. To produce a local image that installs the TSR before
GEOBENCH:

```bash
MSX_UNAPI_TSR=/path/to/UNAPINET.COM bash tools/build_kernel_msx.sh
```

Then run that image with the openMSXnet executable and data directory:

```bash
OPENMSX=/path/to/openmsxnet/openmsx \
OPENMSX_SYSTEM_DATA=/path/to/openmsxnet/share \
MSX_UNAPI=1 tools/run_msx.sh
```

For openMSXnet, both pieces are mandatory: `UNAPINET.COM` publishes the UNAPI
implementation inside MSX-DOS, while the custom emulator extension provides its
host-side sockets. The normal committed distribution bundles neither third-party
component. On an existing Nextor installation, copy `UNAPINET.COM` to the boot
drive and run it before `GBMSX.COM`; another compatible mapped-RAM or page-3
TCP/IP UNAPI implementation may be used instead. Browser and Telnet report a
network-initialisation error when discovery fails. Browser currently supports
plain HTTP only.
