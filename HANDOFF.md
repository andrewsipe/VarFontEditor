# VarFont Studio — project handoff

**Last updated:** 2026-07-11 (alpha polish — `.varf` projects, OT reflow, save review)  
**Purpose:** Single entry point for new chats, collaborators, or future you. Read this before changing the app or engine. **Includes rejected and parked ideas** so we do not re-litigate them.

---

## What this app is

**VarFont Studio** is a native macOS editor for **variable font instance modeling** — not a glyph editor and not a raw TTX table browser.

### Product problem

Variable fonts split “what instances exist” across **fvar**, **STAT**, and **name**. Foundry files are inconsistent. CLI tools and table editors force linear, one-field-at-a-time edits. The product goal is to make the **instance grid and naming intent** legible: define axis stops → generate combinations → prune → preview composed names → commit back to the font.

### Interaction model (settled via HTML prototypes)

Workflow spine:

```
Define (axis tree) → Generate (live plan) → Refine (prune, naming, conflicts) → Commit (write font)
```

Three panels:

| Panel | Role |
|-------|------|
| **Axis tree** | Edit axes, roles, STAT stops (formats 1–3), elision, registration |
| **Instance list** | Derived grid; include/exclude; search and grouping |
| **Inspector** | Naming chain, coordinates, OpenType preview for selection |

Reference prototypes (interaction only, not visual design):

- `VF_Remap/prototype-axis-tree-ui.html`
- `VF_Remap/prototype-axis-tree-ui-v2.html` (multi-file tabs)
- `VarFontEditor/prototype mockups/` (axis tree layout iterations)

### Architecture

```
Font file ──analyze──► FontAnalysis
                          │
                          ▼ import
                     ProjectDocument (.varf)
                          │
                          ▼ plan (Swift, live)
                     InstancePlan
                          │
                          ▼ save
                     CommitRequest ──vfcommit (Python)──► Patched font
```

| Layer | Location | Notes |
|-------|----------|--------|
| **VarFontCore** | `Sources/VarFontCore/` | Swift package: read, plan, schema, commit bridge |
| **VarFontStudio** | `Apps/VarFontStudio/` | SwiftUI app shell |
| **vfcommit** | `Tools/vfcommit/` | Bundled Python helper; fontTools write path |
| **Fixtures & schema** | `fixtures/`, `SCHEMA.md` | JSON contract and test inputs |

**Python scope:** Read and plan are **Swift**. Write goes through **vfcommit** on Save only — not PythonKit in the app. Reuses FontCore policy ideas from the wider monorepo.

---

## How to build and run

**Do not** open `Package.swift` alone while also using the app — Xcode will fight over the local package (“already opened from another project”).

### Developers (from source)

1. Quit Xcode.
2. Open **`VarFontEditor/VarFontStudio.xcworkspace`** (not the package folder).
3. Scheme: **VarFontStudio** · Destination: **My Mac** · Run (⌘R).

### End users (GitHub download)

Pre-built `.app` zips are produced by `scripts/build-release.sh` and published via GitHub Releases (see `README.md`). The bundle includes **vfcommit** and a **Python + fontTools** runtime — no Xcode or pip install required.

```bash
cd VarFontEditor
./scripts/build-release.sh          # runs swift test + Release build + zip
./scripts/build-release.sh --skip-tests
```

Tag **`v*`** on GitHub to trigger `.github/workflows/release.yml`, which builds **both** `arm64` (Apple Silicon) and `x86_64` (Intel) zips and attaches them to the Release.

Tests (SwiftPM):

```bash
cd VarFontEditor && swift test
```

---

## What we have accomplished

### Engine (VarFontCore)

- [x] **FontAnalysis** from real `.ttf` / `.woff2` (CoreText + custom parsers)
- [x] **STAT 1.0/1.1** offset parsing fix (Playfair-scale fonts analyze correctly)
- [x] **Project import** with stable UUID stop IDs, axis roles, reference mapping inference
- [x] **InstancePlanner** — Cartesian grid, pinned/parametric axes, prune sets
- [x] **NamingComposer** — order, elision, clarifiers, registration axes
- [x] **Axis lanes** — variation / pinned / registration (derived from role + fvar)
- [x] **Design-record axes** — STAT `DesignAxisRecord` without fvar (Playfair `ital`)
- [x] **Registration naming** — `file_stat_registration` per file; off instance grid
- [x] **Naming conflicts** — bundle, resolver strategies, compound fixes
- [x] **Registry ladder** — wght/wdth reference mapping, ladder alignment warnings
- [x] **STAT formats 1–3** in model; format 4 read + preserve on save
- [x] **Name audit** — used IDs, elided fallback name from STAT
- [x] **CommitService** — shells to vfcommit; dry-run diff support
- [x] **~99 unit tests** (see Test health below)

