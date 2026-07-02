#!/usr/bin/env python3
"""Audit native → reference mapping for variable fonts (mirrors AxisReferenceMapping.swift)."""

from __future__ import annotations

import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

from fontTools.ttLib import TTFont


WGHT_NAMES = [
    ("ultrablack", 900), ("fat", 900),
    ("black", 900), ("heavy", 900),
        ("extrabold", 800), ("exbold", 800), ("ultrabold", 800), ("xbold", 800),
        ("semibold", 600), ("demibold", 600),
        ("bold", 700),
        ("medium", 500),
        ("semilight", 350),
        ("extralight", 200), ("ultralight", 200),
        ("hair", 100), ("hairline", 100),
        ("thin", 100),
        ("light", 300),
    ("normal", 400), ("regular", 400),
]

WDTH_NAMES = [
    ("ultraexpanded", 200), ("ultraexp", 200),
    ("extraexpanded", 150), ("extraexp", 150),
    ("expanded", 125), ("wide", 125),
    ("semiexpanded", 112.5), ("semiexp", 112.5),
    ("normal", 100), ("regular", 100),
    ("semicondensed", 87.5), ("semicond", 87.5),
    ("condensed", 75), ("cond", 75),
    ("extracondensed", 62.5), ("extracond", 62.5),
        ("ultracondensed", 50), ("ultracond", 50),
        ("supercondensed", 25), ("supercond", 25),
]

OPSZ_NAMES = [
    ("micro", 5),
    ("caption", 8),
    ("small", 10),
    ("text", 12), ("pica", 12),
    ("subhead", 14),
    ("display", 48),
]

LADDERS = {
    "wght": [100, 200, 300, 350, 400, 500, 600, 700, 800, 900],
    "wdth": [25, 50, 62.5, 75, 87.5, 100, 112.5, 125, 150, 200],
    "opsz": [6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 60, 72],
}

REGISTRY_NORMAL = {"wght": 400, "wdth": 100, "opsz": 12}
REGISTRY_LOW = {"wght": 100, "wdth": 50, "opsz": 6}
REGISTRY_HIGH = {"wght": 900, "wdth": 200, "opsz": 72}


def values_equal(a: float, b: float) -> bool:
    return abs(a - b) < 0.0001


def normalize_name(name: str) -> str:
    return name.lower().replace(" ", "").replace("-", "").replace("_", "")


def ref_from_name(name: str, tag: str) -> float | None:
    key = normalize_name(name)
    table = {"wght": WGHT_NAMES, "wdth": WDTH_NAMES, "opsz": OPSZ_NAMES}.get(tag, [])
    for needle, ref in table:
        if needle in key:
            return ref
    return None


def ref_from_value(value: float, tag: str) -> float | None:
    for ref in LADDERS.get(tag, []):
        if values_equal(value, ref):
            return ref
    return None


@dataclass
class Stop:
    name: str
    native: float
    elidable: bool
    stat_format: int
    range_min: float | None = None
    range_max: float | None = None
    linked_value: float | None = None


@dataclass
class Axis:
    tag: str
    min: float
    default: float
    max: float
    stops: list[Stop] = field(default_factory=list)


@dataclass
class Anchor:
    reference: float
    native: float


def supports_ladder(tag: str) -> bool:
    return tag in {"wght", "wdth"}


def looks_like_registry(axis: Axis) -> bool:
    if axis.tag == "opsz":
        return True
    if axis.tag == "wght":
        if axis.max > 925 or axis.min < 99:
            return True
        if axis.stops:
            return all(ref_from_value(s.native, axis.tag) is not None for s in axis.stops)
        return axis.max <= 901
    if axis.tag == "wdth":
        if values_equal(axis.min, 50) and axis.max >= 150 and axis.max <= 201:
            return True
        if values_equal(axis.default, 100):
            if axis.stops:
                return all(ref_from_value(s.native, axis.tag) is not None for s in axis.stops)
            return True
        return False
    return False


def infer_kind(axis: Axis) -> str:
    if not supports_ladder(axis.tag):
        return "identity"
    if looks_like_registry(axis):
        return "identity"
    if len(infer_anchors(axis)) >= 2:
        return "stop_anchored"
    if axis.default is not None or axis.stops:
        return "default_anchored"
    return "identity"


def infer_ref_for_stop(stop: Stop, tag: str) -> float | None:
    ref = ref_from_value(stop.native, tag)
    if ref is not None:
        return ref
    if stop.elidable:
        return REGISTRY_NORMAL.get(tag)
    return ref_from_name(stop.name, tag)


