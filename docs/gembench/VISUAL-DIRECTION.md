# GEMBENCH visual direction

Status: **base direction fixed on 2026-08-28**.

GEMBENCH uses a pixel-native, late-1980s industrial visual language derived
from the repository's three logo concepts. It favours hard geometry, strong
negative space, bright keylines, and deliberate checker or ordered dithering.
Soft gradients and antialiased edges in the large concept art are references
for value and shape; target assets reduce them to crisp palette entries.

## Base palette

The GEMBENCH MSX2 interface must remain coherent with four logical pens:

| Pen | Role | CPC ink | Reference RGB | Intended use |
| ---: | --- | ---: | --- | --- |
| 0 | Canvas | 0 | `#000000` | Desktop, window work areas, overscan border, negative space |
| 1 | Light | 26 | `#FFFFFF` | Primary text, highlights, bright icon planes |
| 2 | Structure | 13 | `#929292` | Frames, shadows, secondary text, control depth |
| 3 | Accent | 6 | `#FF0000` | Focus, selection, active controls, alerts, signature planes |

Black is the default background and border. Red should identify state or
structure rather than become a second background. White carries primary
legibility; grey supplies depth without introducing a blue cast.

Screen 7 retains palette entries 4-15 for native pictures, richer icons, and
future semantic roles. Core controls and focus indication must remain readable
using entries 0-3 alone, and focus must not rely on colour without a shape,
outline, or inversion change.

## Logo references

- `assets/GEMBENCH_ORIGINAL_LOGO.png` is the detailed mood board: faceted red
  geometry, metallic grey structure, bright white highlights, and checker
  texture.
- `assets/GEMBENCH_LOGO.png` is the cleaner wordmark and desktop-wallpaper
  source. Its simplified silhouette survives reduction to the four-pen target.
- `assets/GEMBENCH_KERNEL.png` is the compact emblem and boot-splash source.

These are original GEMBENCH assets and remain source references. Conversion to
target formats must be deterministic and should preserve the black silhouette,
white keyline, red mass, and sparse grey depth before considering extra Screen
7 colours.

## Scope

This direction applies to GEMBENCH's fixed MSX2 target. The inherited CPC and
PCW compatibility builds retain their existing palettes, assets, and defaults.
Shared source must gate visual changes on the MSX2 target so this branch does
not silently retheme those distributions.

## Interface rules

- Use black for the persistent desktop canvas and uncluttered work areas.
- Use white for primary labels and the brightest one-pixel edges.
- Use grey for inactive structure, shadows, separators, and secondary detail.
- Use red for focus, selection, pressed state, and a small number of strong
  chrome accents.
- Prefer one-pixel outlines, square corners, geometric facets, and explicit
  checker/ordered dithering over simulated smooth shading.
- Keep text contrast measurable in the four-colour base before adding Screen 7
  embellishment.

The first rollout changes the MSX2 kernel/config defaults, adds opt-in asset tooling,
uses the compact emblem during boot, and derives the default wallpaper from the
clean wordmark. Native sixteen-colour UI roles remain a later measured step.