### App (VarFontStudio)

- [x] Three-panel editor, multi-project workspace, font drop/import
- [x] **Axis tree** — collapsible blocks, layout K (Fmt · Value · Name · Elid)
  - F1 single row; F2 two-row (min · nom · max subline); F3 name + link icon
  - Instance-axis toggle; pinned axes; registration lane
  - Add/remove stops; format change sheets; inline edit with tab order
  - Conflict + plan warnings inline on axis headers; rollup banner for multi-axis issues
  - `AxisBlockStateSpec` table in `AxisTreePanel.swift` (check new UI against it)
- [x] **Instance list** — table, include toggles, search, grouping (~300 rows)
- [x] **Inspector** — naming chain, coordinates, instance key
- [x] **Naming order** footer / chain editor
- [x] **File clarifiers** bar (width/slope/optical/custom) — lower priority than registration
- [x] **Conflict resolver** sheet
- [x] **Save review** window — preflight dry-run, per-file tabs, commit diff presentation
- [x] **OpenType feature label reflow** — optional compact ss/cv/size labels to ID 256+ before STAT/fvar (`Preferences` menu default; per-project override in Save review)
- [x] **Project save/open** — `.varf` JSON workspace files (legacy `.varfont` still opens); ⌘⌥S / ⌘⌥⇧S
- [x] **Shortcuts help** — Help menu reference for alpha testers
- [x] **Push to tree** — copy master axis stops to sibling files in project
- [x] **Undo** snapshots for axis edits
- [x] **StudioDesign** — shared tokens (spacing, typography, row chrome)

### Verified on real fonts (manual)

| Font | Notes |
|------|--------|
| Playfair Roman VF | 12×3×7 = 252 instances; design-record `ital` |
| Playfair Italic VF | Separate file in family project |
| Roboto Flex | Many axes; small instance grid (wght × slnt) |

---

## Core product model (locked-in decisions)

### Naming segment priority

When building a composed instance name:

1. **Dynamic axes** (`role: instance`) — grid stops; per-stop `elidable` omits segment
2. **Registration axes** (`design_record_only`) — per-file `file_stat_registration`
3. **File clarifiers** (`@slope`, `@width`, …) — only if higher tiers did not cover that category

Clarifiers are **skipped** when a matching design-record registration axis is set on the file (`ital` → slope, `wdth` → width, `opsz` → optical; `@custom` never covered). See `RegistrationAxisSupport.clarifierCategoriesCoveredByRegistration`.

### Elided fallback (three independent layers)

| Layer | Meaning |
|-------|---------|
| Per-stop `elidable` | Omit this stop’s segment from the composed name |
| Registration stop | Which slope/upright stop *this file* claims |
| STAT **elided fallback** | Name when **all** segments elide (e.g. → `"Regular"`) |

- **Import:** `project.naming.elidedFallback` mirrors STAT `elidedFallbackNameID` / name audit.
- **Editability:** TBD in UI; mirror-in is required even if read-only at first.
- **Write (deferred):** commit must write STAT elided fallback ID to match project — presentation parity = write parity.

### Axis tree ↔ STAT / fvar parity (goal)

One block per logical axis:

- **fvar axes** — min/default/max, instance grid participation
- **STAT stops** — formats, names, elidable, F3 links
- **Design-only STAT axes** — no fvar scale; per-file registration

Parity for **registration capture/edit and preview=commit naming** landed in Phase 0 (Jul 2026). Full save round-trip trust remains a later session.

### Save / write

**Explicitly deferred** until capture/present/edit for registration and elided fallback are stable. Test saves have shown issues; treat round-trip as a **focused later session**, not blocking UI work.

---

## Outstanding / incomplete (functional)

Phase 0 (STAT / Axis Tree alignment, Jul 2026) is **done** for read/preserve, registration edit, elided fallback display, F3 link picker, and preview=commit naming. Next focused session: **save round-trip trust**.

