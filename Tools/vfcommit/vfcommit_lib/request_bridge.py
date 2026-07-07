"""Map CommitRequest JSON to vfcommit axis models."""

from __future__ import annotations

from typing import Any, Dict, List, Set

from vfcommit_lib.nameid_allocator import AxisDef, AxisValueDef, CompoundStatValueDef


def instance_key(coords: Dict[str, float]) -> str:
    """Stable instance key (tags sorted alphabetically)."""
    return "|".join(f"{tag}:{_format_coord(value)}" for tag, value in sorted(coords.items()))


def _format_coord(value: float) -> str:
    if value == int(value):
        return str(int(value))
    return str(value)


def axis_defs_from_request(axes: List[Dict[str, Any]]) -> List[AxisDef]:
    """Build AxisDef list from CommitRequest.axes JSON."""
    result: List[AxisDef] = []
    for axis in axes:
        values = [
            AxisValueDef(
                value=float(stop["value"]),
                name=str(stop["name"]),
                elidable=bool(stop.get("elidable", False)),
                stat_format=int(stop.get("stat_format", 1)),
                range_min=stop.get("range_min"),
                range_max=stop.get("range_max"),
                linked_value=stop.get("linked_value"),
                older_sibling=bool(stop.get("older_sibling", False)),
            )
            for stop in axis.get("values", [])
        ]
        result.append(
            AxisDef(
                tag=str(axis["tag"]),
                display_name=str(axis.get("display_name") or axis["tag"]),
                min_value=float(axis.get("min", values[0].value if values else 0)),
                default_value=float(axis.get("default", values[0].value if values else 0)),
                max_value=float(axis.get("max", values[-1].value if values else 0)),
                values=values,
                stat_format_override=1,
            )
        )
    return result


def compound_stat_values_from_request(
    values: List[Dict[str, Any]],
) -> List[CompoundStatValueDef]:
    """Build preserved format 4 entries from CommitRequest.compound_stat_values."""
    result: List[CompoundStatValueDef] = []
    for item in values:
        axis_indices = [int(index) for index in (item.get("axis_indices") or [])]
        axis_values = [float(value) for value in (item.get("axis_values") or [])]
        if not axis_indices:
            coords = item.get("coords") or {}
            axis_indices = list(range(len(coords)))
            axis_values = [float(coords[tag]) for tag in sorted(coords.keys())]
        if not axis_indices:
            continue
        result.append(
            CompoundStatValueDef(
                id=str(item["id"]),
                axis_indices=axis_indices,
                axis_values=axis_values,
                name=str(item.get("name") or ""),
                elidable=bool(item.get("elidable", False)),
                older_sibling=bool(item.get("older_sibling", False)),
            )
        )
    return result


def grid_axis_defs(axis_defs: List[AxisDef], axes_json: List[Dict[str, Any]]) -> List[AxisDef]:
    """Axes that participate in the fvar instance cartesian product."""
    instance_tags = {
        str(axis["tag"])
        for axis in axes_json
        if str(axis.get("role", "instance")) == "instance"
    }
    return [axis for axis in axis_defs if axis.tag in instance_tags]


def count_included_instances(
    grid_axes: List[AxisDef],
    included_keys: List[str],
    pinned_coords: Dict[str, float] | None = None,
) -> int:
    """Count fvar instances after optional key filter."""
    if not grid_axes:
        return 0
    if not included_keys:
        total = 1
        for axis in grid_axes:
            total *= len(axis.values)
        return total

    allowed = set(included_keys)
    count = 0
    for coords in _coord_combinations(grid_axes):
        if _instance_key_with_pinned(coords, pinned_coords) in allowed:
            count += 1
    return count


def _instance_key_with_pinned(
    coords: Dict[str, float],
    pinned_coords: Dict[str, float] | None,
) -> str:
    merged = dict(coords)
    if pinned_coords:
        for tag, value in pinned_coords.items():
            merged.setdefault(tag, float(value))
    return instance_key(merged)


def _coord_combinations(grid_axes: List[AxisDef]):
    import itertools

    tag_list = [axis.tag for axis in grid_axes]
    value_lists = [axis.values for axis in grid_axes]
    for combo in itertools.product(*value_lists):
        yield {tag: float(stop.value) for tag, stop in zip(tag_list, combo)}


def pinned_coords(axes_json: List[Dict[str, Any]]) -> Dict[str, float]:
    """Default coordinates for non-instance axes (excludes design_record_only)."""
    pinned: Dict[str, float] = {}
    for axis in axes_json:
        role = str(axis.get("role", "instance"))
        if role == "instance" or role == "design_record_only":
            continue
        values = axis.get("values") or []
        if len(values) == 1:
            pinned[str(axis["tag"])] = float(values[0]["value"])
        elif axis.get("default") is not None:
            pinned[str(axis["tag"])] = float(axis["default"])
        elif values:
            pinned[str(axis["tag"])] = float(values[0]["value"])
    return pinned
