"""Reorder STAT DesignAxisRecord order to match the commit request.

fvar axis record order and avar segment maps are intentionally left alone:
variation data (gvar / HVAR / etc.) is stored parallel to fvar axis indices.
Rewriting fvar order without remapping that data swaps slider identity.
"""

from __future__ import annotations

from typing import List, Sequence

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.otTables import AxisRecord, AxisRecordArray


def _stat_table(font: TTFont):
    """Return the STAT table object (loaded fonts wrap in `.table`)."""
    stat = font["STAT"]
    return getattr(stat, "table", stat)


def reorder_axis_tables(
    font: TTFont,
    *,
    design_axis_tags: Sequence[str],
    fvar_axis_tags: Sequence[str] | None = None,
) -> List[str]:
    """Ensure + rewrite STAT DesignAxisRecord order (+ AxisOrdering).

    Missing tags from ``design_axis_tags`` are appended before reordering.
    Returns tags that were newly appended to DesignAxisRecord.

    ``fvar_axis_tags`` is accepted for call-site compatibility and ignored.
    """
    del fvar_axis_tags  # locked: do not permute fvar / avar
    if not design_axis_tags:
        return []
    tag_list = list(design_axis_tags)
    appended = _ensure_design_axes(font, tag_list)
    _reorder_stat_design_axes(font, tag_list)
    return appended


def _ensure_design_axes(font: TTFont, tag_order: List[str]) -> List[str]:
    """Append DesignAxisRecord rows for request tags missing from STAT."""
    if "STAT" not in font:
        return []
    stat = _stat_table(font)
    design = getattr(stat, "DesignAxisRecord", None)
    if design is None or not hasattr(design, "Axis"):
        design = AxisRecordArray()
        design.Axis = []
        stat.DesignAxisRecord = design

    by_tag = {ax.AxisTag: ax for ax in design.Axis}
    appended: List[str] = []
    for tag in tag_order:
        if tag in by_tag:
            continue
        rec = AxisRecord()
        rec.AxisTag = tag
        rec.AxisNameID = 0  # repointed in stat_builder._write_stat
        rec.AxisOrdering = len(design.Axis)
        design.Axis.append(rec)
        by_tag[tag] = rec
        appended.append(tag)
    return appended


def _reorder_stat_design_axes(font: TTFont, tag_order: List[str]) -> None:
    if "STAT" not in font:
        return
    stat = _stat_table(font)
    design = getattr(stat, "DesignAxisRecord", None)
    if not design or not design.Axis:
        return
    by_tag = {ax.AxisTag: ax for ax in design.Axis}
    reordered = [by_tag[tag] for tag in tag_order if tag in by_tag]
    for ax in design.Axis:
        if ax.AxisTag not in tag_order:
            reordered.append(ax)
    design.Axis = reordered
    for index, axis in enumerate(design.Axis):
        axis.AxisOrdering = index


__all__ = ["reorder_axis_tables", "_ensure_design_axes"]