### Phase 0.5 — Naming model clarity (Jul 2026)

Phase 0.5 aligns UI and language with three naming roles. No save-trust work.

| Role | What it is | Multiplies instances? | In style name? | Color |
|------|------------|----------------------|----------------|-------|
| **Instance axis** | Stops on the grid (fvar varies) | Yes | Yes (per stop; elidable may drop) | Neutral |
| **Registration axis** | STAT design-record, no fvar; **this file's** stop | No | Yes when stop is not elided | Teal |
| **Pinned axis** | Has fvar but toggled off the grid | No (fixed default) | No | Neutral dashed |
| **File clarifier** | Project label when STAT does not register that slot | No | Yes if set | Purple |

**Locked UI decisions:**

- Registration stop picker lives in the axis header **subtitle** (`No fvar scale · Roman ▾`), not the badge column — count badges stay scannable.
- Naming-order footer toggle: **Hide pinned axes** (registration axes stay visible).
- Naming-order chips: neutral + checkbox (instance), teal no-checkbox (registration), purple (clarifier).
- `NamingChainLink.Kind.registration` for design-record segments in inspector chain views.

Never call registration “STAT-only” in user-facing copy.

### Plan issue resolution (Jul 2026)

Registration, orphan F3 links, and `ital` name/value convention warnings now share a guided fix path separate from stop-conflict **Resolve**:

| Code | Auto on import | Guided fix |
|------|----------------|------------|
| `registration_value_missing` | Re-infer when stops exist | Pick inferred registration |
| `registration_mismatch` | Use Roman/upright stop when present | Rename stop / pick another / keep |
| `ital_value_name_mismatch` | Sole stop revalue to 0/1 | Revalue vs keep |
| `orphan_stat_link` | Never | Convert to F1 vs keep F3 |

- `PlanIssueResolver` + `PlanIssueResolverSheet` — proposals apply via `fileStatRegistration`, stop revalue/rename, or F3→F1.
- `dismissedPlanIssues` on `FontDocument` — “Keep” choices hide acknowledged warnings.
- Registration stop **values** are editable; revalue syncs `fileStatRegistration`.

### Registration axis

| Gap | Status |
|-----|--------|
| Import inference | **Done** — elidable stop preferred; Roman/Italic file cues |
| UI edit | **Done** — registration stop picker + highlighted row in axis tree |
| VM API | **Done** — `setFileStatRegistration(tag:value:forFontID:)` |
| Italic VF | **Done** — file-aware default + `registration_mismatch` warning |

### Elided fallback

- [x] Show resolved elided fallback in naming chain footer (with inferred affordance)
- [x] Import uses `ElidedFallbackResolver` (§6 baseline resolve)
- [x] Write path: `CommitRequest` carries resolved fallback; vfcommit emits `elidedFallbackNameID`
- [ ] Document in `SCHEMA.md` how fallback relates to per-stop elidable (independent layers)

### Instance list vs prototype

- [ ] Context formula bar (`12 × 3 × 7 = 252`) with bulk actions
- [ ] Toolbar pills: total / included / pruned / duplicates
- [x] Filter instance list by clicking axis stop in tree
- [ ] Matrix view when exactly two varying axes

### Commit / round-trip

- [x] Round-trip tests: edit → vfcommit → re-analyze fvar (`CommitRoundTripTests`, `test_round_trip_write.py`)
- [x] vfcommit honors `included_instance_keys` on write (not just dry-run summary)
- [ ] Fix save issues found in manual test copies (Font Book / re-import grid hydration)
- [ ] Full table-trust session (name reflow, byte-level parity goals)
- [ ] Name table reflow strategy — see `EXPORT_DESIGN_NOTES.md`

See [`docs/SAVE_ROUND_TRIP_LOG.md`](docs/SAVE_ROUND_TRIP_LOG.md).

### Engine / tests

- [x] **Test health (2026-07-07):** `swift test` — 153 tests, 0 failures (2 skipped without live fonts); vfcommit `unittest` — 12 tests OK
- [x] Live font path resolution via `LiveFontFixture.swift` (multi-path `~/Downloads` candidates)
- [ ] Reconcile static JSON fixtures with live Playfair axis counts where tests still use snapshots only

### Format / axis tree (smaller gaps)

