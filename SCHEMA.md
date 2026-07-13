# VarFont Editor — JSON schema (v1)

> **Project status & handoff:** see [HANDOFF.md](HANDOFF.md) before changing the app or engine.

Contract between the Swift app (read, plan, UI) and the write helper (`vfcommit`, future).

**`schema_version`:** always `1` on top-level objects until a breaking change.

## Pipeline

```
Font file ──analyze──► FontAnalysis
                          │
                          ▼ import
                     ProjectDocument ◄──► .varf (saved)
                          │
                          ▼ plan (Swift, live)
                     InstancePlan
                          │
                          ▼ export
                     CommitRequest ──vfcommit──► CommitResult
                                                    │
                                                    ▼
                                              Exported font file
```

| Artifact | Mutable | Persisted | Owner |
|----------|---------|-----------|--------|
| `FontAnalysis` | No | No (refresh on open) | Read engine |
| `ProjectDocument` | Yes | Yes | App |
| `InstancePlan` | Derived | No | Plan engine |
| `CommitRequest` | Per save | No | App → helper |
| `CommitResult` | No | No | Helper → app |

Build order without commit: **FontAnalysis → ProjectDocument → InstancePlan**. Wire `CommitRequest` / `vfcommit` when round-trip tests pass.

---

## Shared primitives

### `axis_tag`

Four-character OpenType axis tag (`"wght"`, `"opsz"`, `"GRAD"`).

### `axis_role`

| Value | Lane | Instance grid | STAT labels | Typical use |
|-------|------|---------------|-------------|-------------|
| `instance` | Variation | Multiplies combinations | Yes | wght, wdth, opsz in static grids |
| `stat_only` | Pinned (when fvar `min` present) | Fixed pin coord | Yes | GRAD, opsz pinned per file (Roboto) |
| `parametric` | Pinned (when fvar `min` present) | Fixed pin coord | Optional | XOPQ, YTLC, … |
| `design_record_only` | Registration | Off grid | Yes (per-file) | `ital` on Roman VF (STAT only, no fvar) |

Lanes are derived in the app from `role` + `hasFvarScale` (`min != nil`); not stored in JSON.

Optional per-axis reference mapping (**`wght` and `wdth` only**; editor display — native values in file). Optical size (`opsz`) always uses native designer coordinates; there is no registry translation for opsz.

```json
"reference_mapping": "identity",
"reference_mapping_inferred": "stop_anchored",
"reference_anchors": [{ "reference": 400.0, "native": 360.0 }]
```

Project-level `coordinate_display`: `"reference"` | `"native"` (applies to weight and width only). Reference/native display does not emit planner warnings.

### Naming tiers

| Tier | Source | Affects instance grid names |
|------|--------|----------------------------|
| Instance axis stops | `axis_role: instance` | Yes — composed style names |
| Registration | `design_record_only` + `file_stat_registration` | Per-file only (not in instance keys) |
| Clarifiers | `file_role.clarifiers` | Prefix segments when not covered by registration |
| Elided fallback | `naming.elided_fallback` | Shown when all elidable segments drop |

`elided_fallback` is independent of per-stop `elidable` flags. Per-file `elided_fallback_override` on variants can override inferred fallback.

Persisted auxiliary fields on `FontDocument`:

- `file_stat_registration` — per-axis registration coordinate map
- `compound_stat_values` — STAT format 4 multi-axis presets (read/write in editor)
- `dismissed_plan_issues` — acknowledged plan warnings
- `inferred_is_italic_file` — import hint for registration inference

### `stat_format`

`1` | `2` | `3` — v0 **write** supports 1–3. Format `4` compound entries are preserved via `compound_stat_values` and edited in the axis tree combination section.

### `InstanceKey`

Stable string for selection and prune sets. Tags sorted alphabetically. **Registration axes** (`design_record_only`) are **not** included in instance keys — they resolve per file, not per grid combination.

```
"GRAD:0|opsz:14|slnt:0|wdth:100|wght:400"
```

