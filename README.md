# VarFont Studio (alpha)

A macOS app for building out variable font instances — the different weights, widths, and styles that show up in your design apps as separate entries in the font menu (Light, Bold, Condensed, and so on).

If you've ever opened a variable font in a font editor's raw table view and felt your eyes glaze over, this is meant to be the friendlier way in. You set up your axis stops (say, Weight from 100 to 900), VarFont Studio generates the full grid of instances, you tweak the naming until it looks right, preview exactly what's about to change, and then export a patched copy of your font. It's not a glyph editor and it won't crack open raw TTX for you — it's focused specifically on getting your instances and naming right.

**Requires:** macOS 14 (Sonoma) or later, on Apple Silicon or Intel.

---

## Installing it

Grab the latest zip from **[GitHub Releases](https://github.com/andrewsipe/VarFontStudio/releases)** — there are two to choose from, one for Apple Silicon Macs (M1/M2/M3/etc.) and one for Intel. If you're not sure which you have, check **Apple menu → About This Mac**. Downloading the wrong one won't break anything obvious — the app opens fine either way — but exporting fonts won't work, so it's worth grabbing the right one.

Once you've got the zip:

1. Unzip it and drag **VarFontStudio.app** into your **Applications** folder.
2. Double-click **Allow First Launch**, also in that unzipped folder.

That second step matters because this is an alpha build and isn't notarized by Apple yet — macOS's Gatekeeper doesn't know who made it, so it needs a nudge before it'll open. The helper just clears the download's quarantine flag; it's not doing anything sneaky, and you can read exactly what it runs if you're curious.

If macOS still won't let it open, the easiest fallback is **System Settings → Privacy & Security**, scroll down to where it mentions VarFont Studio was blocked, and click **Open Anyway**. That almost always does it.

Python and the font tools it needs are bundled inside the app, so there's nothing else to install.

---

## Using it

Open a font (or a saved `.varf` project) by dragging it onto the window, or through **File → Open**. From there:

- Set up your axis stops and let the app build out the instance grid
- Adjust naming until it reads the way you want — including the Axis Tree **pencil** to rename an axis’s display label (STAT + fvar) without changing the 4-character tag
- Hit **Review** (⌘⇧R) for a before/after of STAT, fvar, and name-table slots (with a dedicated nameID column). Windows English names (0–25) list every populated record, including unchanged ones
- **Export** (⌘E) to write out patched font files
- **Save** (⌘S) to keep your project as a `.varf` file so you can pick it back up later

Working across multiple font files in one project? **Export All** writes everything out at once, keeping the original filenames.

One nice detail: quitting only prompts you if you have *unsaved project changes* — if you've tweaked a font but haven't exported yet, that won't hold up your exit.

Check **Help → VarFont Studio Shortcuts** in the app for the full list of keyboard shortcuts.

---

## Building it from source

The Swift package and Xcode project both live in this repo. Open `VarFontStudio.xcworkspace`, pick the **VarFontStudio** scheme, and run (⌘R).

Tests: `swift test` for the Swift side, `cd Tools/vfcommit && python3 -m pytest tests -q` for the Python side.

If you want to know more about the JSON project format, [SCHEMA.md](SCHEMA.md) has the details. `archive/` has old prototypes and design notes if you're curious about how this came together, but you won't need it to build the app.

---

## Where things stand

This is an alpha (**0.1.5**). The core workflow — modeling instances, **naming axes** (file identity + optional classification codes), inline axis display-name edits, Review, and writing STAT/fvar/name changes back into the font — works and is what I've been focused on getting right. Signed/notarized distribution isn't set up yet, which is why you're using the "Allow First Launch" workaround above for now.
