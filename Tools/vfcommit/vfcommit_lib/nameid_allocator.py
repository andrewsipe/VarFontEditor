#!/usr/bin/env python3
"""
NameID audit and allocation for variable-font STAT/fvar table editing.
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Set, Tuple

from fontTools.ttLib import TTFont

from vfcommit_lib.logging_config import get_logger
from vfcommit_lib.name_policies import is_usable_prefix, sanitize_postscript, strip_variable_tokens
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
    "slnt": "slope",
    "wdth": "width",
    "opsz": "optical",
}

DEFAULT_CLARIFIER_TOKENS: List[str] = list(CLARIFIER_TOKEN_TO_CATEGORY.keys())
PSHYPHEN_TOKEN = "@pshyphen"
CODE_TOKEN = "@code"


def ensure_postscript_hyphen(order: List[str]) -> List[str]:
    """Ensure exactly one PS hyphen marker (default: first in chain)."""
    without = [token for token in order if token != PSHYPHEN_TOKEN]
    if PSHYPHEN_TOKEN in order:
        insert_at = min(order.index(PSHYPHEN_TOKEN), len(without))
        return without[:insert_at] + [PSHYPHEN_TOKEN] + without[insert_at:]
    return [PSHYPHEN_TOKEN] + without


def sanitize_instance_code(raw: Any) -> Optional[str]:
    """Keep up to two alphanumeric characters; empty → None."""
    if raw is None:
        return None
    filtered = "".join(ch for ch in str(raw) if ch.isalnum())[:2]
    return filtered or None


def compose_instance_code(
    axes_json: Optional[List[dict]],
    axis_values_by_tag: Dict[str, "AxisValueDef"],
    registration: Optional[Dict[str, float]] = None,
    *,
    file_role: Optional[dict] = None,
    naming_order: Optional[List[str]] = None,
) -> Optional[str]:
    """Concatenate per-stop codes in Axis Tree order (instance + registration)."""
    del file_role, naming_order  # retained for call-site compatibility
    parts: List[str] = []
    reg = registration or {}
    for axis in axes_json or []:
        role = str(axis.get("role", "instance"))
        tag = str(axis["tag"])
        code: Optional[str] = None
        if role == "instance":
            av = axis_values_by_tag.get(tag)
            if av is not None:
                code = sanitize_instance_code(getattr(av, "code", None))
        elif role == "design_record_only":
            reg_value = reg.get(tag)
            if reg_value is not None:
                stop = _stop_for_axis_json(axis, reg_value)
                if stop is not None:
                    code = sanitize_instance_code(stop.get("code"))
        if code:
            parts.append(code)

    return "".join(parts) if parts else None


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


def clarifier_categories_covered_by_axes(
    axes_json: Optional[List[dict]],
    file_stat_registration: Optional[Dict[str, float]],
) -> set[str]:
    """Categories already represented by instance-axis or registration stop codes."""
    covered = clarifier_categories_covered_by_registration(axes_json, file_stat_registration)
    for axis in axes_json or []:
        tag = str(axis.get("tag") or "")
        role = str(axis.get("role", "instance"))
        if tag == "ital":
            covered.add("slope")
        elif tag == "slnt" and role == "instance":
            covered.add("slope")
        elif tag == "wdth" and role == "instance":
            covered.add("width")
        elif tag == "opsz" and role == "instance":
            covered.add("optical")
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


def parse_clarifier_codes(file_role: Optional[dict]) -> Dict[str, str]:
    """Map clarifier category to optional code fragment."""
    result: Dict[str, str] = {}
    if not file_role:
        return result
    for item in file_role.get("clarifiers") or []:
        category = str(item.get("category") or "").strip()
        code = sanitize_instance_code(item.get("code"))
        if category and code:
            result[category] = code
    return result


def effective_elided_fallback(naming: dict, file_role: Optional[dict]) -> str:
    override = (file_role or {}).get("elided_fallback_override")
    if override:
        return str(override)
    return str(naming.get("elided_fallback") or "Regular")


def naming_order_with_defaults(naming: dict) -> List[str]:
    """Match Swift ``NamingPolicy.mergedOrder``: ensure PS hyphen only.

    Clarifier tokens are not auto-appended — file identity lives on naming axes.
    Legacy projects may still list ``@width`` / ``@slope`` explicitly in order.
    """
    order = list(naming.get("order") or [])
    return ensure_postscript_hyphen(order)


def compose_name_from_order(
    naming_order: List[str],
    axis_values_by_tag: Dict[str, AxisValueDef],
    clarifiers: Dict[str, str],
    elided_fallback_name: str = "Regular",
    *,
    axes_json: Optional[List[dict]] = None,
    file_stat_registration: Optional[Dict[str, float]] = None,
    file_role: Optional[dict] = None,
) -> str:
    """Interleave axis stop names and per-file clarifier labels."""
    axis_by_tag = {str(axis["tag"]): axis for axis in (axes_json or [])}
    registration = file_stat_registration or {}
    covered_clarifiers = clarifier_categories_covered_by_registration(axes_json, registration)
    parts: List[str] = []

    for token in naming_order:
        if token == PSHYPHEN_TOKEN:
            continue
        if token == CODE_TOKEN:
            code = compose_instance_code(
                axes_json,
                axis_values_by_tag,
                registration,
                file_role=file_role,
                naming_order=naming_order,
            )
            if code:
                parts.append(code)
            continue
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


def compose_postscript_style_from_order(
    naming_order: List[str],
    axis_values_by_tag: Dict[str, AxisValueDef],
    clarifiers: Dict[str, str],
    elided_fallback_name: str = "Regular",
    *,
    axes_json: Optional[List[dict]] = None,
    file_stat_registration: Optional[Dict[str, float]] = None,
    file_role: Optional[dict] = None,
) -> str:
    """Build the style segment of an fvar PostScript name using `@pshyphen` splits."""
    axis_by_tag = {str(axis["tag"]): axis for axis in (axes_json or [])}
    registration = file_stat_registration or {}
    covered_clarifiers = clarifier_categories_covered_by_registration(axes_json, registration)
    before: List[str] = []
    after: List[str] = []
    past_hyphen = False

    for token in naming_order:
        if token == PSHYPHEN_TOKEN:
            past_hyphen = True
            continue

        part: Optional[str] = None
        if token == CODE_TOKEN:
            part = compose_instance_code(
                axes_json,
                axis_values_by_tag,
                registration,
                file_role=file_role,
                naming_order=naming_order,
            )
        elif token in CLARIFIER_TOKEN_TO_CATEGORY:
            category = CLARIFIER_TOKEN_TO_CATEGORY[token]
            if category not in covered_clarifiers:
                label = clarifiers.get(category)
                if label:
                    part = label
        else:
            axis_json = axis_by_tag.get(token)
            if axis_json and str(axis_json.get("role")) == "design_record_only":
                reg_value = registration.get(token)
                if reg_value is not None:
                    stop = _stop_for_axis_json(axis_json, reg_value)
                    if stop and not bool(stop.get("elidable", False)):
                        part = str(stop["name"])
            else:
                av = axis_values_by_tag.get(token)
                if av is not None and not av.elidable:
                    part = av.name

        if not part:
            continue
        if past_hyphen:
            after.append(part)
        else:
            before.append(part)

    before_text = sanitize_postscript("".join(before))
    after_text = sanitize_postscript("".join(after))
    if not before_text:
        return after_text or sanitize_postscript(elided_fallback_name)
    if not after_text:
        return before_text
    return f"{before_text}-{after_text}"


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
    code: Optional[str] = None


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
    nameid_strategy: str = "preserve"
    ot_reflow_end: int = 255
    # Windows English (3,1,0x0409) low-ID patches. Empty string deletes that record.
    # ID 25 is written via family_ps_prefix.
    windows_name_patches: List[Dict[str, Any]] = field(default_factory=list)


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


def _stat_slot_key(tag: str, value: float) -> Tuple[str, float]:
    """Normalize axis coordinate for STAT slot lookup."""
    if float(value).is_integer():
        return (tag, float(int(value)))
    return (tag, float(value))


def _snapshot_role_name_ids(font: TTFont) -> Dict[str, object]:
    """
    Existing nameIDs bound to semantic roles in STAT/fvar.

    Used to reuse stable IDs when strings are unchanged (avoids false reflow on review).
    """
    axis_name_ids: Dict[str, int] = {}
    axis_value_ids: Dict[Tuple[str, float], int] = {}
    elided_fallback_id: Optional[int] = None
    fvar_instances: Dict[str, Tuple[int, Optional[int]]] = {}

    if "STAT" in font:
        stat = font["STAT"].table
        idx_to_tag: Dict[int, str] = {}
        design = getattr(stat, "DesignAxisRecord", None)
        if design and design.Axis:
            for index, ax in enumerate(design.Axis):
                idx_to_tag[index] = ax.AxisTag
                axis_name_ids[ax.AxisTag] = ax.AxisNameID

        efb = getattr(stat, "ElidedFallbackNameID", 0) or 0
        if efb >= 256:
            elided_fallback_id = efb

        avarray = getattr(stat, "AxisValueArray", None)
        if avarray and avarray.AxisValue:
            for av in avarray.AxisValue:
                fmt = av.Format
                if fmt == 4:
                    continue
                tag = idx_to_tag.get(av.AxisIndex)
                if not tag:
                    continue
                if fmt == 1:
                    value = float(av.Value)
                elif fmt == 2:
                    value = float(av.NominalValue)
                elif fmt == 3:
                    value = float(av.Value)
                else:
                    continue
                axis_value_ids[_stat_slot_key(tag, value)] = av.ValueNameID

    if "fvar" in font:
        for inst in font["fvar"].instances:
            sf_id = inst.subfamilyNameID
            ps_raw = getattr(inst, "postscriptNameID", 0xFFFF)
            ps_id = None if ps_raw in (0xFFFF, 0, None) else int(ps_raw)
            sf_name = (font["name"].getDebugName(sf_id) or "").strip()
            if sf_name and sf_id >= 256:
                fvar_instances[sf_name] = (
                    sf_id,
                    ps_id if ps_id and ps_id >= 256 else None,
                )

    return {
        "axis_names": axis_name_ids,
        "axis_values": axis_value_ids,
        "elided_fallback": elided_fallback_id,
        "fvar_instances": fvar_instances,
    }


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
    if not is_usable_prefix(s):
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

    One hyphen separates the family-side prefix from the style tail.
    When the style segment contains an internal hyphen (@pshyphen split),
    the portion before that hyphen is concatenated onto the family prefix.
    """
    prefix = sanitize_postscript(family_prefix.strip()) or "Font"
    style = sanitize_postscript(subfamily_name.strip())
    if not style or style.lower() == "regular":
        return f"{prefix}-Regular"
    if "-" in style:
        before, after = style.split("-", 1)
        if after:
            return f"{prefix}{before}-{after}"
        return f"{prefix}-{before}"
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
    file_role: Optional[dict] = None,
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
            file_role=file_role,
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
    file_role: Optional[dict] = None,
) -> List[str]:
    """Cartesian product of axis values into composed instance subfamily names."""
    return [
        composed
        for composed, _ in iterate_instance_name_entries(
            axis_defs,
            elided_fallback_name,
            naming_order=naming_order,
            clarifiers=clarifiers,
            axes_json=axes_json,
            file_stat_registration=file_stat_registration,
            included_instance_keys=included_instance_keys,
            pinned_coords=pinned_coords,
            file_role=file_role,
        )
    ]


