# VarFontStudio — export / save design notes

**Status:** OT feature label reflow (`preserve` | `reflow`) **shipped in alpha** via vfcommit + Save review. Remaining items below are for broader export diff UI and future hardening.

---

## Shipped (alpha, Jul 2026)

| Feature | Behavior |
|---------|----------|
| **`nameid_strategy: reflow`** | Moves ss/cv/size OpenType UI labels to a contiguous block at ID 256+, updates GSUB/GPOS pointers, then allocates STAT/fvar names after that block |
| **App default** | **Preferences** menu → Preserve vs Reflow OpenType feature name IDs |
| **Per-project override** | Review tab bar → OpenType labels segmented control; persisted in `.varf` when you Save Project |
| **Save review** | Name tab shows reflowed OT labels first; fvar tab lists subfamily + PostScript name per instance |

Default remains **`preserve`** — no behavior change unless reflow is enabled.

### Stale source IDs after reflow (intentional)

On the first reflow commit, old high nameIDs are **copied** to their new 256+ positions and GSUB/GPOS are repointed. The **original** high slots are **not** deleted in that same pass — they were protected during pre-wipe so every platform/encoding record could be copied. They become inert duplicates until the **next** commit, when `classify_name_ids` marks them as orphans and pre-wipe removes them. TTX inspection right after a reflow may show duplicate-looking strings; a second save cleans them up.

---

## Export diff sheet (UI)

When applying project changes back to a variable font, show a **diff sheet** before commit:

- Present changes in a **TTX-familiar** view: which OpenType tables are touched and what data changes inside them.
- Goal: make export reviewable for users who already reason about fonts as `name`, `STAT`, `fvar`, `GSUB`/`GPOS`, etc.
- Diff should be driven by a real **write plan** (dry-run), not a hand-waved summary.

---

## Name table reflow — proposed approach (vs VarFlow-style)

VarFlow has an existing OpenType-feature preservation process. For VarFontStudio export, consider this alternative when **replacing `STAT` and `fvar`**:

### Principle

Because we are rebuilding `STAT` and `fvar`, treat their nameID references as disposable. **Redact first, preserve everything else, reflow, then rebuild.**

### Pipeline (draft)

1. **Redact STAT/fvar name IDs from `name`**
   - Remove name records that exist *only* to serve current `STAT` / `fvar` labels (axis names, axis value labels, instance subfamily strings, instance PostScript nameIDs where applicable).
   - Leave all **non–STAT/fvar** `name` data untouched (IDs 0–25, family/menu names, copyright, etc.).

2. **Cross-reference OpenType UI name links**
   - Scan `GSUB` / `GPOS` `FeatureParams` for label nameIDs (`FeatureNameID`, `UINameID`, `LabelNameID`, stylistic-set / character-variant parameter blocks, etc.).
   - Existing helper: `FontCore/core_ot_label_scanner.py` → `scan_ot_label_nameids()`.

3. **Reflow IDs below the rebuild band**
   - For nameIDs **&lt; 256** that are linked from OpenType features (and any other protected non–STAT/fvar consumers), **reflow starting at 256** so they do not collide with the rebuild.
   - Update all downstream table pointers (feature params, etc.) to the new IDs.
   - Related prior art: `FontCore/core_nameid_allocator.py` (`NameIDPlan.free_start = 256`) and `preserve_low_nameids_in_fvar_stat_*` in `core_ttx_table_io.py` / `core_name_policies.py`.

4. **Rebuild `STAT` labels**
   - Allocate fresh nameIDs from the free range for axis names and axis value labels per project naming policy.

5. **Rebuild `fvar` labels**
   - Allocate fresh nameIDs for instance subfamily / PostScript name strings.
   - Write instances from the edited project plan.

6. **Preserve high IDs where appropriate**
   - NameIDs **&gt; 255** that were previously linked only to old `STAT` / `fvar` can remain in the `name` table as inert strings if useful for audit/history, but **must not be re-linked** on rebuild (prune stale links; only new allocations wire into `STAT` / `fvar`).

### Why this may be better

- OpenType feature labels are the fragile part; they should be **identified and reflowed explicitly**, not accidentally overwritten during STAT/fvar replacement.
- Stripping STAT/fvar-owned names first avoids fighting the existing allocation graph.
- Rebuild order (`name` redact → OT reflow → `STAT` → `fvar`) matches dependency direction.

### Open questions (when implementing)

- Exact redaction set: derive from live `STAT`/`fvar` graph vs static ID threshold (cf. `preserve_low_nameids` threshold **17** in FontNameID tools).
- Whether inert high IDs should be **deleted** vs left orphaned for diff visibility.
- Binary vs TTX write path parity (`core_ttx_table_io.py` vs fontTools binary edits).
- How instance **PostScript** names interact with ID 6 / ID 25 and `NameIDPlan` postscript allocation.
- Diff sheet granularity: per-table XML hunks vs structured field-level rows.

---

## Related code (monorepo)

| Area | Location |
|------|----------|
| OT feature label scan | `FontCore/core_ot_label_scanner.py` |
| NameID audit / allocation plan | `FontCore/core_nameid_allocator.py` |
| STAT builder | `FontCore/core_stat_builder.py` |
| Low-ID preservation (current) | `FontCore/core_name_policies.py`, `core_ttx_table_io.py`, `FontNameID/NameID*Replacer.py` |
| Instance / axis planning (editor) | `VarFontEditor/Sources/VarFontCore/Plan/` |

---

*Recorded 2026-06-27 from editor UX / export planning discussion.*