def infer_anchors(axis: Axis) -> list[Anchor]:
    anchors: list[Anchor] = []
    seen: set[str] = set()
    for stop in axis.stops:
        ref = infer_ref_for_stop(stop, axis.tag)
        if ref is None:
            continue
        key = f"{stop.native:.4f}"
        if key in seen:
            continue
        seen.add(key)
        anchors.append(Anchor(reference=ref, native=stop.native))
    return sorted(anchors, key=lambda a: a.native)


def interpolate(probe: float, inputs: list[float], outputs: list[float]) -> float:
    if len(inputs) < 2:
        return probe
    if probe <= inputs[0]:
        return outputs[0]
    if probe >= inputs[-1]:
        return outputs[-1]
    for i in range(len(inputs) - 1):
        lo, hi = inputs[i], inputs[i + 1]
        if lo <= probe <= hi:
            span = hi - lo
            if span <= 0:
                return outputs[i]
            ratio = (probe - lo) / span
            return outputs[i] + ratio * (outputs[i + 1] - outputs[i])
    return probe


def extrapolate(native: float, anchors: list[Anchor], above: bool) -> float | None:
    if len(anchors) < 2:
        return None
    if above:
        a, b = anchors[-2], anchors[-1]
        if b.native <= a.native:
            return None
        slope = (b.reference - a.reference) / (b.native - a.native)
        return b.reference + slope * (native - b.native)
    a, b = anchors[0], anchors[1]
    if b.native <= a.native:
        return None
    slope = (b.reference - a.reference) / (b.native - a.native)
    return a.reference + slope * (native - a.native)


def augment_endpoints(anchors: list[Anchor], axis: Axis) -> list[Anchor]:
    result = list(anchors)
    if not result:
        return result
    if result[0].native > axis.min + 0.0001:
        ref = extrapolate(axis.min, result, above=False) or REGISTRY_LOW.get(axis.tag, axis.min)
        result.insert(0, Anchor(reference=ref, native=axis.min))
    if result[-1].native < axis.max - 0.0001:
        ref = extrapolate(axis.max, result, above=True) or REGISTRY_HIGH.get(axis.tag, axis.max)
        result.append(Anchor(reference=ref, native=axis.max))
    dedup: dict[str, Anchor] = {}
    for a in result:
        dedup[f"{a.native:.4f}"] = a
    return sorted(dedup.values(), key=lambda a: a.native)


def effective_anchors(axis: Axis, kind: str) -> list[Anchor]:
    inferred = infer_anchors(axis)
    if len(inferred) >= 2:
        return augment_endpoints(inferred, axis)
    # default_anchored synthetic
    normal_native = next(
        (s.native for s in axis.stops if s.elidable),
        next(
            (s.native for s in axis.stops if ref_from_name(s.name, axis.tag) == REGISTRY_NORMAL.get(axis.tag)),
            axis.default,
        ),
    )
    ref_low = REGISTRY_LOW[axis.tag]
    ref_normal = REGISTRY_NORMAL[axis.tag]
    ref_high = REGISTRY_HIGH[axis.tag]
    if values_equal(normal_native, axis.min):
        return [
            Anchor(reference=ref_normal, native=axis.min),
            Anchor(reference=ref_high, native=axis.max),
        ]
    return [
        Anchor(reference=ref_low, native=axis.min),
        Anchor(reference=ref_normal, native=normal_native),
        Anchor(reference=ref_high, native=axis.max),
    ]


def native_to_reference(native: float, axis: Axis, kind: str) -> float:
    if kind == "identity":
        return native
    anchors = effective_anchors(axis, kind)
    if len(anchors) < 2:
        return native
    return interpolate(native, [a.native for a in anchors], [a.reference for a in anchors])


def get_name(font: TTFont, name_id: int) -> str:
    name_table = font["name"]
    for rec in name_table.names:
        if rec.nameID == name_id:
            try:
                return rec.toUnicode()
            except Exception:
                return str(rec)
    return f"nameID:{name_id}"