def iterate_instance_name_entries(
    axis_defs: List[AxisDef],
    elided_fallback_name: str = "Regular",
    *,
    naming_order: Optional[List[str]] = None,
    clarifiers: Optional[Dict[str, str]] = None,
    axes_json: Optional[List[dict]] = None,
    file_stat_registration: Optional[Dict[str, float]] = None,
    included_instance_keys: Optional[List[str]] = None,
    pinned_coords: Optional[Dict[str, float]] = None,
    file_role: Optional[dict] = None,
):
    """Yield `(composed_name, combo_by_tag)` for each included instance row."""
    if not axis_defs:
        return

    from vfcommit_lib.request_bridge import parse_instance_key

    value_lists = [ad.values for ad in axis_defs]
    tag_list = [ad.tag for ad in axis_defs]
    seen: Set[str] = set()
    pinned = pinned_coords or {}

    def _emit(combo):
        composed = compose_instance_name(
            combo,
            elided_fallback_name,
            naming_order=naming_order,
            clarifiers=clarifiers,
            axis_tags=tag_list,
            axes_json=axes_json,
            file_stat_registration=file_stat_registration,
            file_role=file_role,
        )
        if composed in seen:
            return
        seen.add(composed)
        combo_by_tag = {tag: av for tag, av in zip(tag_list, combo)}
        yield composed, combo_by_tag

    # Allowlist mode when keys are provided (including empty = include none).
    # ``None`` keeps the legacy “entire cartesian product” behavior for callers
    # that omit ``included_instance_keys``.
    if included_instance_keys is not None:
        if not included_instance_keys:
            return
        values_by_tag = {
            ad.tag: {float(av.value): av for av in ad.values}
            for ad in axis_defs
        }
        for key in included_instance_keys:
            try:
                coords = parse_instance_key(key)
            except ValueError:
                continue
            for tag, value in pinned.items():
                coords.setdefault(tag, float(value))
            combo = []
            ok = True
            for tag in tag_list:
                if tag not in coords:
                    ok = False
                    break
                av = values_by_tag.get(tag, {}).get(float(coords[tag]))
                if av is None:
                    ok = False
                    break
                combo.append(av)
            if not ok:
                continue
            yield from _emit(combo)
        return

    for combo in itertools.product(*value_lists):
        yield from _emit(combo)


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
    nameid_strategy: str = "preserve",
    ot_reflow_end: int | None = None,
    windows_name_patches: List[Dict[str, Any]] | None = None,
    file_role: dict | None = None,
) -> NameIDPlan:
    """Produce nameID allocation plan without modifying the font."""
    grid_axes = instance_axis_defs if instance_axis_defs is not None else axis_defs
    order = naming_order or []
    clarifier_map = clarifiers or {}
    axes_payload = axes_json or []
    registration = file_stat_registration or {}
    preserved_compounds = compound_defs or []
    role_payload = file_role
    reflow_mode = nameid_strategy == "reflow"
    ot_block_end = ot_reflow_end if ot_reflow_end is not None else 255
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

    role_snapshot = _snapshot_role_name_ids(font)
    snapshot_axis_names: Dict[str, int] = role_snapshot["axis_names"]  # type: ignore[assignment]
    snapshot_axis_values: Dict[Tuple[str, float], int] = role_snapshot["axis_values"]  # type: ignore[assignment]
    snapshot_elided_fallback: Optional[int] = role_snapshot["elided_fallback"]  # type: ignore[assignment]
    snapshot_fvar_instances: Dict[str, Tuple[int, Optional[int]]] = role_snapshot["fvar_instances"]  # type: ignore[assignment]

    cursor = ot_block_end + 1 if reflow_mode else 256
    claimed_ids: Set[int] = set()

    def _name_matches(nid: int, expected: str) -> bool:
        actual = font["name"].getDebugName(nid) or ""
        return actual.strip() == expected.strip()

    def _can_reuse(nid: Optional[int], expected: str) -> bool:
        if not nid or nid < 256:
            return False
        if reflow_mode and nid <= ot_block_end:
            return False
        if nid in claimed_ids:
            return False
        if not reflow_mode and nid in ot_protected_ids:
            return False
        if nid in preserved_axis_name_ids:
            return False
        return _name_matches(nid, expected)

    def alloc_id() -> int:
        nonlocal cursor
        while cursor in preserved_axis_name_ids or cursor in claimed_ids:
            cursor += 1
        if not reflow_mode:
            while (
                cursor in ot_protected_ids
                or cursor in preserved_axis_name_ids
                or cursor in claimed_ids
            ):
                cursor += 1
        nid = cursor
        claimed_ids.add(nid)
        cursor += 1
        return nid

    def alloc_or_reuse(reuse_nid: Optional[int], expected: str) -> int:
        if _can_reuse(reuse_nid, expected):
            claimed_ids.add(reuse_nid)
            return reuse_nid
        return alloc_id()

    free_start = cursor

    # Allocation order (OT feature labels ≥256 stay pinned; we flow around them):
    #   1. DesignAxisRecord names
    #   2. AxisValueArray names (+ preserved format-4 compounds)
    #   3. ElidedFallbackNameID
    #   4. fvar instance subfamily (+ PostScript) names
    # Each slot gets its own nameID — duplicate string text never shares an ID across
    # roles, so a later rename can't cascade through STAT / EFB / instances.

    # 1. Axis display names (reallocated fresh at 256+, decoupled from 2/6/17)
    axis_name_ids: Dict[str, int] = {}
    axis_names: Dict[str, str] = {}
    for axis_def in axis_defs:
        if axis_def.tag not in axis_name_ids:
            label = axis_def.display_name or axis_def.tag
            axis_name_ids[axis_def.tag] = alloc_or_reuse(
                snapshot_axis_names.get(axis_def.tag),
                label,
            )
            axis_names[axis_def.tag] = label

    # 2. STAT axis value names — use the axis-tree stop label as-is.
    # Instance-style composition (clarifiers, registration, elided-fallback) belongs
    # on fvar instance names only. Writing composed strings here is what turned
    # Playfair Italic's "Medium" / elided "Normal" into "Medium Italic" / "Italic".
    axis_value_ids: Dict[Tuple[str, float], int] = {}
    stat_value_labels: Dict[Tuple[str, float], str] = {}
    for axis_def in axis_defs:
        for av_def in axis_def.values:
            key = (axis_def.tag, av_def.value)
            if key not in axis_value_ids:
                label = (av_def.name or "").strip()
                if not label:
                    value = av_def.value
                    label = str(int(value)) if float(value).is_integer() else str(value)
                axis_value_ids[key] = alloc_or_reuse(
                    snapshot_axis_values.get(_stat_slot_key(axis_def.tag, av_def.value)),
                    label,
                )
                stat_value_labels[key] = label

    compound_value_ids: Dict[str, int] = {}
    compound_value_names: Dict[str, str] = {}
    for compound in preserved_compounds:
        compound_value_ids[compound.id] = alloc_id()
        compound_value_names[compound.id] = compound.name

    # 3. Elided fallback — always its own ID, never aliased to an instance nameID.
    elided_fallback_id = alloc_or_reuse(
        snapshot_elided_fallback,
        elided_fallback_name,
    )

    # 4. fvar instance names (+ PostScript)
    if allocate_postscript_names:
        override = (family_ps_prefix or "").strip()
        family_prefix = override or derive_family_ps_prefix(font)
    else:
        family_prefix = ""
    instance_ids: Dict[str, int] = {}
    instance_postscript_names: Dict[str, str] = {}
    instance_postscript_ids: Dict[str, int] = {}

    for composed_name, combo_by_tag in iterate_instance_name_entries(
        grid_axes,
        elided_fallback_name,
        naming_order=order,
        clarifiers=clarifier_map,
        axes_json=axes_payload,
        file_stat_registration=registration,
        included_instance_keys=included_instance_keys,
        pinned_coords=pinned_coords,
        file_role=role_payload,
    ):
        if composed_name not in instance_ids:
            reuse_sf, _ = snapshot_fvar_instances.get(composed_name, (None, None))
            instance_ids[composed_name] = alloc_or_reuse(reuse_sf, composed_name)

        if not allocate_postscript_names:
            continue

        ps_style = compose_postscript_style_from_order(
            order,
            combo_by_tag,
            clarifier_map,
            elided_fallback_name,
            axes_json=axes_payload,
            file_stat_registration=registration,
            file_role=role_payload,
        )
        ps_name = compose_postscript_instance_name(family_prefix, ps_style)
        instance_postscript_names[composed_name] = ps_name
        # Unique ID per instance slot even when the PS string text coincides.
        _, reuse_ps = snapshot_fvar_instances.get(composed_name, (None, None))
        instance_postscript_ids[composed_name] = alloc_or_reuse(reuse_ps, ps_name)

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
        nameid_strategy=nameid_strategy,
        ot_reflow_end=ot_block_end,
        windows_name_patches=list(windows_name_patches or []),
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
    if plan.elided_fallback_id:
        all_planned[plan.elided_fallback_id] = "elided fallback"
    for compound_id, nid in plan.compound_value_ids.items():
        all_planned[nid] = f"compound [{compound_id}]"
    for nid, description in all_planned.items():
        if nid < 256:
            collisions.append(
                f"nameID {nid} planned for '{description}' is below 256 "
                "(variable naming must live at 256+)"
            )
        if nid > 32767:
            collisions.append(
                f"nameID {nid} planned for '{description}' exceeds uint16 max 32767"
            )
    if plan.nameid_strategy == "reflow":
        for nid, description in all_planned.items():
            if nid <= plan.ot_reflow_end:
                collisions.append(
                    f"nameID {nid} planned for '{description}' "
                    f"collides with OT reflow block ending at {plan.ot_reflow_end}"
                )
    for nid, description in all_planned.items():
        if nid in plan.protected:
            collisions.append(
                f"nameID {nid} planned for '{description}' "
                f"but protected as: {plan.protected[nid]}"
            )
    # Every planned slot must own a distinct ID (STAT stop vs EFB vs instance, etc.).
    owners: Dict[int, List[str]] = {}
    for (tag, val), nid in plan.axis_value_ids.items():
        owners.setdefault(nid, []).append(f"STAT {tag}={val}")
    for tag, nid in plan.axis_name_ids.items():
        owners.setdefault(nid, []).append(f"axis name [{tag}]")
    for compound_id, nid in plan.compound_value_ids.items():
        owners.setdefault(nid, []).append(f"compound [{compound_id}]")
    if plan.elided_fallback_id:
        owners.setdefault(plan.elided_fallback_id, []).append("elided fallback")
    for name, nid in plan.instance_ids.items():
        owners.setdefault(nid, []).append(f"instance '{name}'")
    for composed, nid in plan.instance_postscript_ids.items():
        owners.setdefault(nid, []).append(f"PS '{composed}'")
    for nid, roles in owners.items():
        if len(roles) > 1:
            collisions.append(
                f"nameID {nid} shared by: {', '.join(roles)}"
            )
    return collisions


__all__ = [
    "AxisValueDef",
    "AxisDef",
    "CompoundStatValueDef",
    "NameIDPlan",
    "CODE_TOKEN",
    "PSHYPHEN_TOKEN",
    "audit_nameids",
    "build_allocation_plan",
    "check_for_collisions",
    "compose_instance_code",
    "compose_instance_name",
    "compose_name_from_order",
    "compose_postscript_instance_name",
    "compose_postscript_style_from_order",
    "derive_family_ps_prefix",
    "enumerate_instance_names",
    "preserved_design_axis_name_ids",
    "sanitize_instance_code",
]
