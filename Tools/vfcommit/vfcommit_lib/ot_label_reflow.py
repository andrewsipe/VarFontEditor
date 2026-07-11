#!/usr/bin/env python3
"""
OpenType feature label nameID reflow — scan, classify, remap, and patch GSUB/GPOS.

After a reflow commit, the *source* high nameIDs (pre-copy) are intentionally left in
the name table: they stay protected through pre-wipe so copy_name_records_for_id can
read every platform record, and are not deleted in the same pass. GSUB/GPOS already
point at the new 256+ IDs. Stale source slots are classified as orphans on the next
commit (classify_name_ids → pre-wipe) — a deliberate self-healing step, not an oversight.
Inspecting the font in TTX immediately after reflow may therefore show duplicate
strings at old and new IDs until a follow-up save.
"""

from __future__ import annotations

import re
from copy import deepcopy
from dataclasses import dataclass, field
from typing import Dict, List, Set

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._n_a_m_e import NameRecord

from vfcommit_lib.logging_config import get_logger
from vfcommit_lib.nameid_allocator import (
    AxisDef,
    audit_nameids,
    preserved_design_axis_name_ids,
)
from vfcommit_lib.ot_label_scanner import OTLabelRecord, scan_ot_label_nameids
from vfcommit_lib.stat_builder import _wipe_existing_table_data

logger = get_logger(__name__)

_RE_STYLESET = re.compile(r"^ss\d{2}$")
_RE_CHARVAR = re.compile(r"^cv\d{2}$")


@dataclass
class OTLabelSite:
    """A mutable GSUB/GPOS FeatureParams nameID reference site."""

    name_id: int
    table: str
    feature_tag: str
    field: str
    feature_record: object
    params: object
    cv_offset: int | None = None


@dataclass
class NameIDClassification:
    ot_ids: Set[int] = field(default_factory=set)
    stat_fvar_ids: Set[int] = field(default_factory=set)
    preserved_axis_ids: Set[int] = field(default_factory=set)
    orphan_ids: Set[int] = field(default_factory=set)


def scan_ot_label_sites(font: TTFont) -> Dict[int, List[OTLabelSite]]:
    """Walk GSUB/GPOS; return sites grouped by unique nameID."""
    groups: Dict[int, List[OTLabelSite]] = {}
    for table_tag in ("GSUB", "GPOS"):
        if table_tag not in font:
            continue
        try:
            feature_list = font[table_tag].table.FeatureList
            if feature_list is None:
                continue
            for rec in feature_list.FeatureRecord:
                _extract_sites(rec, table_tag, groups)
        except AttributeError:
            logger.debug("%s has no FeatureList", table_tag)
        except Exception as exc:
            logger.warning("Error scanning %s for OT label sites: %s", table_tag, exc)
    return groups


def _add_site(groups: Dict[int, List[OTLabelSite]], site: OTLabelSite) -> None:
    groups.setdefault(site.name_id, []).append(site)


def _extract_sites(feature_record, table_tag: str, groups: Dict[int, List[OTLabelSite]]) -> None:
    tag = feature_record.FeatureTag
    params = getattr(feature_record.Feature, "FeatureParams", None)
    if params is None:
        return

    try:
        if _RE_STYLESET.match(tag):
            _collect_site(params, "FeatureNameID", tag, table_tag, feature_record, groups)
            _collect_site(params, "UINameID", tag, table_tag, feature_record, groups)
        elif _RE_CHARVAR.match(tag):
            _collect_site(params, "LabelNameID", tag, table_tag, feature_record, groups)
            _collect_site(params, "TooltipTextNameID", tag, table_tag, feature_record, groups)
            _collect_site(params, "SampleTextNameID", tag, table_tag, feature_record, groups)
            n = getattr(params, "NumNamedParameters", 0) or 0
            first = getattr(params, "FirstParamUILabelNameID", None)
            if first is not None and n > 0:
                for offset in range(n):
                    nid = int(first) + offset
                    _add_site(
                        groups,
                        OTLabelSite(
                            name_id=nid,
                            table=table_tag,
                            feature_tag=tag,
                            field=f"FirstParamUILabelNameID+{offset}",
                            feature_record=feature_record,
                            params=params,
                            cv_offset=offset,
                        ),
                    )
        elif tag == "size":
            nid = getattr(params, "SubFamilyID", 0) or 0
            if nid > 0:
                _collect_site(params, "SubFamilyID", tag, table_tag, feature_record, groups)
    except Exception as exc:
        logger.warning("Skipping malformed FeatureParams for %s/%s: %s", table_tag, tag, exc)


def _collect_site(
    params,
    field: str,
    feature_tag: str,
    table_tag: str,
    feature_record,
    groups: Dict[int, List[OTLabelSite]],
) -> None:
    nid = getattr(params, field, None)
    if nid is None or nid == 0:
        return
    _add_site(
        groups,
        OTLabelSite(
            name_id=int(nid),
            table=table_tag,
            feature_tag=feature_tag,
            field=field,
            feature_record=feature_record,
            params=params,
            cv_offset=None,
        ),
    )


def patch_ot_label_site(site: OTLabelSite, new_id: int) -> None:
    """Write new_id into the FeatureParams field referenced by site."""
    if site.cv_offset is not None:
        first = getattr(site.params, "FirstParamUILabelNameID", None)
        if first is None:
            return
        setattr(site.params, "FirstParamUILabelNameID", int(new_id) - site.cv_offset)
        site.name_id = new_id
        return
    setattr(site.params, site.field, int(new_id))
    site.name_id = new_id


