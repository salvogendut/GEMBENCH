# Development guide

GEOBENCH development targets MSX2 only. Start with [BUILDING.md](BUILDING.md)
and [MSX2-ONLY.md](MSX2-ONLY.md).

## Normal loop

```sh
make check
make geobench-msx
MSX_UNAPI=0 tools/run_msx.sh QA/MSX/GBMSX.IMG
```

Use openMSX as the reference emulator and 1983 for additional development
coverage. Networking needs both a guest TCP/IP UNAPI program and a matching
provider/extension; disable it for unrelated UI checks.

## Applications

Applications are SDCC programs at `0x4000–0x7FFF` and must pass the MSX2 define:

```sh
APPDEFS="-DGB_MSX2" \
  tools/build_capp.sh apps/myapp build/msx/MYAPP.RAW
```

The helper supports opt-in link profiles such as `DOC=1`, `WIDGETS=1`,
`GBR_OBJECTS=1`, `GBR_MENUS=1`, `GB_VDI_BASE=1`, `GB_EVENTS=1`, `GB_SCRAP=1`,
`GB_SHELL_CLIENT=1`, `GB_DEFER=1`, `GB_FSCTX=1`, and `GB_TIMER=1`. Keep each
profile explicit so application size and ownership remain auditable.

Every app must keep loaded code below `DATA_LOC`, data/BSS below `0x8000`, and
the task stack clear. The builder prints and validates these boundaries.

Use `make app APP=mahjong` or `make app APP=calculator` for the registered fast
rebuild paths. A full build is required when kernel, shared modules, assets, or
distribution layout changes.

## Resources

Compile a GBR resource with:

```sh
python3 tools/gbrc.py examples/hello-dialog.json \
  --output build/examples/hello-dialog.gbr
```

Resource schemas use stable numeric IDs. Run `make check` after changes to GBR,
GBAP, ABI, object-tree, form, menu, VDI, scrap, shell, or service code.

Canonical icon/backdrop/title assets remain four-pen packed bytes. This
historical packing is converted by the MSX2 renderer. Screen 7 application icons
may add an adjacent `icon16.asm` resource.

Useful tools include:

- `tools/iconedit.py` for `.IST` and `.SPR` resources;
- `tools/titlebaredit.py` for `.TBR` and `.GDT` themes;
- `tools/picconv.py` and `tools/png2cpc.py --platform msx2` for pictures;
- `tools/genfont.py` for the default font;
- `tools/check_pic_distribution.py` and `tools/check_msx_floppies.py` for media.

## Runtime discipline

- Keep kernel and shared services atomic; preemption is for opted-in pure app
  workers.
- Bound every loop, queue, string, transfer, and per-frame operation.
- Publish generation-tagged owner handles across delayed work.
- Route visual changes through compositor damage; do not repaint covered areas.
- Never retain pointers into a mapper page after switching it out.
- Preserve the frozen GEMBENCH-1 ABI unless a documented version boundary is
  intentionally introduced.

## Tests

`make check` is the required host gate. Targeted openMSX workflows are exposed
as `tools/test_*_openmsx.sh` scripts and matching Make targets for architecture
milestones. The visibility/compositor, timer, Paint, Settings, typed-scrap,
shell, Desk-accessory, shared-service, and GB-BASIC smoke tests exercise real
applications in generated private images.
