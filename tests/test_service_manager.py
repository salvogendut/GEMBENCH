from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ServicePolicy:
    """Small executable model of the fixed M7 ownership policy."""

    def __init__(self) -> None:
        self.provider_generation = 0
        self.provider_owner: int | None = None
        self.leases: list[tuple[int, int] | None] = [None, None, None]
        self.lease_generation = [0, 0, 0]

    def acquire(self, owner: int, provider: int = 0x0102) -> tuple[str, int]:
        if any(lease and lease[0] == owner for lease in self.leases):
            return "duplicate", 0
        try:
            slot = self.leases.index(None)
        except ValueError:
            return "full", 0
        if self.provider_owner is None:
            self.provider_generation = self.provider_generation % 255 + 1
            self.provider_owner = provider
        self.lease_generation[slot] = self.lease_generation[slot] % 255 + 1
        self.leases[slot] = (owner, self.provider_generation)
        return "ok", self.lease_generation[slot] << 8 | slot + 1

    def validate(self, owner: int, handle: int) -> str:
        slot = (handle & 0xFF) - 1
        if not 0 <= slot < len(self.leases):
            return "stale"
        lease = self.leases[slot]
        if lease is None or self.lease_generation[slot] != handle >> 8:
            return "stale"
        return "ok" if lease[0] == owner else "owner"

    def release(self, owner: int, handle: int) -> str:
        result = self.validate(owner, handle)
        if result == "ok":
            self.leases[(handle & 0xFF) - 1] = None
        return result

    def collect(self, live_owners: set[int]) -> int:
        for index, lease in enumerate(self.leases):
            if lease and lease[0] not in live_owners:
                self.leases[index] = None
        refs = sum(lease is not None for lease in self.leases)
        if refs == 0:
            self.provider_owner = None
        return refs


class ServiceManagerTests(unittest.TestCase):
    def test_bounded_owners_cleanup_and_generations(self) -> None:
        manager = ServicePolicy()
        status_a, handle_a = manager.acquire(0x0101)
        status_b, handle_b = manager.acquire(0x0102)
        status_c, handle_c = manager.acquire(0x0103)
        self.assertEqual((status_a, status_b, status_c), ("ok", "ok", "ok"))
        self.assertEqual(manager.acquire(0x0101)[0], "duplicate")
        self.assertEqual(manager.acquire(0x0104)[0], "full")
        self.assertEqual(manager.validate(0x0102, handle_a), "owner")

        self.assertEqual(manager.collect({0x0101, 0x0103}), 2)
        self.assertEqual(manager.validate(0x0102, handle_b), "stale")
        self.assertEqual(manager.release(0x0103, handle_c), "ok")
        self.assertEqual(manager.release(0x0101, handle_a), "ok")
        self.assertEqual(manager.collect(set()), 0)
        self.assertIsNone(manager.provider_owner)

        status_new, handle_new = manager.acquire(0x0201)
        self.assertEqual(status_new, "ok")
        self.assertNotEqual(handle_new, handle_a)
        self.assertEqual(manager.validate(0x0201, handle_a), "stale")

    def test_fixed_tables_fit_reserved_fsctx_tail(self) -> None:
        text = (ROOT / "lib/gembench/msx_service.h").read_text()

        def number(name: str) -> int:
            match = re.search(rf"#define\s+{name}\s+.*?0x([0-9A-Fa-f]+)u?", text)
            self.assertIsNotNone(match, name)
            return int(match.group(1), 16)

        provider = number("GB_SERVICE_PROVIDER_ADDRESS")
        leases = number("GB_SERVICE_LEASE_ADDRESS")
        lock = number("GB_SERVICE_LOCK_ADDRESS")
        diag = number("GB_SERVICE_DIAG_ADDRESS")
        self.assertEqual((provider, leases, lock, diag),
                         (0xC884, 0xC892, 0xC89E, 0xC89F))
        self.assertEqual(provider + 2 * 7, leases)
        self.assertEqual(leases + 3 * 4, lock)
        self.assertLess(diag, 0xC8A0)  # active native directory cursor begins here

    def test_network_provider_manifest_requires_service_capability(self) -> None:
        manifest = (ROOT / "apps/netsvc/manifest.json").read_text()
        self.assertIn('"application_id": "NETSVC"', manifest)
        self.assertIn('"service-manager"', manifest)
        self.assertIn('"windowless"', manifest)
        self.assertIn('"service"', manifest)


if __name__ == "__main__":
    unittest.main()
