#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import gen_desk_accessories as catalog  # noqa: E402


class DeskAccessoryCatalogTests(unittest.TestCase):
    def write(self, root: Path, value: object) -> Path:
        path = root / "catalog.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_release_catalog_matches_generated_header(self) -> None:
        capacity, entries = catalog.load_catalog(
            ROOT / "apps" / "desktop" / "accessories.json"
        )
        rendered = catalog.render_header(capacity, entries)
        self.assertEqual(
            rendered,
            (ROOT / "include" / "gembench" / "gbdesk_catalog.h").read_text(
                encoding="utf-8"
            ),
        )
        self.assertEqual([entry["id"] for entry in entries], [1, 2])
        self.assertEqual(
            [entry["app11"] for entry in entries], ["CLOCK   APP", "CALC    APP"]
        )

    def test_capacity_is_a_hard_limit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = self.write(
                Path(directory),
                {
                    "capacity": 1,
                    "accessories": [
                        {"symbol": "A", "id": 1, "label": "A", "app": "A.APP"},
                        {"symbol": "B", "id": 2, "label": "B", "app": "B.APP"},
                    ],
                },
            )
            with self.assertRaisesRegex(catalog.CatalogError, "capacity"):
                catalog.load_catalog(source)

    def test_duplicate_ids_and_apps_are_rejected(self) -> None:
        for field, value, message in (
            ("id", 1, "duplicate accessory id"),
            ("app", "A.APP", "duplicate accessory app"),
        ):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                second = {"symbol": "B", "id": 2, "label": "B", "app": "B.APP"}
                second[field] = value
                source = self.write(
                    Path(directory),
                    {
                        "capacity": 2,
                        "accessories": [
                            {"symbol": "A", "id": 1, "label": "A", "app": "A.APP"},
                            second,
                        ],
                    },
                )
                with self.assertRaisesRegex(catalog.CatalogError, message):
                    catalog.load_catalog(source)

    def test_id_zero_and_non_app_names_are_rejected(self) -> None:
        for identity, app, message in (
            (0, "A.APP", "must be in 1..255"),
            (1, "A.ACC", "must be an uppercase"),
        ):
            with self.subTest(identity=identity, app=app), tempfile.TemporaryDirectory() as directory:
                source = self.write(
                    Path(directory),
                    {
                        "capacity": 1,
                        "accessories": [
                            {"symbol": "A", "id": identity, "label": "A", "app": app}
                        ],
                    },
                )
                with self.assertRaisesRegex(catalog.CatalogError, message):
                    catalog.load_catalog(source)


if __name__ == "__main__":
    unittest.main()