- [x] Inline **F3 link target** editing (picker on F3 rows)
- [x] Format **4** — read + preserve on save (no author UI; badge in axis tree)
- [x] **OlderSibling** STAT flag preserve on read/write
- [x] **@slope** clarifier demoted when `ital` design-record registration exists
- [ ] Format 4 create/edit UI
- [ ] OS/2 instancing — explicitly deferred (“Phase 9” in prior notes)

---

## Deferred — targeted session work

Use separate sessions; do not mix with axis tree polish.

| Session | Scope |
|---------|--------|
| **Save round-trip** | vfcommit output vs re-import; fix table write bugs |
| **Registration completion** | Inference + UI picker + tests; then wire write |
| **Elided fallback** | UI mirror + commit STAT field |
| **Name reflow on export** | **Partially shipped** — optional `reflow` mode in vfcommit + Save review; see `EXPORT_DESIGN_NOTES.md` |
| **Prototype instance list** | Formula bar, matrix, tree→list filter |
| **Test fixture refresh** | After registration naming settled |

---

## QoL / nice-to-have (later)

- Axis tree column width presets / user resize
- Keyboard shortcuts audit across stop edit tab order
- Duplicate instance highlighting improvements in list
- Project template sync UX polish
- `.varf` project file double-click association (legacy `.varfont` supported)
- CI workflow for `swift test` on push
- VarFontEditor folder tracked in git (`?? VarFontEditor/` in parent repo as of mid-2026)

---

## Explicitly out of scope (v0)

Items here were discussed and intentionally **not** built for the current app. Refer here before re-opening them — the idea may be valid someday but was judged too large, wrong layer, or low payoff for v0.

### Scale & performance

| Idea | Decision | Rationale |
|------|----------|-----------|
| **Crowded preset** (~1,872 instances) in prototype | Out of v0 | Theoretical Cartesian product; no font in your library approaches this. Prototype stress test only. |
| **FontVault-scale lists** (thousands of rows, virtualized catalog patterns) | Out of v0 | Playfair ~252/file, ~504/family is the realistic ceiling. SwiftUI `Table`/`List` at ~300 rows is sufficient. |
| **Full matrix UI** for 3+ axes | Deferred | Matrix only makes sense for 2 varying axes; see Outstanding for optional 2-axis matrix. |

### Conditional & per-instance axis behavior

| Idea | Decision | Rationale |
|------|----------|-----------|
| **Conditional axes** (GRAD only at Text opsz, sparse opsz participation) | Post-v0 Refine layer | Prototype settled: define full grid first, refine later. Schema reserves `overrides.per_instance` but planner does not enforce it. |
| **Per-instance omit/pin** (`omit_axes_from_name`, `pin_coords`) | Schema only | Same as above — needs Refine UI + planner rules. |
| **Global elision toggles** | Rejected | Elision is **per stop, per axis** (at most one elidable per axis). Not a project-wide switch. |

### UI / interaction experiments (rejected or superseded)

| Idea | Decision | Rationale |
|------|----------|-----------|
| **Reference/native coordinate picker** in axis tree | Removed | Pivot to native-only display in tree; registry mapping remains in engine for ladder warnings. |
| **Format-2 ladder auto-propagate** on edit | Rejected | Changing min/max should not silently rewrite other stops; explicit validation warnings instead. |
| **Reserved remove-button column** in axis grid | Superseded | Trailing hover overlay on `primaryRow` only (layout K); see UI conventions below. |
| **Per-axis Min/Max/Link columns** (layout J variant) | Superseded | Layout K: F2 subline under name row. |
| **Prototype visual design** (custom colors, IBM Plex, workflow banner) | Not ported | App uses native Sonoma semantic styles (`StudioDesign.swift`). |
| **Permanent naming chain in top chrome** | Rejected | Naming order lives in Refine footer / inspector, not a fixed header strip (prototype v3 direction). |

### Write / export (deferred entire track)

| Idea | Decision | Rationale |
|------|----------|-----------|
| **Full commit round-trip trust** | Deferred session | Capture/present/edit must settle first; manual test saves already show issues. |
| **STAT format 4 write** | Out until read path complete | Format 4 read-only in engine. |
| **OS/2 instancing** (“Phase 9”) | Deferred | Not blocking instance modeling UI. |
| **VarFlow-style export** | Not reused | See `EXPORT_DESIGN_NOTES.md` for alternate name-reflow approach. |
| **In-app Python / PythonKit** | Rejected for v0 | `vfcommit` subprocess on Save only; keeps app bundle smaller. |
| **Rust/fontations write path** | Parked | Strong v1+ candidate; poor v0 fit while Swift read/plan still evolving. |
| **User-installed fonttools** | Dev-only | Poor UX for shipping app. |