Example without registration axis:

```
"opsz:5|wdth:88|wght:360"
```

Use the same rule in Swift and `vfcommit`.

---

## `AxisValue`

Maps to FontCore `AxisValueDef`.

```json
{
  "id": "w3",
  "value": 700.0,
  "name": "Bold",
  "elidable": false,
  "stat_format": 1,
  "range_min": null,
  "range_max": null,
  "linked_value": null
}
```

| Field | Required | Notes |
|-------|----------|--------|
| `id` | yes | Stable UI id |
| `value` | yes | Coordinate |
| `name` | yes | Label for STAT and composed names |
| `elidable` | yes | **At most one `true` per axis** |
| `stat_format` | no | Default `1` |
| `range_min`, `range_max` | if format `2` | Optical size ranges |
| `linked_value` | if format `3` | Style-link target (e.g. Regular → Bold) |

---

## 1. `FontAnalysis`

Read-only snapshot from a font file. See `fixtures/examples/playfair-roman-analysis.json`, `roboto-flex-analysis.json`.

```json
{
  "schema_version": 1,
  "source": {
    "path": "/path/to/font.woff2",
    "format": "woff2",
    "family_name": "Playfair",
    "full_name": "Playfair Micro SemiCond SemiLight",
    "is_variable": true
  },
  "readiness": {
    "has_fvar": true,
    "has_stat": true,
    "has_design_axis_record": true,
    "writable": true,
    "blockers": []
  },
  "axes": [],
  "stat_values": [],
  "instances_existing": [],
  "instances_existing_meta": { "total": 252, "sample_count": 5 },
  "name_audit": {
    "free_start": 280,
    "used": [],
    "elided_fallback_id": 2,
    "elided_fallback_name": "Regular"
  },
  "inferred": {
    "is_italic_font": false,
    "grid_axis_tags": ["opsz", "wdth", "wght"],
    "naming_order_suggested": ["opsz", "wdth", "wght", "ital"]
  }
}
```

### `axes[]`

```json
{
  "tag": "wght",
  "display_name": "Weight",
  "min": 360,
  "default": 360,
  "max": 900,
  "ordering": 2,
  "role_inferred": "instance",
  "varies_in_existing_instances": true,
  "values_existing": []
}
```

`values_existing` entries mirror `stat_values` filtered to that axis (import into project on first open).

### `stat_values[]`

Flat STAT audit (all formats). Format 3 includes `linked_value`. Format 4 (future) adds `axis_values: [{ "tag", "value" }]`.

### `instances_existing[]`

Sample instances (fixtures truncate; `instances_existing_meta.total` is authoritative).

### `name_audit.used[]`

```json
{ "id": 318, "description": "GPOS feature name", "protected": true }
```

---

## 2. `ProjectDocument`

Workspace state; multi-file tabs. Saved as **`.varf`** JSON (legacy **`.varfont`** still opens).

```json
{
  "schema_version": 1,
  "created": "2026-06-23T12:00:00Z",
  "modified": "2026-06-23T12:00:00Z",
  "family_label": "Playfair Display VF",
  "naming": {
    "order": ["opsz", "wdth", "wght", "@width", "@slope", "@optical", "@custom"],
    "elided_fallback": "Regular"
  },
  "nameid_strategy": "preserve",
  "template": { "axes": [], "sync_roles": true },
  "fonts": []
}
```

`nameid_strategy`: `"preserve"` | `"reflow"` — project-wide OpenType feature label nameID handling on save. App **Preferences** menu sets the default for new projects; Save review can override per open project.

