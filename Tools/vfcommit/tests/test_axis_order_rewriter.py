"""Tests for STAT DesignAxisRecord ensure + reorder."""

from __future__ import annotations

import unittest

from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables.otTables import AxisRecord, AxisRecordArray

from vfcommit_lib.axis_order_rewriter import _ensure_design_axes, reorder_axis_tables


def _make_font_with_stat(tags: list[str]) -> TTFont:
    font = TTFont()
    stat = newTable("STAT")
    stat.Version = 0x00010002
    arr = AxisRecordArray()
    arr.Axis = []
    for index, tag in enumerate(tags):
        rec = AxisRecord()
        rec.AxisTag = tag
        rec.AxisNameID = 256 + index
        rec.AxisOrdering = index
        arr.Axis.append(rec)
    stat.DesignAxisRecord = arr
    font["STAT"] = stat
    return font


class AxisOrderRewriterTests(unittest.TestCase):
    def test_ensure_appends_missing_design_axis(self) -> None:
        font = _make_font_with_stat(["wght"])
        appended = _ensure_design_axes(font, ["wght", "ital"])
        self.assertEqual(appended, ["ital"])
        tags = [ax.AxisTag for ax in font["STAT"].DesignAxisRecord.Axis]
        self.assertEqual(tags, ["wght", "ital"])
        ital = font["STAT"].DesignAxisRecord.Axis[1]
        self.assertEqual(ital.AxisTag, "ital")
        self.assertEqual(ital.AxisNameID, 0)

    def test_reorder_puts_request_order_first(self) -> None:
        font = _make_font_with_stat(["wght", "opsz"])
        reorder_axis_tables(font, design_axis_tags=["opsz", "wght", "ital"])
        tags = [ax.AxisTag for ax in font["STAT"].DesignAxisRecord.Axis]
        self.assertEqual(tags[:3], ["opsz", "wght", "ital"])


if __name__ == "__main__":
    unittest.main()