### Product boundaries

| Idea | Decision | Rationale |
|------|----------|-----------|
| **Glyph / outline editing** | Never this app | Instance modeling only. |
| **Raw TTX table editor** | Never this app | Intent graph (axis tree → plan), not implementation fragments. |
| **Font library / catalog** | Separate app | FontVault owns browse, dedup, vault SQL. No runtime dependency. |
| **“Font Workshop” batch pipeline GUI** | Separate product | FontNameID + FileRenamer + Filename_Tools — different workflow. |

---

## Ideas park — may revisit, not v0

Valid ideas that might not fit this app or need more design before building.

### Instance list & refine

- **Toolbar status pills** — total / included / pruned / duplicate counts (prototype had these).
- **Context formula bar** with bulk prune actions (`12 × 3 × 7 = 252`).
- **Click axis stop → filter instance list** (prototype filtering).
- **Grouped list bucketing** by width (FontLab-style); partial grouping exists, not full prototype parity.
- **Draggable global naming chain** in chrome (prototype v2); app uses footer editor instead.
- **Duplicate instance matrix** view when exactly two axes vary.

### Axis tree

- **Inline F3 link target editing** (picker in row); display-only `link` SF Symbol today.
- **Editable STAT elided fallback** in UI (mirror from font is enough for v0; edit TBD).
- **Registration stop picker** per file (highest priority among parked — moving to Outstanding when scheduled).
- **Axis tree layout prototypes A–J** — archived in `prototype mockups/`; **K** is production.

### Multi-file & family

- **Apply template to all fonts** — `Push to tree` copies master stops; fuller template sync UX polish remains QoL.
- **Family-wide axis template** in `.varfont` — schema has `template`; UI is minimal.
- **Cross-file registration** — each VF file has own `file_stat_registration`; no shared “family registration” object.

### Engine & fonts

- **Muller Next retrofit** — real-world case in `Variable_Instancer/Adding static instances to variable fonts.md`: VF with STAT/fvar gaps, 234 static styles to model. Informs the app’s purpose; not a test fixture yet.
- **Melange, Nouveau Quellstift, Milgram** — reference fonts for registry ladder / stop-anchored mapping tests (see Test fonts below).
- **Float-tolerant stop matching** (`AxisCoordinate` 0.001) — implemented; prevents `399.9999999` ≠ `400` bugs.

### Integrations

- **Deep FontCore Python reuse in-app** — policy ported to Swift + vfcommit subset, not embedded scripts.
- **FontVault handoff** — open VF from vault into Studio (no integration built).
- **Catalog metadata apply** (FontNameID `NameID_CatalogApply`) — sibling monorepo work, not Studio.

---

## Scale reality (calibration)

Use these when evaluating UI density — not prototype extremes.

| Reference | Instances / scale | Notes |
|-----------|-------------------|--------|
| **Playfair VF** (one file) | 12 × 3 × 7 = **252** | Primary real-world test; opsz × wdth × wght |
| **Playfair family** | **504** | Roman VF + Italic VF as **two files**, not one 504-grid VF |
| **Muller-scale** (prototype) | **234** (117 × 2 slopes) | 13×9×2 weight×width×italic; grouping + search required |
| **Roboto Flex** | **~9–20** in fvar instances | **13 fvar axes**; only **wght × slnt** (or similar) in grid — axis toggle story |
| **Crowded** (prototype) | 1,872 | Theoretical; ignore for product decisions |

---

## Multi-file project model

### Workspace session (in memory)

- Multiple **projects** can be open as tabs (`OpenProject` in `OpenProject.swift`).
- Each project is a `ProjectDocument` with one or more `FontDocument` entries (e.g. Playfair Roman + Italic).
- Drag/drop: create project, add to project, move font between projects, combine projects.

### Master vs variant

| Role | Holds |
|------|--------|
| **Master** (`file_role.kind: master`) | Shared axis tree definition; **Push to tree** copies stops to siblings |
| **Variant** | Per-file `file_stat_registration`, **file clarifiers**, optional `elided_fallback_override` |

