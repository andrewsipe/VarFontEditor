"""Round-trip write tests — vfcommit writes then fontTools re-opens."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from fontTools.ttLib import TTFont

from vfcommit_lib.engine import run_commit
from vfcommit_lib.request_bridge import instance_key

_FIXTURE = (
    Path(__file__).resolve().parents[3]
    / "fixtures"
    / "examples"
    / "playfair-roman-commit-request.json"
)

_PLAYFAIR_CANDIDATES = [
    Path.home() / "Downloads" / "PlayfairRomanVF.woff2",
    Path.home() / "Downloads" / "~Untitled" / "PlayfairRomanVF.woff2",
]


def _resolve_playfair() -> Path | None:
    for candidate in _PLAYFAIR_CANDIDATES:
        if candidate.is_file():
            return candidate
    return None


class RoundTripWriteTests(unittest.TestCase):
    def _base_request(self) -> dict:
        if not _FIXTURE.is_file():
            self.skipTest("fixture missing")
        source = _resolve_playfair()
        if source is None:
            self.skipTest("Playfair Roman VF not on disk — see fixtures/fonts/README.md")
        request = json.loads(_FIXTURE.read_text(encoding="utf-8"))
        request["source_path"] = str(source)
        return request

    def test_write_and_reopen_fvar_count(self) -> None:
        request = self._base_request()
        expected_instances = 8  # 2 x 2 x 2 from minimal fixture axes

        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "PlayfairRomanVF-patched.woff2"
            request["output_path"] = str(output)
            request["dry_run"] = False
            result = run_commit(request)
            self.assertTrue(result.get("ok"), result.get("errors"))
            self.assertTrue(output.is_file())

            font = TTFont(str(output))
            self.assertIn("fvar", font)
            self.assertEqual(len(font["fvar"].instances), expected_instances)
            self.assertEqual(result["summary"]["instances_written"], expected_instances)

    def test_exclude_instances_reduces_fvar_count(self) -> None:
        request = self._base_request()
        # Drop all combos where opsz=5 (Micro) — 4 instances remain from 2x2x2 grid
        grid_tags = ["opsz", "wdth", "wght"]
        excluded_opsz = 5.0
        keys = []
        for opsz in [5, 12]:
            for wdth in [88, 100]:
                for wght in [400, 700]:
                    coords = {
                        "opsz": float(opsz),
                        "wdth": float(wdth),
                        "wght": float(wght),
                    }
                    if coords["opsz"] != excluded_opsz:
                        keys.append(instance_key(coords))
        request["included_instance_keys"] = keys

        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "PlayfairRomanVF-pruned.woff2"
            request["output_path"] = str(output)
            request["dry_run"] = False
            result = run_commit(request)
            self.assertTrue(result.get("ok"), result.get("errors"))
            font = TTFont(str(output))
            self.assertEqual(len(font["fvar"].instances), len(keys))
            self.assertEqual(result["summary"]["instances_written"], len(keys))

    def test_rename_stop_reflected_in_stat_name(self) -> None:
        request = self._base_request()
        for axis in request["axes"]:
            if axis["tag"] == "wght":
                for stop in axis["values"]:
                    if stop["value"] == 700:
                        stop["name"] = "Heavy"

        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "PlayfairRomanVF-renamed.woff2"
            request["output_path"] = str(output)
            request["dry_run"] = False
            result = run_commit(request)
            self.assertTrue(result.get("ok"), result.get("errors"))
            font = TTFont(str(output))
            stat = font["STAT"].table
            value_names = []
            axis_values = getattr(stat, "DesignAxisValueArray", None) or getattr(stat, "AxisValueArray", None)
            records = getattr(axis_values, "AxisValue", []) if axis_values else []
            for record in records:
                if hasattr(record, "ValueNameID"):
                    nid = record.ValueNameID
                    for rec in font["name"].names:
                        if rec.nameID == nid:
                            value_names.append(rec.toUnicode())
            self.assertIn("Heavy", value_names)


if __name__ == "__main__":
    unittest.main()
