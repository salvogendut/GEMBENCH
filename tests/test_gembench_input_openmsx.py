from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from debug import gembench_input_openmsx as input_probe


VALID_RESULT = """\
STATUS=PASS
POINTER_RESPONSE_MS=86.290
KEYBOARD_RESPONSE_MS=56.967
POINTER_BEFORE_X=127
POINTER_BEFORE_Y=104
POINTER_AFTER_X=126
POINTER_AFTER_Y=104
INPUT_FLAGS=7
INPUT_KEY=98
RUNNABLE_TASKS=3
STACK_MAX=32
STACK_FAULT=0
PROBE_PHASE=4
POINTER_ARM_TICK=1880
POINTER_ACK_TICK=1885
KEYBOARD_ARM_TICK=1880
KEYBOARD_ACK_TICK=1890
"""


class OpenMsxInputProbeTests(unittest.TestCase):
    def parse(self, contents: str) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.log"
            path.write_text(contents, encoding="ascii")
            return input_probe.parse_result(path)

    def test_parse_result_accepts_complete_visible_responses(self) -> None:
        result = self.parse(VALID_RESULT)

        self.assertEqual(result["input_flags"], 7)
        self.assertEqual(result["input_key"], ord("b"))
        self.assertEqual(result["pointer_response_ms"], 86.290)
        self.assertEqual(result["keyboard_response_ms"], 56.967)

    def test_parse_result_rejects_pointer_without_visible_motion(self) -> None:
        result = VALID_RESULT.replace("POINTER_AFTER_X=126", "POINTER_AFTER_X=127")

        with self.assertRaisesRegex(input_probe.InputProbeError, "did not visibly move"):
            self.parse(result)


if __name__ == "__main__":
    unittest.main()
