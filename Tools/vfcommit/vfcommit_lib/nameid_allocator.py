#!/usr/bin/env python3
"""
NameID audit and allocation for variable-font STAT/fvar table editing.
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

from fontTools.ttLib import TTFont

from vfcommit_lib.logging_config import get_logger
from vfcommit_lib.name_policies import sanitize_postscript, strip_variable_tokens
from vfcommit_lib.ot_label_scanner import OTLabelRecord

logger = get_logger(__name__)

CLARIFIER_TOKEN_TO_CATEGORY: Dict[str, str] = {
    "@width": "width",
    "@slope": "slope",
    "@optical": "optical",
    "@custom": "custom",
}

REGISTRATION_AXIS_TO_CLARIFIER_CATEGORY: Dict[str, str] = {
    "ital": "slope",
    "wdth": "width",
    "opsz": "optical",
}

DEFAULT_CLARIFIER_TOKENS: List[str] = list(CLARIFIER_TOKEN_TO_CATEGORY.keys())


def clarifier_categories_covered_by_registration(
    axes_json: Optional[List[dict]],
    file_stat_registration: Optional[Dict[str, float]],
) -> set[str]:
    """Clarifier categories superseded by design-record registration on this file."""
    covered: set[str] = set()
    axis_by_tag = {str(axis["tag"]): axis for axis in (axes_json or [])}
    for tag in (file_stat_registration or {}):
        axis = axis_by_tag.get(tag)
        if axis and str(axis.get("role")) == "design_record_only":
            category = REGISTRATION_AXIS_TO_CLARIFIER_CATEGORY.get(tag)
            if category:
                covered.add(category)
    return covered


def parse_clarifiers(file_role: Optional[dict]) -> Dict[str, str]:
    """Map clarifier category to label from CommitRequest file_role."""
    result: Dict[str, str] = {}
    if not file_role:
        return result
    for item in file_role.get("clarifiers") or []:
        category = str(item.get("category") or "").strip()
        label = str(item.get("label") or "").strip()
        if category and label:
            result[category] = label
    return result


def effective_elided_fallback(naming: dict, file_role: Optional[dict]) -> str:
    override = (file_role or {}).get("elided_fallback_override")
    if override:
        return str(override)
    return str(naming.get("elided_fallback") or "Regular")


def naming_order_with_defaults(naming: dict) -> List[str]:
    order = list(naming.get("order") or [])
    for token in DEFAULT_CLARIFIER_TOKENS:
        if token not in order:
            order.append(token)
    return order


def compose_name_from_order(
    naming_order: List[str],
    axis_values_by_tag: Dict[str, AxisValueDef],
    clarifiers: Dict[str, str],
    elided_fallback_name: str = "Regular",
    *,
    axes_json: Optional[List[dict]] = None,
    file_stat_registration: Optional[Dict[str, float]] = None,
) -> str:
    """Interleave axis stop names and per-file clarifier labels."""
    axis_by_tag = {str(axis["tag"]): axis for axis in (axes_json or [])}
    registration = file_stat_registration or {}
    covered_clarifiers = clarifier_categories_covered_by_registration(axes_json, registration)
    parts: List[str] = []

    for token in naming_order:
        if token in CLARIFIER_TOKEN_TO_CATEGORY:
            category = CLARIFIER_TOKEN_TO_CATEGORY[token]
            if category in covered_clarifiers:
                continue
            label = clarifiers.get(category)
            if label:
                parts.append(label)
            continue

        axis_json = axis_by_tag.get(token)
        if axis_json and str(axis_json.get("role")) == "design_record_only":
            reg_value = registration.get(token)
            if reg_value is not None:
                stop = _stop_for_axis_json(axis_json, reg_value)
                if stop and not bool(stop.get("elidable", False)):
                    parts.append(str(stop["name"]))
            continue

        av = axis_values_by_tag.get(token)
        if av is None:
            continue
        if not av.elidable:
            parts.append(av.name)
    return " ".join(parts) if parts else elided_fallback_name


def _stop_for_axis_json(axis_json: dict, value: float) -> Optional[dict]:
    for stop in axis_json.get("values") or []:
        if abs(float(stop["value"]) - float(value)) < 1e-4:
            return stop
    return None


@dataclass
class AxisValueDef:
    """A single user-defined named position on one axis."""

    value: float
    name: str
    elidable: bool
    stat_format: int = 1
    range_min: Optional[float] = None
    range_max: Optional[float] = None
    linked_value: Optional[float] = None
    older_sibling: bool = False


@dataclass
class CompoundStatValueDef:
    """Preserved STAT format 4 compound multi-axis entry."""

    id: str
    axis_indices: List[int]
    axis_values: List[float]
    name: str
    elidable: bool
    older_sibling: bool = False


@dataclass
class AxisDef:
    """All user-defined named values for one axis."""

    tag: str
    display_name: str
    min_value: float
    default_value: float
    max_value: float
    values: List[AxisValueDef]
    stat_format_override: int = 1


@dataclass
class NameIDPlan:
    """Complete nameID allocation plan (no font writes)."""

    protected: Dict[int, str]
    axis_value_ids: Dict[Tuple[str, float], int]
    instance_ids: Dict[str, int]
    axis_name_ids: Dict[str, int] = field(default_factory=dict)
    axis_names: Dict[str, str] = field(default_factory=dict)
    instance_postscript_names: Dict[str, str] = field(default_factory=dict)
    instance_postscript_ids: Dict[str, int] = field(default_factory=dict)
    family_ps_prefix: str = ""
    elided_fallback_name: str = "Regular"
    elided_fallback_id: int = 0
    compound_value_ids: Dict[str, int] = field(default_factory=dict)
    compound_value_names: Dict[str, str] = field(default_factory=dict)
    axes_json: List[dict] = field(default_factory=list)
    file_stat_registration: Dict[str, float] = field(default_factory=dict)
    stat_value_labels: Dict[Tuple[str, float], str] = field(default_factory=dict)
    naming_order: List[str] = field(default_factory=list)
    clarifiers: Dict[str, str] = field(default_factory=dict)
    free_start: int = 256
    free_end: int = 255


def audit_nameids(font: TTFont, ot_labels: List[OTLabelRecord]) -> Dict[int, str]:
    """Map each nameID >= 256 in use to a human-readable reference description."""
    used: Dict[int, str] = {}

    if "fvar" in font:
        for axis in font["fvar"].axes:
            nid = axis.axisNameID
            if nid >= 256:
                used[nid] = f"fvar axis [{axis.axisTag}] AxisNameID"

        for i, inst in enumerate(font["fvar"].instances):
            nid = inst.subfamilyNameID
            if nid >= 256:
                used[nid] = f"fvar instance subfamilyNameID (index {i})"
            ps_nid = getattr(inst, "postscriptNameID", 0xFFFF)
            if ps_nid not in (0xFFFF, 0, None) and ps_nid >= 256:
                used[ps_nid] = f"fvar instance postscriptNameID (index {i})"

    if "STAT" in font:
        stat = font["STAT"].table
        if hasattr(stat, "DesignAxisRecord") and stat.DesignAxisRecord:
            for ax in stat.DesignAxisRecord.Axis:
                nid = ax.AxisNameID
                if nid >= 256:
                    used[nid] = f"STAT DesignAxisRecord [{ax.AxisTag}] AxisNameID"
        if hasattr(stat, "AxisValueArray") and stat.AxisValueArray:
            for av in stat.AxisValueArray.AxisValue:
                nid = av.ValueNameID
                val = getattr(av, "Value", getattr(av, "NominalValue", "?"))
                ax_idx = getattr(av, "AxisIndex", "?")
                if nid >= 256:
                    used[nid] = f"STAT AxisValue [axis {ax_idx} = {val}] ValueNameID"
        efb = getattr(stat, "ElidedFallbackNameID", None)
        if efb and efb >= 256:
            used[efb] = "STAT ElidedFallbackNameID"

    for rec in ot_labels:
        if rec.name_id >= 256:
            suffix = f' ("{rec.string}")' if rec.string else ""
            used[rec.name_id] = f"{rec.table} {rec.feature_tag} {rec.field}{suffix}"

    all_name_ids = {nr.nameID for nr in font["name"].names if nr.nameID >= 256}
    for nid in all_name_ids:
        if nid not in used:
            string = font["name"].getDebugName(nid) or ""
            used[nid] = f'name table only (no table reference) "{string}"'

    return used


def preserved_design_axis_name_ids(font: TTFont, rebuilt_tags: Set[str]) -> Set[int]:
    """
    STAT DesignAxisRecord name IDs for axes not rebuilt by this commit.

    Axes present in STAT but omitted from axis_defs (e.g. ital without fvar)
    keep their AxisNameID; allocation must not reuse those IDs.
    """
    preserved: Set[int] = set()
    if "STAT" not in font:
        return preserved
    stat = font["STAT"].table
    design = getattr(stat, "DesignAxisRecord", None)
    if not design or not design.Axis:
        return preserved
    for ax in design.Axis:
        if ax.AxisTag in rebuilt_tags:
            continue
        nid = ax.AxisNameID
        if nid >= 256:
            preserved.add(nid)
    return preserved


def _prefix_from_postscript_name(raw: str | None) -> str | None:
    """Stem before first hyphen; whole string if no hyphen."""
    if not raw or not raw.strip():
        return None
    s = raw.strip()
    if "?" in s or "." in s:
        return None
    stem = s.split("-", 1)[0] if "-" in s else s
    compact = sanitize_postscript(stem)
    return compact or None


def derive_family_ps_prefix(font: TTFont) -> str:
    """
    Prefix for fvar instance PostScript names (e.g. OnsiteVF from nameID 25).

    Prefers ID 25, then ID 6 stem before hyphen, then stripped ID 6, then family.
    """
    n25 = font["name"].getDebugName(25)
    if n25 and n25.strip():
        return sanitize_postscript(n25.strip())

    n6 = font["name"].getDebugName(6)
    if n6 and n6.strip():
        from_hyphen = _prefix_from_postscript_name(n6)
        if from_hyphen:
            return from_hyphen
        base = strip_variable_tokens(n6) or n6
        for token in ("Variable", "VF"):
            if base.endswith(token):
                base = base[: -len(token)].rstrip("-_")
            if base.endswith(f"-{token}"):
                base = base[: -(len(token) + 1)].rstrip("-_")
        if base:
            return sanitize_postscript(base)

    for nid in (16, 1):
        raw = font["name"].getDebugName(nid)
        if raw and raw.strip():
            base = strip_variable_tokens(raw) or raw
            compact = sanitize_postscript(base)
            if compact:
                return compact

    return "Font"


def compose_postscript_instance_name(family_prefix: str, subfamily_name: str) -> str:
    """
    Build PostScript name for one fvar instance.

    Matches common VF patterns: FamilyPrefix-CondensedBold (no spaces in style).
    """
    prefix = sanitize_postscript(family_prefix.strip()) or "Font"
    style = sanitize_postscript(subfamily_name.strip())
    if not style or style.lower() == "regular":
        return f"{prefix}-Regular"
    return f"{prefix}-{style}"


def compose_instance_name(
    axis_values: tuple,
    elided_fallback_name: str = "Regular",
    *,
    naming_order: Optional[List[str]] = None,
    clarifiers: Optional[Dict[str, str]] = None,
    axis_tags: Optional[List[str]] = None,
    axes_json: Optional[List[dict]] = None,
    file_stat_registration: Optional[Dict[str, float]] = None,
) -> str:
    """Build subfamily string from one axis-value combination (product tuple)."""
    if naming_order is not None and axis_tags is not None:
        by_tag = {tag: av for tag, av in zip(axis_tags, axis_values)}
        return compose_name_from_order(
            naming_order,
            by_tag,
            clarifiers or {},
            elided_fallback_name,
            axes_json=axes_json,
            file_stat_registration=file_stat_registration,
        )
    parts = [av.name for av in axis_values if not av.elidable]
    return " ".join(parts) if parts else elided_fallback_name


def enumerate_instance_names(
    axis_defs: List[AxisDef],
    elided_fallback_name: str = "Regular",
    *,
    naming_order: Optional[List[str]] = None,
    clarifiers: Optional[Dict[str, str]] = None,
    axes_json: Optional[List[dict]] = None,
    file_stat_registration: Optional[Dict[str, float]] = None,
    included_instance_keys: Optional[List[str]] = None,
    pinned_coords: Optional[Dict[str, float]] = None,
) -> List[str]:
    """Cartesian product of axis values into composed instance subfamily names."""
    if not axis_defs:
        return []

    from vfcommit_lib.request_bridge import instance_key

    value_lists = [ad.values for ad in axis_defs]
    tag_list = [ad.tag for ad in axis_defs]
    names: List[str] = []
    seen: Set[str] = set()
    allowed = set(included_instance_keys) if included_instance_keys else None
    pinned = pinned_coords or {}

    for combo in itertools.product(*value_lists):
        coords = {tag: float(av.value) for tag, av in zip(tag_list, combo)}
        if allowed is not None:
            merged = dict(coords)
            for tag, value in pinned.items():
                merged.setdefault(tag, float(value))
            if instance_key(merged) not in allowed:
                continue
        composed = compose_instance_name(
            combo,
            elided_fallback_name,
            naming_order=naming_order,
            clarifiers=clarifiers,
            axis_tags=tag_list,
            axes_json=axes_json,
            file_stat_registration=file_stat_registration,
        )
        if composed not in seen:
            seen.add(composed)
            names.append(composed)

    return names


def build_allocation_plan(
    font: TTFont,
    ot_labels: List[OTLabelRecord],
    axis_defs: List[AxisDef],
    elided_fallback_name: str = "Regular",
    *,
    allocate_postscript_names: bool = True,
    instance_axis_defs: List[AxisDef] | None = None,
    naming_order: List[str] | None = None,
    clarifiers: Dict[str, str] | None = None,
    family_ps_prefix: str | None = None,
    axes_json: List[dict] | None = None,
    file_stat_registration: Dict[str, float] | None = None,
    compound_defs: List[CompoundStatValueDef] | None = None,
    included_instance_keys: List[str] | None = None,
    pinned_coords: Dict[str, float] | None = None,
) -> NameIDPlan:
    """Produce nameID allocation plan without modifying the font."""
    grid_axes = instance_axis_defs if instance_axis_defs is not None else axis_defs
    order = naming_order or []
    clarifier_map = clarifiers or {}
    axes_payload = axes_json or []
    registration = file_stat_registration or {}
    preserved_compounds = compound_defs or []
    used = audit_nameids(font, ot_labels)
    ot_protected_ids: Set[int] = {rec.name_id for rec in ot_labels if rec.name_id >= 256}
    preserved_axis_name_ids = preserved_design_axis_name_ids(
        font, {axis_def.tag for axis_def in axis_defs}
    )
    # Only OpenType feature labels must survive wipe; fvar/STAT instance IDs are reclaimed from 256.
    protected = {nid: used[nid] for nid in ot_protected_ids if nid in used}
    for nid in preserved_axis_name_ids:
        if nid in used:
            protected[nid] = used[nid]

    cursor = 256

    def alloc_id() -> int:
        nonlocal cursor
        while cursor in ot_protected_ids or cursor in preserved_axis_name_ids:
            cursor += 1
        nid = cursor
        cursor += 1
        return nid

    free_start = cursor

    # 1. Axis display names (reallocated fresh at 256+, decoupled from 2/6/17)
    axis_name_ids: Dict[str, int] = {}
    axis_names: Dict[str, str] = {}
    for axis_def in axis_defs:
        if axis_def.tag not in axis_name_ids:
            axis_name_ids[axis_def.tag] = alloc_id()
            axis_names[axis_def.tag] = axis_def.display_name or axis_def.tag

    # 2. STAT axis value names
    axis_value_ids: Dict[Tuple[str, float], int] = {}
    stat_value_labels: Dict[Tuple[str, float], str] = {}
    for axis_def in axis_defs:
        for av_def in axis_def.values:
            key = (axis_def.tag, av_def.value)
            if key not in axis_value_ids:
                axis_value_ids[key] = alloc_id()
                stat_value_labels[key] = compose_name_from_order(
                    order,
                    {axis_def.tag: av_def},
                    clarifier_map,
                    elided_fallback_name,
                    axes_json=axes_payload,
                    file_stat_registration=registration,
                )

    compound_value_ids: Dict[str, int] = {}
    compound_value_names: Dict[str, str] = {}
    for compound in preserved_compounds:
        compound_value_ids[compound.id] = alloc_id()
        compound_value_names[compound.id] = compound.name

    if allocate_postscript_names:
        override = (family_ps_prefix or "").strip()
        family_prefix = override or derive_family_ps_prefix(font)
    else:
        family_prefix = ""
    instance_ids: Dict[str, int] = {}
    instance_postscript_names: Dict[str, str] = {}
    instance_postscript_ids: Dict[str, int] = {}
    ps_string_to_id: Dict[str, int] = {}

    for composed_name in enumerate_instance_names(
        grid_axes,
        elided_fallback_name,
        naming_order=order,
        clarifiers=clarifier_map,
        axes_json=axes_payload,
        file_stat_registration=registration,
        included_instance_keys=included_instance_keys,
        pinned_coords=pinned_coords,
    ):
        if composed_name not in instance_ids:
            instance_ids[composed_name] = alloc_id()

        if not allocate_postscript_names:
            continue

        ps_name = compose_postscript_instance_name(family_prefix, composed_name)
        instance_postscript_names[composed_name] = ps_name
        if ps_name not in ps_string_to_id:
            ps_string_to_id[ps_name] = alloc_id()
        instance_postscript_ids[composed_name] = ps_string_to_id[ps_name]

    # Elided fallback name: reuse the all-elided instance ID when present,
    # otherwise allocate a dedicated 256+ ID. Never falls back to ID 2.
    if elided_fallback_name in instance_ids:
        elided_fallback_id = instance_ids[elided_fallback_name]
    else:
        elided_fallback_id = alloc_id()

    if cursor <= free_start:
        free_end = free_start - 1
    else:
        free_end = cursor - 1

    return NameIDPlan(
        protected=protected,
        axis_value_ids=axis_value_ids,
        instance_ids=instance_ids,
        axis_name_ids=axis_name_ids,
        axis_names=axis_names,
        instance_postscript_names=instance_postscript_names,
        instance_postscript_ids=instance_postscript_ids,
        family_ps_prefix=family_prefix,
        elided_fallback_name=elided_fallback_name,
        elided_fallback_id=elided_fallback_id,
        stat_value_labels=stat_value_labels,
        naming_order=order,
        clarifiers=clarifier_map,
        compound_value_ids=compound_value_ids,
        compound_value_names=compound_value_names,
        axes_json=axes_payload,
        file_stat_registration=registration,
        free_start=free_start,
        free_end=free_end,
    )


def check_for_collisions(plan: NameIDPlan, font: TTFont) -> List[str]:
    """Verify planned nameIDs do not overlap protected IDs."""
    del font  # reserved for future font-aware checks
    collisions: List[str] = []
    all_planned: Dict[int, str] = {
        **{nid: name for name, nid in plan.instance_ids.items()},
        **{nid: f"{tag}={val}" for (tag, val), nid in plan.axis_value_ids.items()},
        **{nid: f"axis name [{tag}]" for tag, nid in plan.axis_name_ids.items()},
    }
    for composed, nid in plan.instance_postscript_ids.items():
        ps = plan.instance_postscript_names.get(composed, "")
        all_planned[nid] = f"PS:{ps}"
    for nid, description in all_planned.items():
        if nid < 256:
            collisions.append(
                f"nameID {nid} planned for '{description}' is below 256 "
                "(variable naming must live at 256+)"
            )
    for nid, description in all_planned.items():
        if nid in plan.protected:
            collisions.append(
                f"nameID {nid} planned for '{description}' "
                f"but protected as: {plan.protected[nid]}"
            )
    return collisions


__all__ = [
    "AxisValueDef",
    "AxisDef",
    "CompoundStatValueDef",
    "NameIDPlan",
    "audit_nameids",
    "build_allocation_plan",
    "check_for_collisions",
    "compose_instance_name",
    "compose_postscript_instance_name",
    "derive_family_ps_prefix",
    "enumerate_instance_names",
    "preserved_design_axis_name_ids",
]
