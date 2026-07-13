"""Tests for name ID allocation starting at 256."""

from __future__ import annotations

import unittest
from copy import deepcopy
from pathlib import Path

from fontTools.ttLib import TTFont

from vfcommit_lib.nameid_allocator import (
    AxisDef,
    AxisValueDef,
    _prefix_from_postscript_name,
    build_allocation_plan,
    check_for_collisions,
    compose_name_from_order,
    derive_family_ps_prefix,
    enumerate_instance_names,
)
from vfcommit_lib.ot_label_scanner import scan_ot_label_nameids
from vfcommit_lib.stat_builder import apply_table_edits, build_protected_name_ids
from vfcommit_lib.request_bridge import axis_defs_from_request

_MILGRAM = Path("/Users/skymacbook/Downloads/~Untitled/Milgram-Variable.ttf")


class NameIDAllocatorTests(unittest.TestCase):
    def test_reclaims_from_256_not_after_existing_vf_ids(self) -> None:
        if not _MILGRAM.is_file():
            self.skipTest("Milgram test font not on disk")

        font = TTFont(str(_MILGRAM), lazy=False)
        ot_labels = scan_ot_label_nameids(font)
        axes_json = [
            {
                "tag": "wght",
                "display_name": "Weight",
                "min": 300,
                "default": 400,
                "max": 900,
                "role": "instance",
                "values": [
                    {"id": "w1", "value": 300, "name": "Light", "elidable": False, "stat_format": 1},
                    {"id": "w2", "value": 400, "name": "Regular", "elidable": True, "stat_format": 1},
                    {"id": "w3", "value": 500, "name": "Medium", "elidable": False, "stat_format": 1},
                    {"id": "w4", "value": 700, "name": "Bold", "elidable": False, "stat_format": 1},
                    {"id": "w5", "value": 800, "name": "X-Bold", "elidable": False, "stat_format": 1},
                    {"id": "w6", "value": 900, "name": "Black", "elidable": False, "stat_format": 1},
                ],
            }
        ]
        axis_defs = axis_defs_from_request(axes_json)
        plan = build_allocation_plan(
            font,
            ot_labels,
            axis_defs,
            elided_fallback_name="Regular",
            allocate_postscript_names=True,
            instance_axis_defs=axis_defs,
        )

        self.assertEqual(plan.free_start, 256)
        self.assertGreaterEqual(plan.free_end, 256)
        self.assertLess(plan.free_start, 272, "should not start allocating after old VF name IDs")

        planned_ids = set(plan.axis_name_ids.values())
        planned_ids.update(plan.axis_value_ids.values())
        planned_ids.update(plan.instance_ids.values())
        planned_ids.update(plan.instance_postscript_ids.values())
        planned_ids.add(plan.elided_fallback_id)
        self.assertEqual(min(planned_ids), 256)

    def test_slope_clarifier_appends_to_instance_names(self) -> None:
        axes_json = [
            {
                "tag": "wght",
                "display_name": "Weight",
                "min": 300,
                "default": 400,
                "max": 900,
                "role": "instance",
                "values": [
                    {"id": "w1", "value": 300, "name": "Light", "elidable": False, "stat_format": 1},
                    {"id": "w2", "value": 400, "name": "Regular", "elidable": True, "stat_format": 1},
                    {"id": "w3", "value": 700, "name": "Bold", "elidable": False, "stat_format": 1},
                ],
            }
        ]
        axis_defs = axis_defs_from_request(axes_json)
        names = enumerate_instance_names(
            axis_defs,
            "Regular",
            naming_order=["wght", "@slope"],
            clarifiers={"slope": "Italic"},
        )
        self.assertIn("Light Italic", names)
        self.assertIn("Bold Italic", names)
        self.assertIn("Italic", names)

    def test_stat_value_labels_use_raw_stop_names_not_composition(self) -> None:
        """STAT ValueNames must stay axis-tree labels — never instance composition.

        Regression: Playfair Italic wrote every STAT stop as "... Italic" and turned
        the elided width "Normal" into just "Italic" because compose_name_from_order
        was used for stat_value_labels.
        """
        if not _MILGRAM.is_file():
            self.skipTest("Milgram test font not on disk")

        axes_json = [
            {
                "tag": "wdth",
                "display_name": "Width",
                "min": 88,
                "default": 100,
                "max": 113,
                "role": "instance",
                "values": [
                    {"id": "d1", "value": 88, "name": "SemiCondensed", "elidable": False, "stat_format": 1},
                    {"id": "d2", "value": 100, "name": "Normal", "elidable": True, "stat_format": 1},
                    {"id": "d3", "value": 113, "name": "SemiExpanded", "elidable": False, "stat_format": 1},
                ],
            },
            {
                "tag": "wght",
                "display_name": "Weight",
                "min": 400,
                "default": 400,
                "max": 700,
                "role": "instance",
                "values": [
                    {"id": "w1", "value": 400, "name": "Regular", "elidable": True, "stat_format": 1},
                    {"id": "w2", "value": 700, "name": "Bold", "elidable": False, "stat_format": 1},
                ],
            },
            {
                "tag": "ital",
                "display_name": "Italic",
                "role": "design_record_only",
                "values": [
                    {"id": "i1", "value": 1, "name": "Italic", "elidable": False, "stat_format": 1},
                ],
            },
        ]
        axis_defs = axis_defs_from_request(axes_json)
        font = TTFont(str(_MILGRAM), lazy=False)
        plan = build_allocation_plan(
            font,
            scan_ot_label_nameids(font),
            axis_defs,
            elided_fallback_name="Italic",
            allocate_postscript_names=False,
            instance_axis_defs=[a for a in axis_defs if a.tag != "ital"],
            naming_order=["wght", "wdth", "@slope"],
            clarifiers={"slope": "Italic"},
            axes_json=axes_json,
            file_stat_registration={"ital": 1},
        )

        self.assertEqual(plan.stat_value_labels[("wdth", 100.0)], "Normal")
        self.assertEqual(plan.stat_value_labels[("wdth", 88.0)], "SemiCondensed")
        self.assertEqual(plan.stat_value_labels[("wght", 700.0)], "Bold")
        self.assertEqual(plan.stat_value_labels[("wght", 400.0)], "Regular")
        self.assertEqual(plan.stat_value_labels[("ital", 1.0)], "Italic")
        # Instance names still compose; slope clarifier is skipped when ital registration
        # covers that category (parity with NamingComposer). Elidable-only combo → EFB.
        self.assertIn("Bold SemiCondensed", plan.instance_ids)
        self.assertIn("Italic", plan.instance_ids)
        self.assertEqual(plan.elided_fallback_name, "Italic")
        # Critically: STAT never absorbed the instance EFB / clarifier string.
        self.assertNotEqual(plan.stat_value_labels[("wdth", 100.0)], "Italic")
        self.assertNotIn("Italic", plan.stat_value_labels[("wght", 700.0)])

    def test_stat_value_labels_preserve_roman_width_and_ital_neutrals(self) -> None:
        if not _MILGRAM.is_file():
            self.skipTest("Milgram test font not on disk")

        axes_json = [
            {
                "tag": "wdth",
                "display_name": "Width",
                "min": 88,
                "default": 100,
                "max": 113,
                "role": "instance",
                "values": [
                    {"id": "d2", "value": 100, "name": "Normal", "elidable": True, "stat_format": 1},
                ],
            },
            {
                "tag": "ital",
                "display_name": "Italic",
                "role": "design_record_only",
                "values": [
                    {"id": "i0", "value": 0, "name": "Roman", "elidable": True, "stat_format": 3, "linked_value": 1},
                ],
            },
        ]
        axis_defs = axis_defs_from_request(axes_json)
        font = TTFont(str(_MILGRAM), lazy=False)
        plan = build_allocation_plan(
            font,
            scan_ot_label_nameids(font),
            axis_defs,
            elided_fallback_name="Regular",
            allocate_postscript_names=False,
            instance_axis_defs=[a for a in axis_defs if a.tag != "ital"],
            naming_order=["ital", "wdth", "@slope"],
            clarifiers={},
            axes_json=axes_json,
            file_stat_registration={"ital": 0},
        )

        self.assertEqual(plan.stat_value_labels[("wdth", 100.0)], "Normal")
        self.assertEqual(plan.stat_value_labels[("ital", 0.0)], "Roman")
        self.assertEqual(plan.elided_fallback_name, "Regular")

    def test_allocation_order_is_stat_then_efb_then_instances(self) -> None:
        """DesignAxis → AxisValues → EFB → fvar; EFB never aliases an instance ID."""
        if not _MILGRAM.is_file():
            self.skipTest("Milgram test font not on disk")

        axes_json = [
            {
                "tag": "wght",
                "display_name": "Weight",
                "min": 400,
                "default": 400,
                "max": 700,
                "role": "instance",
                "values": [
                    {"id": "w1", "value": 400, "name": "Regular", "elidable": True, "stat_format": 1},
                    {"id": "w2", "value": 700, "name": "Bold", "elidable": False, "stat_format": 1},
                ],
            }
        ]
        axis_defs = axis_defs_from_request(axes_json)
        font = TTFont(str(_MILGRAM), lazy=False)
        plan = build_allocation_plan(
            font,
            scan_ot_label_nameids(font),
            axis_defs,
            elided_fallback_name="Regular",
            allocate_postscript_names=False,
            instance_axis_defs=axis_defs,
            naming_order=["wght"],
        )

        axis_name_ids = sorted(plan.axis_name_ids.values())
        axis_value_ids = sorted(plan.axis_value_ids.values())
        instance_ids = sorted(plan.instance_ids.values())

        self.assertTrue(axis_name_ids)
        self.assertTrue(axis_value_ids)
        self.assertTrue(instance_ids)
        self.assertLess(max(axis_name_ids), min(axis_value_ids))
        self.assertLess(max(axis_value_ids), plan.elided_fallback_id)
        self.assertLess(plan.elided_fallback_id, min(instance_ids))
        # Duplicate string "Regular" on STAT, EFB, and instance each get distinct IDs.
        self.assertNotEqual(plan.elided_fallback_id, plan.instance_ids["Regular"])
        self.assertNotEqual(
            plan.elided_fallback_id,
            plan.axis_value_ids[("wght", 400.0)],
        )
        self.assertNotEqual(
            plan.instance_ids["Regular"],
            plan.axis_value_ids[("wght", 400.0)],
        )
        self.assertEqual(check_for_collisions(plan, font), [])

    def test_preserves_stat_only_design_axis_name_ids(self) -> None:
        nouveau = Path("/Users/skymacbook/Downloads/~Untitled/NouveauLED-Variable.ttf")
        if not nouveau.is_file():
            self.skipTest("Nouveau LED test font not on disk")

        font = TTFont(str(nouveau), lazy=False)
        ot_labels = scan_ot_label_nameids(font)
        stat = font["STAT"].table
        ital_axis = next(
            ax for ax in stat.DesignAxisRecord.Axis if ax.AxisTag == "ital"
        )
        ital_name_id = ital_axis.AxisNameID
        self.assertGreaterEqual(ital_name_id, 256)

        axes_json = [
            {
                "tag": "wght",
                "display_name": "Weight",
                "min": 0,
                "default": 0,
                "max": 1000,
                "role": "instance",
                "values": [
                    {"id": "w1", "value": 0, "name": "Hair", "elidable": False, "stat_format": 1},
                    {"id": "w2", "value": 400, "name": "Regular", "elidable": True, "stat_format": 1},
                ],
            },
            {
                "tag": "FLOR",
                "display_name": "Flora",
                "min": 0,
                "default": 0,
                "max": 1000,
                "role": "instance",
                "values": [
                    {"id": "f1", "value": 0, "name": "Crocus", "elidable": False, "stat_format": 1},
                ],
            },
        ]
        axis_defs = axis_defs_from_request(axes_json)
        plan = build_allocation_plan(
            font,
            ot_labels,
            axis_defs,
            elided_fallback_name="Regular",
            allocate_postscript_names=True,
            instance_axis_defs=axis_defs,
            family_ps_prefix="NouveauLEDVariable",
        )

        planned_ids = set(plan.axis_value_ids.values())
        planned_ids.update(plan.instance_ids.values())
        planned_ids.update(plan.instance_postscript_ids.values())
        planned_ids.add(plan.elided_fallback_id)
        self.assertNotIn(
            ital_name_id,
            planned_ids,
            "STAT-only ital axis name ID must not be reused for instances or PS names",
        )
        self.assertEqual(
            font["name"].getDebugName(ital_name_id),
            "Italic",
        )

    def test_stable_plan_reuses_role_bound_name_ids(self) -> None:
        if not _MILGRAM.is_file():
            self.skipTest("Milgram test font not on disk")

        font = TTFont(str(_MILGRAM), lazy=False)
        ot_labels = scan_ot_label_nameids(font)
        axes_json = [
            {
                "tag": "wght",
                "display_name": "Weight",
                "min": 300,
                "default": 400,
                "max": 900,
                "role": "instance",
                "values": [
                    {"id": "w1", "value": 300, "name": "Light", "elidable": False, "stat_format": 1},
                    {"id": "w2", "value": 400, "name": "Regular", "elidable": True, "stat_format": 1},
                    {"id": "w3", "value": 700, "name": "Bold", "elidable": False, "stat_format": 1},
                ],
            }
        ]
        axis_defs = axis_defs_from_request(axes_json)
        kwargs = dict(
            elided_fallback_name="Regular",
            allocate_postscript_names=True,
            instance_axis_defs=axis_defs,
            family_ps_prefix="Milgram",
        )
        plan1 = build_allocation_plan(font, ot_labels, axis_defs, **kwargs)
        working = deepcopy(font)
        apply_table_edits(
            working,
            axis_defs,
            plan1,
            elided_fallback_name="Regular",
            protected_ids=build_protected_name_ids(font, {rec.name_id for rec in ot_labels}),
            confirm_wipe=False,
            instance_axis_defs=axis_defs,
        )
        plan2 = build_allocation_plan(working, ot_labels, axis_defs, **kwargs)
        self.assertEqual(plan2.axis_value_ids, plan1.axis_value_ids)
        self.assertEqual(plan2.elided_fallback_id, plan1.elided_fallback_id)

    def test_writes_family_prefix_to_name_id_25(self) -> None:
        if not _MILGRAM.is_file():
            self.skipTest("Milgram test font not on disk")

        font = TTFont(str(_MILGRAM), lazy=False)
        ot_labels = scan_ot_label_nameids(font)
        axes_json = [
            {
                "tag": "wght",
                "display_name": "Weight",
                "min": 300,
                "default": 400,
                "max": 900,
                "role": "instance",
                "values": [
                    {"id": "w1", "value": 400, "name": "Regular", "elidable": True, "stat_format": 1},
                ],
            }
        ]
        axis_defs = axis_defs_from_request(axes_json)
        plan = build_allocation_plan(
            font,
            ot_labels,
            axis_defs,
            elided_fallback_name="Regular",
            allocate_postscript_names=True,
            instance_axis_defs=axis_defs,
            family_ps_prefix="Nouveau",
        )
        working = deepcopy(font)
        apply_table_edits(
            working,
            axis_defs,
            plan,
            elided_fallback_name="Regular",
            protected_ids=build_protected_name_ids(font, {rec.name_id for rec in ot_labels}),
            confirm_wipe=False,
            instance_axis_defs=axis_defs,
        )
        self.assertEqual(working["name"].getDebugName(25), "Nouveau")

    def test_prefix_from_postscript_name_allows_periods(self) -> None:
        self.assertEqual(_prefix_from_postscript_name("Loes0.4-Regular"), "Loes0.4")

    def test_derive_family_ps_prefix_name_id_16_loes(self) -> None:
        from fontTools.ttLib.tables._n_a_m_e import table__n_a_m_e

        font = TTFont()
        font.setGlyphOrder([".notdef"])
        name_table = table__n_a_m_e()
        font["name"] = name_table
        name_table.setName("Different Family", 1, 3, 1, 0x409)
        name_table.setName("Loes 0.4", 16, 3, 1, 0x409)
        self.assertEqual(derive_family_ps_prefix(font), "Loes0.4")


if __name__ == "__main__":
    unittest.main()