When **multiple files** in one project:

- **Clarifiers** are edited on **variants**, not master (`EditorViewModel.inferFileClarifiersForSelectedFont` clears clarifiers on multi-file master).
- **Registration** is always per-file (`file_stat_registration` on each `FontDocument`).

### Persistence today

| What | Status |
|------|--------|
| **Font save / commit** | Implemented — Save Review → `vfcommit` → output font file |
| **Project save (`.varf` JSON)** | Implemented — Save Project / Save Project As; persists naming, axes, reflow preference, per-file state |
| **Undo/redo** | Per-project `ProjectDocument` snapshots in session |

---

## Reference mapping & coordinates

### Engine

- **wght / wdth only** — OpenType registry ladder; `stop_anchored` / `default_anchored` / `identity` inference.
- **opsz** — always native designer coordinates; no registry translation.
- **Ladder warnings** — `ladder_missing_stop`, `ladder_misaligned_stop`, `ladder_cannot_anchor` when offset axes diverge from registry.

### UI decision

- Axis tree shows **native** values only (reference/native picker removed from tree).
- Project `coordinate_display` (`reference` | `native`) exists in schema for future/inspector use.

### Test fonts (what they teach)

| Font | Lesson |
|------|--------|
| **Playfair** | Stop-anchored wdth/wght; design-record `ital`; F3 Roman linked to Italic |
| **Roboto Flex** | Many pinned/parametric axes; tiny instance grid — **instance axis toggle** |
| **Milgram** | **Weight** naming: `X-Bold` at 800 — value anchor beats name table (`testMilgramExtraBoldUsesValueAnchorNotBoldName`). **Not** the ital/registration case. |
| **Melange** | Width stays identity mapping (wide native range) |
| **Nouveau Quellstift** | Thin at 200 stays on ladder when value is registry step |

---

## Registration & clarifiers (full thread)

### Why registration exists

Some fonts expose **`ital` in STAT DesignAxisRecord** without an fvar axis (Playfair Roman). Slope/upright identity belongs in **naming**, not the Cartesian grid. Registration axes:

- Do not multiply instance count
- Resolve per file via `file_stat_registration`
- Appear in naming chain when in `naming.order`

### Why clarifiers are lower priority

Clarifiers (`@slope`, `@width`, …) were designed **before** STAT design-record axes were fully modeled. **Naming tier:** dynamic → registration → clarifier. When design-record `ital` exists, `@slope` clarifier is **skipped** — registration supersedes it for slope identity.

Clarifiers remain useful for **width/optical/custom** labels not represented as STAT axes (e.g. “Condensed” Roman vs Normal Roman in one project).

### Milgram / “ital with no italic” confusion

- **Milgram** in tests = weight registry anchor issue, not registration.
- **registration_mismatch** warning = upright file whose `file_stat_registration` points at an Italic-named stop.
- Some fonts have **ital axis metadata** but ship upright-only — engine warns; does not auto-fix font data.

---

## Prototype lineage & lessons

| Artifact | Role |
|----------|------|
| `VF_Remap/prototype-axis-tree-ui.html` | First three-panel proof |
| `VF_Remap/prototype-axis-tree-ui-v2.html` | Muller scale, prune, naming chain experiments |
| `VF_Remap/prototype-axis-tree-ui-v2a.html` | Multi-file tabs, layout rearrangement |
| `VarFontEditor/prototype mockups/` | Axis tree column layouts (J, K, etc.) |

**Lessons that became rules:**

1. At most **one elidable stop per axis** — planner warns `multiple_elidable`.
2. **Define → generate → refine** — don’t try to show every instance without filter/group/search.
3. **Inspector** is the connections view (path → composed name), not a fourth panel of tables.
4. **Elision is policy per stop**, not demo regex (`book|medium` elidable was prototype bug).
5. **Naming order** is editable in Refine, not baked into top chrome.

---

## UI conventions (axis tree — avoid regressions)

Documented so future layout tweaks don’t repeat solved bugs.

