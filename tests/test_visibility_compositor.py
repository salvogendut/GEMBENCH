from __future__ import annotations

import random
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
Rect = tuple[int, int, int, int]


def pixels(rect: Rect) -> set[tuple[int, int]]:
    x, y, w, h = rect
    return {(px, py) for py in range(y, y + h) for px in range(x, x + w)}


def visible_fragments(base: Rect, covers: list[Rect]) -> list[Rect]:
    """Reference model of M9's horizontal-band rectangle iterator."""
    x, y, w, h = base
    right, bottom = x + w, y + h
    edges = {y, bottom}
    for cx, cy, cw, ch in covers:
        if cx < right and cx + cw > x and cy < bottom and cy + ch > y:
            edges.add(max(y, cy))
            edges.add(min(bottom, cy + ch))
    ordered = sorted(edges)
    fragments: list[Rect] = []
    for top, band_bottom in zip(ordered, ordered[1:]):
        run = None
        for px in range(x, right + 1):
            covered = px == right or any(
                cx <= px < cx + cw and cy <= top < cy + ch
                for cx, cy, cw, ch in covers
            )
            if not covered and run is None:
                run = px
            elif covered and run is not None:
                fragments.append((run, top, px - run, band_bottom - top))
                run = None
    return fragments


def move_endpoint_envelope(old: Rect, new: Rect) -> Rect:
    """Damage needed by the destructive outline between two move endpoints."""
    ox, oy, w, h = old
    nx, ny, nw, nh = new
    if (nw, nh) != (w, h):
        raise ValueError("a move must not resize its window")
    left, top = min(ox, nx), min(oy, ny)
    return (left, top, max(ox, nx) + w - left, max(oy, ny) + h - top)


class VisibilityCompositorTests(unittest.TestCase):
    def test_band_fragments_equal_exact_pixel_subtraction(self) -> None:
        rng = random.Random(0x47)
        for _ in range(500):
            base = (rng.randrange(0, 16), rng.randrange(0, 12),
                    rng.randrange(1, 17), rng.randrange(1, 13))
            covers = [(rng.randrange(0, 32), rng.randrange(0, 24),
                       rng.randrange(1, 17), rng.randrange(1, 13))
                      for _ in range(rng.randrange(0, 8))]
            expected = pixels(base)
            for cover in covers:
                expected -= pixels(cover)
            actual: set[tuple[int, int]] = set()
            for fragment in visible_fragments(base, covers):
                part = pixels(fragment)
                self.assertFalse(actual & part, "fragments must be disjoint")
                actual |= part
            self.assertEqual(actual, expected)

    def test_move_damage_covers_the_endpoint_sweep(self) -> None:
        cases = [
            ((10, 10, 20, 15), (15, 13, 20, 15)),
            ((10, 10, 20, 15), (0, 0, 20, 15)),
            ((0, 0, 8, 8), (20, 20, 8, 8)),
            ((10, 10, 20, 15), (10, 10, 20, 15)),
        ]
        for old, new in cases:
            damage = pixels(move_endpoint_envelope(old, new))
            self.assertTrue(pixels(old) <= damage)
            self.assertTrue(pixels(new) <= damage)

            # Every outline whose top-left stays between the two endpoints is
            # repaired, including the intermediate route that crosses content
            # outside the disjoint old/new union.
            min_x, max_x = sorted((old[0], new[0]))
            min_y, max_y = sorted((old[1], new[1]))
            for x in range(min_x, max_x + 1):
                for y in range(min_y, max_y + 1):
                    self.assertTrue(pixels((x, y, old[2], old[3])) <= damage)

    def test_focus_sources_repaint_complete_old_and_new_windows(self) -> None:
        cases: list[tuple[Rect | None, Rect | None]] = [
            ((8, 12, 24, 30), (48, 10, 18, 24)),
            ((8, 12, 24, 30), (20, 20, 24, 30)),
            (None, (48, 10, 18, 24)),       # desktop -> application
            ((8, 12, 24, 30), None),        # application -> desktop
        ]
        for old, new in cases:
            primary_rect = new if new is not None else old
            self.assertIsNotNone(primary_rect)
            primary = pixels(primary_rect)
            remainder: set[tuple[int, int]] = set()
            if old is not None and new is not None:
                for fragment in visible_fragments(old, [new]):
                    remainder |= pixels(fragment)
            self.assertFalse(primary & remainder)
            expected = set()
            if old is not None:
                expected |= pixels(old)
            if new is not None:
                expected |= pixels(new)
            self.assertEqual(primary | remainder, expected)

    def test_fixed_layout_and_global_hook(self) -> None:
        glue = (ROOT / "lib/msx/glue.inc").read_text()
        expected = {
            "MSX_WM_VISIBILITY": 0xC1C0,
            "MSX_TASK_VISIBILITY": 0xC1C8,
            "MSX_COMPOSITOR_DAMAGE": 0xC1E8,
            "MSX_COMPOSITOR_EXTRA": 0xC1ED,
            "MSX_COMPOSITOR_SOURCE": 0xC1F3,
            "MSX_PAGE_NATIVE": 0xC200,
            "MSX_APP_FIXED_BOTTOM": 0xD400,
        }
        for symbol, address in expected.items():
            match = re.search(rf"^{symbol}\s+equ\s+#([0-9A-Fa-f]+)",
                              glue, re.MULTILINE)
            self.assertIsNotNone(match, symbol)
            self.assertEqual(int(match.group(1), 16), address)

        kernel = (ROOT / "kernel/gbkern.asm").read_text()
        scheduler = (ROOT / "kernel/scheduler.asm").read_text()
        regions = (ROOT / "kernel/core/visible_regions.asm").read_text()
        visibility = (ROOT / "kernel/core/window_visibility.asm").read_text()
        provider = (ROOT / "kernel/msx_visibility.inc").read_text()
        paint_provider = (ROOT / "kernel/msx_window_damage.inc").read_text()
        repaint = (ROOT / "kernel/core/window_repaint.asm").read_text()
        geometry = (ROOT / "kernel/core/window_geometry.asm").read_text()
        builder = (ROOT / "tools/build_kernel_msx.sh").read_text()
        self.assertIn('include "core/window_repaint.asm"', kernel)
        self.assertIn("PAINT_REGION_BEGIN equ SCHED_REGION_BEGIN_ENTRY", paint_provider)
        self.assertIn("PAINT_REGION_NEXT equ SCHED_REGION_NEXT_ENTRY", paint_provider)
        self.assertIn("call  PAINT_REGION_BEGIN", repaint)
        self.assertIn("call  PAINT_REGION_NEXT", repaint)
        self.assertIn("fully occluded: no callback", repaint)
        self.assertIn('include "core/visible_regions.asm"', scheduler)
        self.assertIn('include "core/window_visibility.asm"', scheduler)
        self.assertIn("sched_visibility_refresh", visibility)
        self.assertIn("sched_region_prepare_band", regions)
        self.assertIn("MSX_TASK_VISIBILITY", provider)
        self.assertIn('include "core/window_geometry.asm"', kernel)
        self.assertIn("call  damage_axis", geometry)
        self.assertIn("envelope covers the destructive rubber-band path", geometry)
        self.assertIn('include "core/window_focus_click.asm"', kernel)
        focus = (ROOT / "kernel/core/window_focus_click.asm").read_text()
        self.assertIn("exact old/new focus-window union", focus)
        self.assertNotIn("MSX_FOCUS_DAMAGE_PENDING", kernel + scheduler + glue)
        self.assertNotIn("GB_REGIONS=1", builder)


if __name__ == "__main__":
    unittest.main()
