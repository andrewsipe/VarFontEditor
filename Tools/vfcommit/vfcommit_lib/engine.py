"""Dry-run and commit orchestration for vfcommit."""

from __future__ import annotations

from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Set

from fontTools.ttLib import TTFont

from vfcommit_lib.nameid_allocator import (
    build_allocation_plan,
    check_for_collisions,
    naming_order_with_defaults,
    parse_clarifiers,
    effective_elided_fallback,
)
from vfcommit_lib.ot_label_scanner import scan_ot_label_nameids
from vfcommit_lib.request_bridge import (
    axis_defs_from_request,
    compound_stat_values_from_request,
    count_included_instances,
    grid_axis_defs,
    pinned_coords,
)
from vfcommit_lib.stat_builder import (
    apply_table_edits,
    build_protected_name_ids,
)
from vfcommit_lib.diff_export import build_commit_diff


def run_commit(request: Dict[str, Any]) -> Dict[str, Any]:
    """Execute dry-run or write commit from a CommitRequest dict."""
    request_id = str(request.get("request_id", ""))
    source_path = str(request["source_path"])
    output_path = str(request.get("output_path", ""))
    dry_run = bool(request.get("dry_run", False))
    options = request.get("options") or {}
    naming = request.get("naming") or {}
    file_role = request.get("file_role")
    axes_json = request.get("axes") or []
    included_keys = list(request.get("included_instance_keys") or [])
    file_stat_registration = {
        str(tag): float(value)
        for tag, value in (request.get("file_stat_registration") or {}).items()
    }
    compound_json = list(request.get("compound_stat_values") or [])

    naming_order = naming_order_with_defaults(naming)
    clarifiers = parse_clarifiers(file_role)
    elided_fallback = effective_elided_fallback(naming, file_role)

    if not Path(source_path).is_file():
        return _error_result(
            request_id,
            dry_run,
            "missing_source",
            f"Source font not found: {source_path}",
        )

    try:
        font = TTFont(source_path, lazy=False)
    except Exception as exc:
        return _error_result(request_id, dry_run, "unreadable_font", str(exc))

    axis_defs = axis_defs_from_request(axes_json)
    grid_axes = grid_axis_defs(axis_defs, axes_json)
    pinned = pinned_coords(axes_json)
    compound_defs = compound_stat_values_from_request(compound_json)

    ot_labels = scan_ot_label_nameids(font)
    ot_label_ids = {rec.name_id for rec in ot_labels}

    family_ps_prefix = options.get("family_ps_prefix")
    plan = build_allocation_plan(
        font,
        ot_labels,
        axis_defs,
        elided_fallback_name=elided_fallback,
        allocate_postscript_names=bool(options.get("allocate_postscript_names", True)),
        instance_axis_defs=grid_axes,
        naming_order=naming_order,
        clarifiers=clarifiers,
        family_ps_prefix=str(family_ps_prefix) if family_ps_prefix else None,
        axes_json=axes_json,
        file_stat_registration=file_stat_registration,
        compound_defs=compound_defs,
        included_instance_keys=included_keys,
        pinned_coords=pinned,
    )
    collisions = check_for_collisions(plan, font)
    if collisions:
        return {
            "schema_version": 1,
            "request_id": request_id,
            "ok": False,
            "output_path": None,
            "dry_run": dry_run,
            "summary": None,
            "warnings": [
                {
                    "code": "nameid_collision",
                    "message": line,
                }
                for line in collisions
            ],
            "errors": [
                {
                    "code": "nameid_collision",
                    "message": collisions[0],
                }
            ],
        }

    protected_ids = build_protected_name_ids(font, ot_label_ids)
    instances_to_write = count_included_instances(grid_axes, included_keys, pinned_coords=pinned)
    stat_values_written = sum(len(axis.values) for axis in axis_defs) + len(compound_defs)
    wiped_instances = len(font["fvar"].instances) if "fvar" in font else 0

    allocated_ids = sorted(
        set(plan.instance_ids.values())
        | set(plan.axis_value_ids.values())
        | set(plan.axis_name_ids.values())
        | set(plan.instance_postscript_ids.values())
        | {plan.elided_fallback_id}
    )
    allocated_ids = [nid for nid in allocated_ids if nid]

    warnings: List[Dict[str, Any]] = []

    if not dry_run:
        if not output_path:
            return _error_result(
                request_id,
                dry_run,
                "missing_output_path",
                "output_path is required when dry_run is false",
            )
        if Path(output_path).resolve() == Path(source_path).resolve():
            return _error_result(
                request_id,
                dry_run,
                "in_place_output",
                "output_path must differ from source_path",
            )

        working = deepcopy(font)
        apply_table_edits(
            working,
            axis_defs,
            plan,
            elided_fallback_name=elided_fallback,
            protected_ids=protected_ids,
            confirm_wipe=False,
            ot_label_count=len(ot_labels),
            instance_axis_defs=grid_axes,
            pinned_coords=pinned,
            compound_defs=compound_defs,
            included_instance_keys=included_keys,
        )
        working.save(output_path)

    result: Dict[str, Any] = {
        "schema_version": 1,
        "request_id": request_id,
        "ok": True,
        "output_path": None if dry_run else output_path,
        "dry_run": dry_run,
        "summary": {
            "instances_written": instances_to_write,
            "stat_values_written": stat_values_written,
            "name_ids_allocated": allocated_ids,
            "wiped_instance_count": wiped_instances,
            "protected_name_ids": sorted(protected_ids),
        },
        "warnings": warnings,
        "errors": [],
    }
    if dry_run:
        result["diff"] = build_commit_diff(plan, axis_defs)
    return result


def _error_result(
    request_id: str,
    dry_run: bool,
    code: str,
    message: str,
) -> Dict[str, Any]:
    return {
        "schema_version": 1,
        "request_id": request_id,
        "ok": False,
        "output_path": None,
        "dry_run": dry_run,
        "summary": None,
        "warnings": [],
        "errors": [{"code": code, "message": message}],
    }
