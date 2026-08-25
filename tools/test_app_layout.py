#!/usr/bin/env python3
"""Unit tests for the app-bank/task-stack layout guard."""

from __future__ import annotations

import unittest

from check_app_layout import validate_layout


class AppLayoutTests(unittest.TestCase):
    def test_normal_layout_keeps_existing_page_limit(self) -> None:
        areas = {"_CODE": (0x4000, 0x3000), "_DATA": (0x7F00, 0xF0)}
        _, top, _, errors = validate_layout(areas, 0x7F00, 0x7F00, 0)
        self.assertEqual(top, 0x7FF0)
        self.assertEqual(errors, [])

    def test_task_reserve_rejects_data_overlap(self) -> None:
        areas = {"_CODE": (0x4000, 0x3000), "_DATA": (0x7E80, 0x90)}
        _, _, limit, errors = validate_layout(areas, 0x7E80, 0x7F00, 0x100)
        self.assertEqual(limit, 0x7F00)
        self.assertTrue(any("stack snapshot reserve" in error for error in errors))

    def test_task_reserve_accepts_exact_boundary(self) -> None:
        areas = {"_CODE": (0x4000, 0x3000), "_DATA": (0x7E80, 0x80)}
        _, top, limit, errors = validate_layout(areas, 0x7E80, 0x7F00, 0x100)
        self.assertEqual(top, limit)
        self.assertEqual(errors, [])

    def test_loaded_image_cannot_overlap_data(self) -> None:
        areas = {"_CODE": (0x4000, 0x3001), "_DATA": (0x7000, 1)}
        _, _, _, errors = validate_layout(areas, 0x7000, 0x7F00, 0)
        self.assertTrue(any("gsinit/data overlap" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
