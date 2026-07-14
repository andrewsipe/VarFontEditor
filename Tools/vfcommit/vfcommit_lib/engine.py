"""Dry-run and commit orchestration for vfcommit."""

from __future__ import annotations

from copy import deepcopy
import os
import shutil
from pathlib import Path
from typing import Any, Dict, List, Set

from fontTools.ttLib import TTFont

from vfcommit_lib.nameid_allocator import (
    build_allocation_plan,
    check_for_collisions,
    naming_order_with_defaults,
    parse_clarifiers,
    effective_elided_fallback,
    preserved_design_axis_name_ids,
)
from vfcommit_lib.ot_label_scanner import scan_ot_label_nameids
from vfcommit_lib.ot_label_reflow import (
    apply_ot_reflow,
    build_ot_reflow_diff_entries,
    build_ot_reflow_plan,
    build_reflow_pre_wipe_protected,
    classify_name_ids,
    detect_reflow_blockers,
    pre_wipe_for_reflow,
    scan_ot_label_sites,
)
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
from vfcommit_lib.post_write_validator import (
    ValidationExpectations,
    validate_written_font,
)


def _parse_nameid_strategy(options: Dict[str, Any]) -> str:
    return str(options.get("nameid_strategy", "preserve")).strip().lower()


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
    if "included_instance_keys" in request:
        included_keys: list[str] | None = list(request.get("included_instance_keys") or [])
    else:
        included_keys = None
    file_stat_registration = {
        str(tag): float(value)
        for tag, value in (request.get("file_stat_registration") or {}).items()
    }
    compound_json = list(request.get("compound_stat_values") or [])

    naming_order = naming_order_with_defaults(naming)
    clarifiers = parse_clarifiers(file_role)
    elided_fallback = effective_elided_fallback(naming, file_role)

    strategy = _parse_nameid_strategy(options)
    if strategy not in ("preserve", "reflow"):
        return _error_result(
            request_id,
            dry_run,
            "invalid_nameid_strategy",
            f"Unknown nameid_strategy: {strategy!r}",
        )

    if not Path(source_path).is_file():
        return _error_result(
            request_id,
            dry_run,
            "missing_source",
            f"Source font not found: {source_path}",
        )

    try:
        # Dry-run only needs name/fvar/STAT/GSUB/GPOS — avoid pulling glyf/gvar/CFF2.
        font = TTFont(source_path, lazy=bool(dry_run))
    except Exception as exc:
        return _error_result(request_id, dry_run, "unreadable_font", str(exc))

    axis_defs = axis_defs_from_request(axes_json)
    grid_axes = grid_axis_defs(axis_defs, axes_json)
    pinned = pinned_coords(axes_json)
    compound_defs = compound_stat_values_from_request(compound_json)

    ot_reflow_mapping: Dict[int, int] = {}
    ot_reflow_end = 255
    ot_groups: Dict[int, list] = {}
    orphan_ids_dropped: List[int] = []
    classification = None

    if strategy == "reflow":
        ot_groups = scan_ot_label_sites(font)
        classification = classify_name_ids(font, ot_groups, axis_defs)
        blockers = detect_reflow_blockers(classification)
        if blockers:
            return _error_result(
                request_id,
                dry_run,
                "ot_reflow_blocked",
                blockers[0],
            )
        orphan_ids_dropped = sorted(classification.orphan_ids)
        pre_wipe_for_reflow(
            font,
            build_reflow_pre_wipe_protected(font, ot_groups, axis_defs),
        )
        ot_reflow_mapping = build_ot_reflow_plan(ot_groups)
        ot_reflow_end = apply_ot_reflow(font, ot_reflow_mapping, ot_groups)
        ot_labels = scan_ot_label_nameids(font)
        ot_label_ids = {rec.name_id for rec in ot_labels}
    else:
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
        nameid_strategy=strategy,
        ot_reflow_end=ot_reflow_end if strategy == "reflow" else None,
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

    if strategy == "reflow":
        new_ot_ids = set(ot_reflow_mapping.values()) | {
            nid for nid in ot_label_ids if nid < 256
        }
        preserved_axes = preserved_design_axis_name_ids(
            font, {axis_def.tag for axis_def in axis_defs}
        )
        protected_ids = new_ot_ids | preserved_axes
    else:
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
    if orphan_ids_dropped:
        warnings.append(
            {
                "code": "orphan_nameids_dropped",
                "message": (
                    "Orphan name IDs removed during reflow pre-wipe: "
                    + ", ".join(str(nid) for nid in orphan_ids_dropped[:10])
                    + ("..." if len(orphan_ids_dropped) > 10 else "")
                ),
            }
        )

    if not dry_run:
        if not output_path:
            return _error_result(
                request_id,
                dry_run,
                "missing_output_path",
                "output_path is required when dry_run is false",
            )
        allow_in_place = bool(request.get("allow_in_place", False))
        original_source_path = str(request.get("original_source_path") or source_path)
        out_resolved = Path(output_path).resolve()
        src_resolved = Path(source_path).resolve()
        original_resolved = Path(original_source_path).resolve()
        if out_resolved == src_resolved and not allow_in_place:
            return _error_result(
                request_id,
                dry_run,
                "in_place_output",
                "output_path must differ from source_path",
            )
        if allow_in_place and out_resolved != original_resolved:
            return _error_result(
                request_id,
                dry_run,
                "in_place_target_mismatch",
                "allow_in_place requires output_path to match original_source_path",
            )

        backup_path = None
        if allow_in_place and out_resolved == original_resolved and out_resolved.is_file():
            backup_path = out_resolved.with_name(out_resolved.name + ".vfstudio-backup")
            if backup_path.exists():
                backup_path.unlink()
            shutil.copy2(out_resolved, backup_path)

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
        temp_path = out_resolved.with_name(out_resolved.name + ".vfcommit-tmp")
        if temp_path.exists():
            temp_path.unlink()
        working.save(str(temp_path))
        os.replace(temp_path, out_resolved)
        if backup_path is not None:
            warnings.append(
                {
                    "code": "backup_created",
                    "message": f"Backup written to {backup_path}",
                }
            )

        validation = validate_written_font(
            str(out_resolved),
            expectations=ValidationExpectations(
                instances_written=instances_to_write,
                elided_fallback_name=elided_fallback,
            ),
        )

    validation_payload: Dict[str, Any] | None = None
    commit_ok = True
    errors: List[Dict[str, Any]] = []

    if not dry_run:
        validation_payload = validation.to_dict()
        for issue in validation.issues:
            if issue.severity == "warning":
                warnings.append({"code": issue.code, "message": issue.message})
            else:
                errors.append({"code": issue.code, "message": issue.message})
        if not validation.ok:
            commit_ok = False

    summary: Dict[str, Any] = {
        "instances_written": instances_to_write,
        "stat_values_written": stat_values_written,
        "name_ids_allocated": allocated_ids,
        "wiped_instance_count": wiped_instances,
        "protected_name_ids": sorted(protected_ids),
    }
    if ot_reflow_mapping:
        summary["ot_reflow_mapping"] = {
            str(old_id): new_id for old_id, new_id in sorted(ot_reflow_mapping.items())
        }
    if orphan_ids_dropped:
        summary["orphan_nameids_dropped"] = orphan_ids_dropped

    result: Dict[str, Any] = {
        "schema_version": 1,
        "request_id": request_id,
        "ok": commit_ok,
        "output_path": None if dry_run else output_path,
        "dry_run": dry_run,
        "summary": summary,
        "warnings": warnings,
        "errors": errors,
    }
    if validation_payload is not None:
        result["validation"] = validation_payload
    if dry_run:
        ot_reflow_diff = build_ot_reflow_diff_entries(ot_reflow_mapping, ot_groups, font)
        result["diff"] = build_commit_diff(
            plan,
            axis_defs,
            ot_reflow_mapping=ot_reflow_diff,
        )
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
