"""Tests for vfcommit request bridge."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from vfcommit_lib.request_bridge import grid_axis_defs, pinned_coords  # noqa: E402


def test_pinned_coords_skips_instance_and_design_record_only() -> None:
    axes = [
        {"tag": "wght", "role": "instance", "values": [{"value": 400}]},
        {
            "tag": "ital",
            "role": "design_record_only",
            "values": [{"value": 0}],
        },
        {
            "tag": "GRAD",
            "role": "stat_only",
            "default": 0,
            "values": [{"value": 0}],
        },
    ]
    assert pinned_coords(axes) == {"GRAD": 0.0}


def test_pinned_coords_stat_only_uses_default() -> None:
    axes = [
        {
            "tag": "opsz",
            "role": "stat_only",
            "default": 14,
            "values": [
                {"value": 8},
                {"value": 14},
            ],
        }
    ]
    assert pinned_coords(axes) == {"opsz": 14.0}


def test_grid_axis_defs_only_instance_roles() -> None:
    axes_json = [
        {"tag": "wght", "role": "instance", "values": [{"value": 400, "name": "Regular"}]},
        {"tag": "ital", "role": "design_record_only", "values": [{"value": 0, "name": "Roman"}]},
        {"tag": "GRAD", "role": "stat_only", "values": [{"value": 0, "name": "Default"}]},
    ]
    from vfcommit_lib.request_bridge import axis_defs_from_request

    axis_defs = axis_defs_from_request(axes_json)
    grid = grid_axis_defs(axis_defs, axes_json)
    assert [axis.tag for axis in grid] == ["wght"]