def patch_ot_label_sites(sites: List[OTLabelSite], new_id: int) -> None:
    for site in sites:
        patch_ot_label_site(site, new_id)


def classify_name_ids(
    font: TTFont,
    ot_groups: Dict[int, List[OTLabelSite]],
    axis_defs: List[AxisDef],
) -> NameIDClassification:
    ot_ids = set(ot_groups.keys())
    flat_labels = [
        OTLabelRecord(
            name_id=nid,
            string="",
            feature_tag=sites[0].feature_tag,
            table=sites[0].table,
            field=sites[0].field,
        )
        for nid, sites in ot_groups.items()
        if sites
    ]
    audit = audit_nameids(font, flat_labels)
    stat_fvar_ids = {
        nid
        for nid, desc in audit.items()
        if nid >= 256 and ("fvar" in desc or "STAT" in desc)
    }
    preserved_axis_ids = preserved_design_axis_name_ids(
        font, {axis_def.tag for axis_def in axis_defs}
    )
    orphan_ids = {
        nid
        for nid, desc in audit.items()
        if nid >= 256 and desc.startswith('name table only')
    }
    return NameIDClassification(
        ot_ids=ot_ids,
        stat_fvar_ids=stat_fvar_ids,
        preserved_axis_ids=preserved_axis_ids,
        orphan_ids=orphan_ids,
    )


def detect_reflow_blockers(classification: NameIDClassification) -> List[str]:
    shared = classification.ot_ids & classification.stat_fvar_ids
    if not shared:
        return []
    examples = ", ".join(str(nid) for nid in sorted(shared)[:5])
    suffix = "..." if len(shared) > 5 else ""
    return [
        f"OpenType feature labels share nameIDs with STAT/fvar ({examples}{suffix}); "
        "reflow cannot proceed"
    ]


def build_reflow_pre_wipe_protected(
    font: TTFont,
    ot_groups: Dict[int, List[OTLabelSite]],
    axis_defs: List[AxisDef],
) -> Set[int]:
    old_ot_ids = set(ot_groups.keys())
    preserved_axes = preserved_design_axis_name_ids(
        font, {axis_def.tag for axis_def in axis_defs}
    )
    return old_ot_ids | preserved_axes


def pre_wipe_for_reflow(font: TTFont, protected_ids: Set[int]) -> None:
    _wipe_existing_table_data(font, protected_ids)


def build_ot_reflow_plan(
    ot_groups: Dict[int, List[OTLabelSite]],
    *,
    start_id: int = 256,
) -> Dict[int, int]:
    """Map old_id -> new_id for OT-referenced IDs >= 256."""
    old_ids = sorted(nid for nid in ot_groups if nid >= 256)
    mapping: Dict[int, int] = {}
    cursor = start_id
    for old_id in old_ids:
        mapping[old_id] = cursor
        cursor += 1
    return mapping


def ot_reflow_end_from_groups(ot_groups: Dict[int, List[OTLabelSite]]) -> int:
    high_ot = [nid for nid in ot_groups if nid >= 256]
    return max(high_ot) if high_ot else 255


def copy_name_records_for_id(font: TTFont, old_id: int, new_id: int) -> None:
    """Duplicate every platform/encoding/language record from old_id to new_id."""
    if "name" not in font:
        return
    name_table = font["name"]
    copies: List[NameRecord] = []
    for rec in name_table.names:
        if rec.nameID != old_id:
            continue
        new_rec = NameRecord()
        new_rec.nameID = new_id
        new_rec.platformID = rec.platformID
        new_rec.platEncID = rec.platEncID
        new_rec.langID = rec.langID
        new_rec.string = deepcopy(rec.string)
        copies.append(new_rec)
    name_table.names.extend(copies)


def apply_ot_reflow(
    font: TTFont,
    mapping: Dict[int, int],
    ot_groups: Dict[int, List[OTLabelSite]],
) -> int:
    """
    Copy name records and patch GSUB/GPOS after pre-wipe.

    Returns the highest OT nameID in use after reflow.
    """
    if mapping:
        for old_id, new_id in sorted(mapping.items(), key=lambda kv: kv[1]):
            copy_name_records_for_id(font, old_id, new_id)
        for old_id, new_id in mapping.items():
            patch_ot_label_sites(ot_groups.get(old_id, []), new_id)
        return max(mapping.values())
    return ot_reflow_end_from_groups(ot_groups)


def build_ot_reflow_diff_entries(
    mapping: Dict[int, int],
    ot_groups: Dict[int, List[OTLabelSite]],
    font: TTFont,
) -> List[Dict[str, object]]:
    entries: List[Dict[str, object]] = []
    for old_id, new_id in sorted(mapping.items(), key=lambda kv: kv[1]):
        sites = ot_groups.get(old_id, [])
        feature = sites[0].feature_tag if sites else ""
        string = font["name"].getDebugName(new_id) or font["name"].getDebugName(old_id) or ""
        entries.append(
            {
                "from": old_id,
                "to": new_id,
                "string": string,
                "feature": feature,
            }
        )
    return entries


__all__ = [
    "NameIDClassification",
    "OTLabelSite",
    "apply_ot_reflow",
    "build_ot_reflow_diff_entries",
    "build_ot_reflow_plan",
    "build_reflow_pre_wipe_protected",
    "classify_name_ids",
    "copy_name_records_for_id",
    "detect_reflow_blockers",
    "ot_reflow_end_from_groups",
    "patch_ot_label_site",
    "patch_ot_label_sites",
    "pre_wipe_for_reflow",
    "scan_ot_label_sites",
]
