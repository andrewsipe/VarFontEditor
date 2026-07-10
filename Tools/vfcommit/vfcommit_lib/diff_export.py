"""Serialize NameIDPlan into CommitResult.diff for dry-run review."""

from __future__ import annotations

from typing import Any, Dict, List

from vfcommit_lib.nameid_allocator import AxisDef, NameIDPlan


def build_commit_diff(
    plan: NameIDPlan,
    axis_defs: List[AxisDef],
) -> Dict[str, Any]:
    """Build structured diff payload for Swift CommitDiffBuilder."""
    name_records: List[Dict[str, Any]] = []
    seen_ids: set[int] = set()

    def add_record(nid: int, string: str, role: str) -> None:
        if not nid or nid in seen_ids:
            return
        seen_ids.add(nid)
        name_records.append({"id": nid, "string": string, "role": role})

    for tag, nid in sorted(plan.axis_name_ids.items(), key=lambda item: item[1]):
        add_record(nid, plan.axis_names.get(tag, tag), "axis_display_name")

    for axis_def in axis_defs:
        for av_def in axis_def.values:
            key = (axis_def.tag, av_def.value)
            nid = plan.axis_value_ids.get(key)
            if nid is not None:
                label = plan.stat_value_labels.get(key, av_def.name)
                add_record(nid, label, "stat_axis_value")

    if plan.elided_fallback_id:
        add_record(
            plan.elided_fallback_id,
            plan.elided_fallback_name,
            "elided_fallback",
        )

    for composed, nid in sorted(plan.instance_ids.items(), key=lambda item: item[1]):
        add_record(nid, composed, "instance_subfamily")
        ps_name = plan.instance_postscript_names.get(composed)
        ps_nid = plan.instance_postscript_ids.get(composed)
        if ps_name and ps_nid:
            add_record(ps_nid, ps_name, "instance_postscript")

    stat_values_planned = []
    for axis_def in axis_defs:
        for av_def in axis_def.values:
            key = (axis_def.tag, av_def.value)
            nid = plan.axis_value_ids.get(key)
            label = plan.stat_value_labels.get(key, av_def.name)
            entry: Dict[str, Any] = {
                "tag": axis_def.tag,
                "value": float(av_def.value),
                "name": label,
                "elidable": bool(av_def.elidable),
                "stat_format": int(av_def.stat_format),
                "name_id": nid,
            }
            if av_def.linked_value is not None:
                entry["linked_value"] = float(av_def.linked_value)
            if av_def.range_min is not None:
                entry["range_min"] = float(av_def.range_min)
            if av_def.range_max is not None:
                entry["range_max"] = float(av_def.range_max)
            stat_values_planned.append(entry)

    instances_planned = []
    for composed, nid in sorted(plan.instance_ids.items(), key=lambda item: item[1]):
        entry = {
            "composed_name": composed,
            "subfamily_name_id": nid,
        }
        ps_name = plan.instance_postscript_names.get(composed)
        ps_nid = plan.instance_postscript_ids.get(composed)
        if ps_name:
            entry["postscript_name"] = ps_name
        if ps_nid:
            entry["postscript_name_id"] = ps_nid
        instances_planned.append(entry)

    return {
        "family_ps_prefix": plan.family_ps_prefix,
        "elided_fallback_name": plan.elided_fallback_name,
        "elided_fallback_id": plan.elided_fallback_id,
        "name_id_range": [plan.free_start, plan.free_end],
        "name_records_planned": sorted(name_records, key=lambda rec: rec["id"]),
        "name_records_sequenced": list(name_records),
        "stat_values_planned": stat_values_planned,
        "instances_planned": instances_planned,
    }
