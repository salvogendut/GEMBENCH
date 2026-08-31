from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class TimerMailbox:
    """Executable model of the single coalesced M8 damage mailbox."""

    def __init__(self) -> None:
        self.owner_slot = 0
        self.generation = 0
        self.rect = (0, 0, 0, 0)
        self.dropped_slot = 0

    def publish(self, slot: int, generation: int,
                rect: tuple[int, int, int, int]) -> bool:
        if self.owner_slot or not rect[2] or not rect[3]:
            return False
        self.rect = rect
        self.generation = generation
        self.owner_slot = slot + 1  # publish identity last
        return True

    def collect(self, live: dict[int, int], visible: bool = True
                ) -> tuple[int, int, int, int] | None:
        if not self.owner_slot:
            return None
        if self.owner_slot & 0x80:  # recursive Desktop callback during consume
            return None
        slot = self.owner_slot - 1
        if live.get(slot) != self.generation:
            self.owner_slot = 0
            return None
        if not visible:
            self.dropped_slot = self.owner_slot
            self.owner_slot = 0
            return None
        snapshot = self.rect  # owner remains published while the root snapshots
        self.owner_slot |= 0x80  # retain the active source through callbacks
        return snapshot

    def finish(self) -> None:
        self.owner_slot = 0


class BackgroundTimerTests(unittest.TestCase):
    def test_coalescing_snapshot_and_republish(self) -> None:
        mailbox = TimerMailbox()
        first = (24, 20, 28, 122)
        second = (10, 12, 20, 90)
        self.assertTrue(mailbox.publish(2, 7, first))
        self.assertFalse(mailbox.publish(2, 7, second))
        self.assertEqual(mailbox.collect({2: 7}), first)
        self.assertEqual(mailbox.owner_slot, 0x83)
        self.assertIsNone(mailbox.collect({2: 7}))
        self.assertEqual(mailbox.owner_slot, 0x83)
        self.assertFalse(mailbox.publish(2, 7, second))
        mailbox.finish()
        self.assertTrue(mailbox.publish(2, 7, second))
        self.assertEqual(mailbox.collect({2: 7}), second)
        mailbox.finish()

    def test_close_and_slot_reuse_reject_stale_damage(self) -> None:
        mailbox = TimerMailbox()
        self.assertTrue(mailbox.publish(2, 7, (24, 20, 28, 122)))
        self.assertIsNone(mailbox.collect({2: 8}))
        self.assertEqual(mailbox.owner_slot, 0)

    def test_fully_occluded_component_is_acknowledged_without_paint(self) -> None:
        mailbox = TimerMailbox()
        self.assertTrue(mailbox.publish(2, 7, (40, 126, 3, 8)))
        self.assertIsNone(mailbox.collect({2: 7}, visible=False))
        self.assertEqual(mailbox.owner_slot, 0)
        self.assertEqual(mailbox.dropped_slot, 3)

    def test_fixed_layout_and_build_guards(self) -> None:
        glue = (ROOT / "lib/msx/glue.inc").read_text()
        expected = {
            "MSX_TIMER_OWNER": 0xC3CA,
            "MSX_TIMER_RECT": 0xC3CB,
            "MSX_TIMER_GEN": 0xC3CF,
            "MSX_TIMER_DROPPED": 0xC1EC,
        }
        for symbol, address in expected.items():
            match = re.search(rf"^{symbol}\s+equ\s+#([0-9A-Fa-f]+)",
                              glue, re.MULTILINE)
            self.assertIsNotNone(match, symbol)
            self.assertEqual(int(match.group(1), 16), address)

        builder = (ROOT / "tools/build_capp.sh").read_text()
        self.assertIn('GB_TIMER=1 requires TASK=1', builder)
        self.assertIn('GB_TIMER_COLLECTOR=1 requires TASK_ROOT=1', builder)
        self.assertIn('background application timers are currently MSX2-only',
                      builder)


if __name__ == "__main__":
    unittest.main()
