"""Tests for naming-order alignment between Swift editor and vfcommit."""

from __future__ import annotations

import unittest

from vfcommit_lib.nameid_allocator import (
    CODE_TOKEN,
    PSHYPHEN_TOKEN,
    AxisValueDef,
    compose_name_from_order,
    naming_order_with_defaults,
)


class NamingOrderTests(unittest.TestCase):
    def test_does_not_auto_append_clarifier_tokens(self) -> None:
        order = naming_order_with_defaults({"order": ["wght", "ital"]})
        self.assertIn(PSHYPHEN_TOKEN, order)
        self.assertIn("wght", order)
        self.assertIn("ital", order)
        self.assertNotIn("@width", order)
        self.assertNotIn("@slope", order)
        self.assertNotIn("@optical", order)
        self.assertNotIn("@custom", order)

    def test_leftover_clarifiers_not_composed_without_tokens(self) -> None:
        axes_json = [
            {
                "tag": "wght",
                "role": "instance",
                "values": [{"value": 400, "name": "Regular", "elidable": True}],
            },
            {
                "tag": "ital",
                "role": "design_record_only",
                "values": [{"value": 0, "name": "Roman", "elidable": True, "code": "0"}],
            },
        ]
        combo = {"wght": AxisValueDef(400, "Regular", True)}
        name = compose_name_from_order(
            naming_order_with_defaults({"order": [PSHYPHEN_TOKEN, CODE_TOKEN, "wght", "ital"]}),
            combo,
            {"width": "Condensed"},
            axes_json=axes_json,
            file_stat_registration={"ital": 0.0},
        )
        self.assertNotIn("Condensed", name)
        self.assertIn("0", name)


if __name__ == "__main__":
    unittest.main()
