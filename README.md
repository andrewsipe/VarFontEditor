# VarFont Studio (alpha)

**VarFont Studio** is a macOS app for planning and writing **variable font instances** — the combinations of weight, width, optical size, and other axes that show up in design apps and in your font’s `STAT`, `fvar`, and `name` tables.

You define axis stops, generate the instance grid, tune naming, preview what will change, then save a patched copy of your font. No glyph editing; no raw TTX browser.

---

## Install (no Xcode required)

Pre-built apps are on **[GitHub Releases](https://github.com/andrewsipe/VarFontEditor/releases)**.

### 1. Pick the right download

Each release attaches **two** zip files. The filename ends with the CPU type:

| Suffix | Mac |
|--------|-----|
| **`arm64`** | Apple Silicon (M1, M2, M3, …) |
| **`x86_64`** | Intel |

**Apple menu → About This Mac → Chip or Processor** tells you which you need.

The app UI is a Universal binary, but **Save** uses a bundled Python runtime that is **native to the zip you downloaded**. An `arm64` zip on an Intel Mac will open fine until you try to Save — download the matching zip instead.

**Requires macOS 14 (Sonoma) or later.**

### 2. Unzip and move to Applications

1. Download the zip for your Mac.
2. Double-click to unzip.
3. Drag **VarFont Studio.app** into **Applications**.

### 3. First launch — “unidentified developer” is expected

Alpha builds are **not** signed for the Mac App Store and **not** notarized. macOS Gatekeeper will often block a double-click on first open. **This is normal, not malware.**

Do this **once**:

1. Open **Finder → Applications**.
2. **Control-click** (or right-click) **VarFont Studio.app**.
3. Choose **Open** from the menu.
4. In the dialog, click **Open** again (not Cancel).

After that, you can launch it like any other app. If you only double-click the first time, macOS may refuse silently or show a vague security message — use **right-click → Open**.

### 4. Open a font and work

- **File → Open Font…** (⌘O) — start a new project from a variable font.
- **File → Open Project…** (⌘⌥O) — reopen a saved `.varf` project.
- Edit axis stops and instance inclusion, then **File → Open Save Review Window** (⌘⇧R) before writing.
- **Help → VarFont Studio Shortcuts…** lists keyboard shortcuts.

Save writes a **patched copy** next to your source file unless you choose another path. Python and fontTools are **bundled inside the app** — nothing extra to install.

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
# output: dist/VarFontStudio-<version>-<date>-<arch>.zip
```

**Publish via GitHub:** push a tag — CI builds **both** arm64 and x86_64 zips and attaches them to the Release.

```bash
git tag v0.1.0-alpha
git push origin v0.1.0-alpha
```

---

## Alpha scope

- Instance modeling, naming, STAT/fvar commit via bundled **vfcommit**
- Optional **OpenType feature label reflow** (Preferences menu + Save review)
- Project files: **`.varf`** (legacy `.varfont` still opens)
- Notarized / Developer ID distribution: not yet — use right-click → Open on first launch