def load_font(path: Path) -> list[Axis]:
    font = TTFont(str(path), lazy=True)
    fvar = font["fvar"]
    stat = font["STAT"]
    axes_by_tag: dict[str, Axis] = {}
    for rec in fvar.axes:
        tag = rec.axisTag.strip()
        axes_by_tag[tag] = Axis(
            tag=tag,
            min=float(rec.minValue),
            default=float(rec.defaultValue),
            max=float(rec.maxValue),
        )

    design_axes = list(stat.table.DesignAxisRecord.Axis)
    for av in stat.table.AxisValueArray.AxisValue:
        if av.Format not in (1, 2, 3):
            continue
        axis_index = av.AxisIndex
        if axis_index >= len(design_axes):
            continue
        tag = design_axes[axis_index].AxisTag.strip()
        if tag not in axes_by_tag:
            continue
        flags = getattr(av, "Flags", 0) or 0
        elidable = bool(flags & 0x2)
        name = get_name(font, av.ValueNameID)

        if av.Format == 1:
            native = float(av.Value)
            stop = Stop(name=name, native=native, elidable=elidable, stat_format=1)
        elif av.Format == 2:
            native = float(av.NominalValue)
            stop = Stop(
                name=name,
                native=native,
                elidable=elidable,
                stat_format=2,
                range_min=float(av.RangeMinValue),
                range_max=float(av.RangeMaxValue),
            )
        elif av.Format == 3:
            native = float(av.Value)
            stop = Stop(
                name=name,
                native=native,
                elidable=elidable,
                stat_format=3,
                linked_value=float(av.LinkedValue),
            )
        else:
            continue
        axes_by_tag[tag].stops.append(stop)

    font.close()
    return [axes_by_tag[t] for t in sorted(axes_by_tag)]


def fmt(v: float) -> str:
    if abs(v - round(v)) < 0.05:
        return str(int(round(v)))
    return f"{v:.2f}"


def audit_file(path: Path) -> None:
    print(f"\n{'=' * 72}")
    print(path.name)
    print("=" * 72)
    try:
        axes = load_font(path)
    except Exception as exc:
        print(f"  ERROR: {exc}")
        return

    for axis in axes:
        if not axis.stops:
            continue
        kind = infer_kind(axis)
        anchors = effective_anchors(axis, kind) if kind != "identity" else []
        print(
            f"\n  {axis.tag}  fvar {fmt(axis.min)} – {fmt(axis.default)} – {fmt(axis.max)}"
            f"  mapping={kind}"
        )
        if anchors:
            anchor_str = ", ".join(f"{fmt(a.native)}→{fmt(a.reference)}" for a in anchors)
            print(f"    anchors: {anchor_str}")

        for stop in sorted(axis.stops, key=lambda s: s.native):
            ref = native_to_reference(stop.native, axis, kind)
            flag = "⚠" if kind != "identity" and abs(ref - stop.native) > 0.01 and infer_ref_for_stop(stop, axis.tag) and not values_equal(ref, infer_ref_for_stop(stop, axis.tag) or ref) else " "
            inferred = infer_ref_for_stop(stop, axis.tag)
            note = ""
            if inferred is not None and not values_equal(ref, inferred):
                note = f"  [name anchor={fmt(inferred)}, got={fmt(ref)}]"
            elif kind != "identity" and inferred is None:
                note = "  [no name/value anchor]"

            if stop.stat_format == 2:
                rmin = native_to_reference(stop.range_min, axis, kind) if stop.range_min is not None else None
                rmax = native_to_reference(stop.range_max, axis, kind) if stop.range_max is not None else None
                print(
                    f"    {flag} fmt2 {stop.name!r}: native nominal {fmt(stop.native)}"
                    f" range [{fmt(stop.range_min)}–{fmt(stop.range_max)}]"
                    f" → ref nominal {fmt(ref)}"
                    f" range [{fmt(rmin)}–{fmt(rmax)}]{note}"
                )
            elif stop.stat_format == 3:
                lref = native_to_reference(stop.linked_value, axis, kind) if stop.linked_value is not None else None
                print(
                    f"    {flag} fmt3 {stop.name!r}: native {fmt(stop.native)}"
                    f" → ref {fmt(ref)}"
                    f" (linked {fmt(stop.linked_value)}→{fmt(lref)}){note}"
                )
            else:
                print(
                    f"    {flag} fmt1 {stop.name!r}: native {fmt(stop.native)} → ref {fmt(ref)}{note}"
                )


def main() -> None:
    folder = Path(sys.argv[1] if len(sys.argv) > 1 else "/Users/skymacbook/Downloads/~Untitled")
    fonts = sorted(
        p for p in folder.iterdir()
        if p.suffix.lower() in {".otf", ".ttf", ".woff", ".woff2"}
    )
    if not fonts:
        print(f"No fonts in {folder}")
        sys.exit(1)
    for path in fonts:
        audit_file(path)


if __name__ == "__main__":
    main()