- **Hover overlays** attach to the view whose bounds define alignment — e.g. remove button on `primaryRow`, not the F2 subline container.
- **Magic offsets** use named constants with intent (`removeButtonTrailingOffset`), not bare `4`.
- **Axis block states** — check new combinations against `AxisBlockStateSpec` in `AxisTreePanel.swift` before adding branches.
- **Add Stop** — full-width CTA outside Fmt/Value/Elid grid; leading inset aligns with Name column only (documented in code).
- **Format 3** — link shown as SF Symbol `link`, not `↔`; inline link editing in axis tree.

---

## Architecture alternatives (historical)

Decisions from pre-build exploration — not up for re-litigation without new constraints.

| Approach | Verdict |
|----------|---------|
| Swift read + plan, **vfcommit on Save** | **Chosen** v0 |
| PythonKit + fonttools in app | Rejected — bundle size, embedding |
| Rust / fontations | Parked for write-heavy v1 |
| CLI TableEditor linear flow | Superseded by this app |
| Three separate table editors (fvar/STAT/name) | Rejected — one instance grid model |
| HTML prototype aesthetics in Swift | Rejected — structure only |

---

## Parent monorepo (sibling work — not Studio)

Active or related work in `Good Font Scripts` that **does not block** Studio but shares domain:

| Area | Relationship |
|------|----------------|
| **FontCore** (Python) | NameID allocator, STAT builder, catalog — vfcommit ports subset |
| **FontNameID** | Batch replacers; `NameID_CatalogApply` |
| **FontVault** | Font library app; browse/sort/catalog SQL |
| **Variable_Instancer** | Static instances in VF; Muller Next doc |
| **VF_Remap** | Prototypes + older editor experiments |
| **VarFlow** (external) | Prior export/name workflow — informed `EXPORT_DESIGN_NOTES.md` |

`VarFontEditor/` may appear as **untracked** (`??`) in the parent git repo — commit strategy for the subfolder is separate from Studio feature work.

---

## Key files (start here)

| File | Why |
|------|-----|
| `HANDOFF.md` | This document |
| `SCHEMA.md` | JSON contract v1 |
| `EXPORT_DESIGN_NOTES.md` | Future export/name reflow |
| `Apps/VarFontStudio/EditorViewModel.swift` | App state, save, axis mutations |
| `Apps/VarFontStudio/Views/AxisTreePanel.swift` | Axis tree UI + `AxisBlockStateSpec` |
| `Sources/VarFontCore/Plan/InstancePlanner.swift` | Grid generation |
| `Sources/VarFontCore/Plan/NamingComposer.swift` | Composed names |
| `Sources/VarFontCore/Plan/RegistrationAxisSupport.swift` | Per-file registration |
| `Sources/VarFontCore/Read/FontAnalysisReader.swift` | fvar + STAT merge |
| `Sources/VarFontCore/Import/ProjectImporter.swift` | Open font → project |
| `Tools/vfcommit/` | Write helper |

---

## Relationship to the wider monorepo

This repo folder (`Good Font Scripts`) contains many **Python font pipelines** (FontNameID, FontCore, Variable_Instancer, FontVault, etc.). VarFont Studio **reimplements read/plan in Swift** and uses a **small Python commit helper**, not the full batch scripts.

FontVault is a separate native app (font library). VarFont Studio is the **variable font instance editor** spin-out discussed in 2026 planning chats. Shared concepts: NameID policy, STAT builder ideas, catalog metadata — but no runtime dependency on FontVault.

---

## Suggested next work (when resuming)

1. **Manual Save Copy checklist** on Playfair — Font Book + re-open in Studio (see `docs/SAVE_ROUND_TRIP_LOG.md`).
2. **Re-import grid hydration** — patched fonts should rebuild full instance plan on open.
3. **Alpha release checklist** — smoke-test multi-file Playfair, OT reflow on/off, `.varf` round-trip.

Do **not** add more axis tree layout tweaks unless fixing a clear bug.

---

## Changelog (high level)

| Period | Focus |
|--------|--------|
| Early 2026 | Prototypes, schema, VarFontCore engine, first app shell |
| Mid 2026 | STAT parser fix, lanes, registration axes, conflict resolver |
| Jun–Jul 2026 | Axis tree layout K, STAT F1/F2/F3 UI, block structure phases 0–7, save review shell |
| Jul 2026 | Phase 0.5 naming model clarity — registration subtitle picker, role colors, clarifier demotion |
| Jul 2026 | Alpha polish — `.varf` projects, OT label reflow, Save review name tab, fvar PostScript rows, Preferences menu |
