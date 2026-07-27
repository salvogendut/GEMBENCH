#!/usr/bin/env python3
"""Focused checks for iconedit.py's host-side drawing operations."""

import random
import sys
import tempfile
import tkinter as tk
from pathlib import Path
from types import SimpleNamespace

from iconedit import (IconEditor, copy_grid_region, flood_fill_grid,
                      load_asm_icon, normalize_rect, pasted_grid,
                      save_asm_icon, spray_points)


def test_normalize_rect():
    assert normalize_rect(7, 5, 2, 1) == (2, 1, 7, 5)


def test_flood_fill():
    grid = [
        [0, 0, 1],
        [0, 1, 1],
        [2, 2, 1],
    ]
    changed = flood_fill_grid(grid, 0, 0, 3)
    assert set(changed) == {(0, 0), (1, 0), (0, 1)}
    assert grid == [
        [3, 3, 1],
        [3, 1, 1],
        [2, 2, 1],
    ]
    assert flood_fill_grid(grid, 0, 0, 3) == []


def test_spray_points():
    first = spray_points(8, 6, 0, 0, random.Random(7),
                         radius=2, drops=40)
    second = spray_points(8, 6, 0, 0, random.Random(7),
                          radius=2, drops=40)
    assert first == second
    assert (0, 0) in first
    assert len(first) > 1
    assert all(0 <= x < 8 and 0 <= y < 6 for x, y in first)
    assert all(x * x + y * y <= 4 for x, y in first)


def test_region_copy_and_paste():
    source = [
        [0, 1, 2, 3],
        [3, 2, 1, 0],
        [1, 1, 2, 2],
    ]
    copied = copy_grid_region(source, (3, 2, 1, 1))
    assert copied == {
        "pixel_w": 3,
        "h": 2,
        "grid": [
            [2, 1, 0],
            [1, 2, 2],
        ],
    }

    target = [[0] * 4 for _ in range(3)]
    payload = {
        "grid": [
            [1, 15, 2],
            [3, -2, 1],
        ],
    }
    result, bounds = pasted_grid(target, payload, 2, 1, max_pen=3)
    assert target == [[0] * 4 for _ in range(3)]
    assert result == [
        [0, 0, 0, 0],
        [0, 0, 1, 3],
        [0, 0, 3, 0],
    ]
    assert bounds == (2, 1, 3, 2)

    unchanged, same_bounds = pasted_grid(result, payload, 2, 1, max_pen=3)
    assert unchanged is result
    assert same_bounds == bounds


def test_long_asm_label_spacing():
    icon = {
        "w": 8,
        "h": 32,
        "codec": 1,
        "grid": [[0] * 32 for _ in range(32)],
    }
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "icon.asm"
        save_asm_icon(path, [icon], "icon_iconeditor")
        text = path.read_text(encoding="ascii")
        assert "icon_iconeditor_w equ" in text
        loaded, label = load_asm_icon(path)
        assert label == "icon_iconeditor"
        assert loaded == [icon]


def _cell_event(editor, x, y):
    icon = editor._cur()
    ox, oy = editor._origin(icon)
    return SimpleNamespace(
        x=ox + x * editor.scale + editor.scale // 2,
        y=oy + y * editor.scale + editor.scale // 2,
    )


def _drag(editor, tool, start, end):
    editor._select_tool(tool)
    editor._on_press(_cell_event(editor, *start))
    editor._on_drag(_cell_event(editor, *end))
    editor._on_release(_cell_event(editor, *end))


def test_tk_toolchest():
    """Exercise the real Tk controls and mouse-event drawing path under Xvfb."""
    root = tk.Tk()
    root.withdraw()
    editor = IconEditor(root)
    editor.update()
    assert set(editor.tool_buttons) == {
        "circle_fill", "circle", "rect_fill", "rect",
        "pen", "line", "erase", "bucket", "spray",
        "undo", "select", "copy", "paste",
    }

    editor._select_pen(2)
    _drag(editor, "rect_fill", (1, 1), (3, 3))
    assert all(editor.icons[0]["grid"][y][x] == 2
               for y in range(1, 4) for x in range(1, 4))
    editor.undo()
    assert not any(any(row) for row in editor.icons[0]["grid"])

    _drag(editor, "line", (0, 0), (4, 4))
    assert all(editor.icons[0]["grid"][p][p] == 2 for p in range(5))
    editor.undo()
    assert not any(any(row) for row in editor.icons[0]["grid"])

    _drag(editor, "rect", (1, 1), (5, 5))
    editor._select_pen(3)
    editor._select_tool("bucket")
    editor._on_press(_cell_event(editor, 3, 3))
    assert editor.icons[0]["grid"][3][3] == 3
    assert editor.icons[0]["grid"][1][1] == 2
    assert editor.icons[0]["grid"][0][0] == 0

    _drag(editor, "select", (1, 1), (3, 3))
    editor.copy_icon()
    assert editor.clipboard_icon["kind"] == "selection"
    assert editor.clipboard_icon["pixel_w"] == 3
    assert editor.clipboard_icon["h"] == 3
    editor.selection = (8, 8, 8, 8)
    editor.paste_icon()
    assert editor.icons[0]["grid"][8][8] == 2
    assert editor.icons[0]["grid"][9][9] == 3

    editor.close_window()


def main():
    tests = [
        test_normalize_rect,
        test_flood_fill,
        test_spray_points,
        test_region_copy_and_paste,
        test_long_asm_label_spacing,
    ]
    for test in tests:
        test()
        print(f"ok   {test.__name__}")
    if "--tk-smoke" in sys.argv:
        test_tk_toolchest()
        print("ok   test_tk_toolchest")
    print("\nall icon editor tool tests passed")


if __name__ == "__main__":
    main()