### `fonts[]` — per open file

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "source_path": "/path/to/PlayfairRomanVF.woff2",
  "output_path": null,
  "analysis_snapshot_id": "optional-hash-or-mtime",
  "dirty": false,
  "file_role": {
    "kind": "variant",
    "master_font_id": "uuid-of-master-font",
    "clarifiers": [
      { "category": "width", "label": "Condensed" },
      { "category": "slope", "label": "Italic" }
    ],
    "elided_fallback_override": null
  },
  "axes": [],
  "options": {
    "fix_fvar_default": true,
    "allocate_postscript_names": true,
    "nameid_strategy": "preserve"
  },
  "included_instance_keys": [],
  "excluded_instance_keys": [],
  "overrides": { "per_instance": [] }
}
```

### `fonts[].file_role`

Per-file family identity — **not** fvar axes. Master file has `kind: "master"` and empty `clarifiers`. Variants list what makes this file different from the master.

| `clarifiers[].category` | Typical labels |
|-------------------------|----------------|
| `slope` | Italic, Oblique |
| `width` | Condensed, Wide |
| `optical` | Text, Display, Micro |
| `custom` | Color, Rounded Stencil Rough, … |

At most one clarifier per category per file. Labels append to composed instance names per project `naming.order` clarifier tokens (`@width`, `@slope`, `@optical`, `@custom`).

### `fonts[].axes[]`

```json
{
  "tag": "wght",
  "display_name": "Weight",
  "min": 360,
  "default": 360,
  "max": 900,
  "role": "instance",
  "values": []
}
```

### Prune semantics

- Generate Cartesian product from axes where `role` is `instance`.
- Pin `stat_only` and `parametric` axes to `default` (or per-axis first value) in every instance.
- If `included_instance_keys` is **non-empty**: allow-list.
- Else: all generated keys **minus** `excluded_instance_keys`.

### `template`

Shared axis stops for **Apply to all fonts** (Roman + Italic VF). See `fixtures/examples/playfair-family-project.json`.

### `overrides.per_instance` (v1 placeholder)

Per-instance axis participation (e.g. GRAD only at Text opsz). Empty in v0; schema reserved.

```json
{
  "key": "opsz:14|wght:400|...",
  "omit_axes_from_name": ["GRAD"],
  "pin_coords": { "GRAD": 0 }
}
```

---

## 3. `InstancePlan`

Derived preview; recomputed on every project edit. See `fixtures/examples/playfair-roman-instance-plan.json`.

```json
{
  "schema_version": 1,
  "font_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "formula": {
    "parts": [12, 3, 7],
    "total_generated": 252,
    "total_included": 252,
    "total_excluded": 0
  },
  "instances": [],
  "warnings": [],
  "name_plan_summary": {
    "family_ps_prefix": "PlayfairDisplayVF",
    "new_id_range": [280, 400],
    "instance_count": 252
  }
}
```

### `instances[]`

```json
{
  "key": "opsz:5|wdth:88|wght:360",
  "composed_name": "Micro SemiCond SemiLight",
  "coords": { "opsz": 5, "wdth": 88, "wght": 360, "ital": 0 },
  "included": true,
  "duplicate": false,
  "naming_chain": [
    { "tag": "opsz", "name": "Micro", "elided": false },
    { "tag": "wdth", "name": "SemiCond", "elided": false },
    { "tag": "wght", "name": "SemiLight", "elided": false }
  ]
}
```

### `warnings[]`

```json
{ "code": "multiple_elidable", "axis": "wght", "message": "Only one elidable value per axis." }
{ "code": "duplicate_name", "name": "Regular", "keys": ["...", "..."] }
{ "code": "default_not_in_stops", "axis": "wght", "default": 90 }
```

---

## 4. `CommitRequest`

Input to `vfcommit`. Subset of project + output paths.

```json
{
  "schema_version": 1,
  "request_id": "uuid",
  "source_path": "/path/in.woff2",
  "output_path": "/path/out-patched.woff2",
  "dry_run": false,
  "options": {
    "fix_fvar_default": true,
    "allocate_postscript_names": true,
    "preserve_stat_format_3": true,
    "nameid_strategy": "preserve"
  },
  "naming": {
    "order": ["opsz", "wdth", "wght", "@width", "@slope", "@optical", "@custom"],
    "elided_fallback": "Regular"
  },
  "file_role": {
    "kind": "variant",
    "clarifiers": [{ "category": "slope", "label": "Italic" }]
  },
  "axes": [],
  "included_instance_keys": []
}
```

`axes` uses the same shape as `ProjectDocument.fonts[].axes`.  
`dry_run: true` → `CommitResult` without writing a file.

Alignment with TableEditor YAML: `axes[].values` = `AxisValue`; `options.fix_fvar_default` = `--no-fix-default` inverse.

---

## 5. `CommitResult`

```json
{
  "schema_version": 1,
  "request_id": "uuid",
  "ok": true,
  "output_path": "/path/out-patched.woff2",
  "dry_run": false,
  "summary": {
    "instances_written": 252,
    "stat_values_written": 22,
    "name_ids_allocated": [280, 365],
    "wiped_instance_count": 252,
    "protected_name_ids": [318, 319]
  },
  "warnings": [],
  "errors": []
}
```

`diff` is present on **dry-run** responses only. Omitted on successful writes.

```json
"diff": {
  "family_ps_prefix": "MyFamilyVF",
  "elided_fallback_name": "Regular",
  "elided_fallback_id": 295,
  "name_id_range": [280, 295],
  "name_records_planned": [
    { "id": 280, "string": "Bold", "role": "instance_subfamily" }
  ],
  "stat_values_planned": [
    { "tag": "wght", "value": 400, "name": "Normal", "elidable": true, "stat_format": 1, "name_id": 281 }
  ],
  "instances_planned": [
    { "composed_name": "Micro Normal", "subfamily_name_id": 282, "postscript_name": "MyFamilyVF-MicroNormal", "postscript_name_id": 283 }
  ],
  "name_records_sequenced": [
    { "id": 256, "string": "Alternate g", "role": "ot_feature_label" },
    { "id": 261, "string": "Weight", "role": "axis_display_name" }
  ],
  "ot_reflow_mapping": [
    { "from": 763, "to": 256, "string": "Alternate g", "feature": "ss05" }
  ]
}
```

`name_records_sequenced` — write-order slots for Save review (OT labels first when reflow is on).  
`ot_reflow_mapping` — present when `nameid_strategy` is `reflow`; maps old OT label IDs to new 256+ block.

Swift merges `FontAnalysis` (before) + `InstancePlan` + `CommitResult.diff` into `CommitDiffReport` for the Save review UI.

Optional: `analysis_after` (`FontAnalysis` of output) for immediate UI refresh.

---

## v0 exclusions

- STAT Format **4** write  
- `overrides.per_instance` enforcement  
- TTC  
- Instancer / static export  
- In-place overwrite (always `output_path` ≠ `source_path`)  

---

## Fixtures

| File | Purpose |
|------|---------|
| `fixtures/examples/playfair-roman-analysis.json` | Read golden (252 instances) |
| `fixtures/examples/playfair-italic-analysis.json` | Read golden (italic VF) |
| `fixtures/examples/roboto-flex-analysis.json` | Axis roles (13 axes, 20 instances) |
| `fixtures/examples/playfair-family-project.json` | Multi-file project |
| `fixtures/examples/playfair-roman-instance-plan.json` | Plan sample (truncated instances) |
| `fixtures/examples/playfair-roman-commit-request.json` | Save payload example |
| `fixtures/examples/commit-result-success.json` | Helper response example |

Generated analysis files may reference local paths under `~/Downloads/`; tests should rewrite `source.path` or load from bundled test fonts.

---

## Swift types (suggested)

```
FontAnalysis, ProjectDocument, FontDocument, AxisDefinition, AxisValue
InstancePlan, PlannedInstance, PlanWarning
CommitRequest, CommitOptions, CommitResult, CommitSummary, CommitDiff
CommitDiffStatValuePlanned, CommitDiffInstancePlanned, CommitNameRecordPlanned
CommitDiffReport, CommitDiffStatRow, CommitDiffInstanceRow, CommitDiffNameIDRow
CommitDiffChangeKind
```

`Codable` + `schema_version` migration when v2 is needed.
