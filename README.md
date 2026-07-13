# VarFont Studio (alpha)

**Requires macOS 14 (Sonoma) or later** · Apple Silicon or Intel

**VarFont Studio** is a macOS app for planning and writing **variable font instances** — the combinations of weight, width, optical size, and other axes that show up in design apps and in your font’s `STAT`, `fvar`, and `name` tables.

You define axis stops, generate the instance grid, tune naming, preview what will change in **Review**, then **Export** a patched copy of your font. **Save** keeps your `.varf` project. No glyph editing; no raw TTX browser.

---

## Install (no Xcode required)

Pre-built apps are on **[GitHub Releases](https://github.com/andrewsipe/VarFontEditor/releases)**.

### Requirements

| | |
|--|--|
| **macOS** | **14 (Sonoma) or later** |
| **Chip** | Apple Silicon **or** Intel (download the matching zip) |

### 1. Pick the right download

Each release attaches **two** zip files. Names look like:

| Filename | Mac |
|----------|-----|
| **`…-macOS14+-Apple-Silicon.zip`** | Apple Silicon (M1, M2, M3, …) |
| **`…-macOS14+-Intel.zip`** | Intel |

**Apple menu → About This Mac** shows both your macOS version and Chip / Processor.

The app UI is a Universal binary, but **Export** uses a bundled Python runtime that is **native to the zip you downloaded**. An Apple Silicon zip on an Intel Mac will open fine until you try to Export — download the matching zip instead.

### 2. Unzip and move to Applications

1. Download the zip for your Mac.
2. Double-click to unzip.
3. Drag **VarFont Studio.app** into **Applications**.

### 3. First launch — “Not Opened” / unidentified developer is expected

Alpha builds are **not** notarized. On recent macOS, double-click often shows **“VarFontStudio.app” Not Opened** with only **Done** / **Move to Trash**. **This is normal, not malware.**

**Option A — System Settings (usual path on macOS 15):**

1. Click **Done** on the alert (do **not** Move to Trash).
2. Open **System Settings → Privacy & Security**.
3. Scroll to the message that **VarFont Studio** was blocked.
4. Click **Open Anyway**, then confirm **Open**.

**Option B — Finder:**

1. Open **Finder → Applications**.
2. **Control-click** (right-click) **VarFont Studio.app** → **Open**.
3. If macOS still blocks it, use Option A.

**Option C — Terminal (if A/B fail):**

```bash
xattr -cr /Applications/VarFontStudio.app
open /Applications/VarFontStudio.app
```

That removes the download quarantine flag so Gatekeeper stops blocking the ad-hoc build.

### 4. Open a font or project and work

- **Drop** fonts or `.varf` projects onto the empty window (or **File → Open Font…** / **Open Project…**).
- **⌘S** — **Save Project** (writes `.varf`).
- **⌘E** — **Export…** (writes patched font binaries; default name uses `-patched` beside the source).
- **Export All…** (multi-file projects) — folder of fonts keeping original filenames.
- **⌘⇧R** — **Review** before exporting.
- **Help → VarFont Studio Shortcuts…** lists keyboard shortcuts.

Quit only prompts when a **project file** has unsaved changes — unexported font edits do not block exit.

Python and fontTools are **bundled inside the app** — nothing extra to install.

---

## For developers

Swift package + Xcode app live in this repo.

| Doc | Contents |
|-----|----------|
| [SCHEMA.md](SCHEMA.md) | JSON schema v1 |
| [archive/](archive/) | Prototypes, handoff notes, design history (not needed to build) |

**Run from source:** open `VarFontStudio.xcworkspace` → scheme **VarFontStudio** → My Mac (⌘R).

**Tests:** `swift test`

**Build a release zip locally** (uses your Mac’s native Python arch):

```bash
chmod +x scripts/build-release.sh scripts/bundle-python-runtime.sh
./scripts/build-release.sh
# output: dist/VarFontStudio-<version>-macOS14+-Apple-Silicon.zip  (or -Intel.zip)
```

**Publish via GitHub:** push a tag — CI builds **both** Apple Silicon and Intel zips and attaches them to the Release.

```bash
git tag v0.1.1-alpha
git push origin v0.1.1-alpha
```

---

## Alpha scope

- Instance modeling, naming, STAT/fvar commit via bundled **vfcommit**
- **Save** = project (`.varf`); **Export** = patched fonts; **Review** = preflight diff
- Optional **OpenType feature label reflow** (Preferences menu + Review tab bar)
- Drag/drop fonts and **`.varf`** projects (legacy `.varfont` still opens)
- Notarized / Developer ID distribution: not yet — use right-click → Open on first launch
