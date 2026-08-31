# GEOBENCH visual identity

Status: **restored from the canonical GEOBENCH tree on 2026-08-31**.

GEOBENCH uses its original pixel-native lollipop identity and four logical
desktop pens. The source of truth is the clean sibling checkout `../geobench`
at commit `c6728bb0b2656c651636fb18c8d5773f8adb832a`.

## Base palette

| Pen | Role | CPC ink | Reference RGB | Intended use |
| ---: | --- | ---: | --- | --- |
| 0 | Desktop | 1 | `#000080` | Desktop, backdrop, ordinary blue surfaces |
| 1 | Light | 26 | `#FFFFFF` | Text, highlights, bright icon planes |
| 2 | Dark | 0 | `#000000` | Outlines, title bars, shadows, dark app canvases |
| 3 | Accent | 6 | `#FF0000` | Focus, selection, active controls, alerts |

The default `INKS=` value is `1,26,0,6,1`: the four UI pens followed by the
blue border. Screen 7 retains entries 4–15 for native pictures and richer app
artwork; core controls must remain readable using entries 0–3.

VDI-lite calls these roles canvas, surface, edge, and accent. Those semantic
names remain useful even though the restored palette is blue/white/black/red.

## Identity assets

- `logo.png` is the full GEOBENCH lollipop wordmark used by the repository.
- `assets/SPLASH.png` is the compact lollipop source used by the boot splash.
- `assets/pictures/LOGO.PIC` is the canonical desktop wallpaper.
- `lib/icon_geobench.asm` supplies the lollipop icon for the kernel and `.MOD`
  files through the default icon set.

The build stages these canonical assets directly. There is no target-specific
wallpaper override or alternate black-background splash pipeline.

## Compatibility history

The black/white/grey/red GEMBENCH identity and its gem-shaped logo are preserved
on `archive/gembench-msx2-identity`. The frozen `GEMBENCH-1` ABI name and the
`include/gembench/`, `lib/gembench/`, and `docs/gembench/` paths remain as
technical compatibility identifiers; they do not define the public product
name or visual identity.
