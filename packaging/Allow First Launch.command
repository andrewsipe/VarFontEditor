#!/bin/bash
# Clears the download quarantine flag so Gatekeeper allows this ad-hoc alpha build.
# Double-click after dragging VarFontStudio.app to Applications.
# If macOS blocks this script too: Control-click → Open, or drag this file into Terminal.
set -euo pipefail

clear 2>/dev/null || true
echo "========================================"
echo "  VarFont Studio — Allow First Launch"
echo "========================================"
echo ""
echo "This helper is from the official GitHub release zip."
echo "Alpha builds are not Apple-notarized yet, so macOS"
echo "blocks a normal double-click. This script only:"
echo ""
echo "  1. Removes the download quarantine flag (xattr)"
echo "  2. Opens VarFont Studio"
echo ""
echo "It does not modify your fonts or install software."
echo ""

cd "$(dirname "$0")"
HERE="$(pwd -P)"

if [[ -d "/Applications/VarFontStudio.app" ]]; then
  APP="/Applications/VarFontStudio.app"
  echo "Found app: /Applications/VarFontStudio.app"
elif [[ -d "$HERE/VarFontStudio.app" ]]; then
  APP="$HERE/VarFontStudio.app"
  echo "Found app next to this helper:"
  echo "  $APP"
  echo "(Tip: drag it into Applications for a normal install.)"
else
  echo "ERROR: VarFontStudio.app not found."
  echo ""
  echo "Drag VarFontStudio.app into Applications, then run"
  echo "this helper again (double-click, or drag into Terminal)."
  echo ""
  osascript <<'EOF' >/dev/null 2>&1 || true
display alert "VarFont Studio not found" message "Drag VarFontStudio.app into the Applications folder, then run “Allow First Launch” again." as critical
EOF
  echo "Press Return to close…"
  read -r _
  exit 1
fi

echo ""
echo "Clearing quarantine on:"
echo "  $APP"
if /usr/bin/xattr -cr "$APP" 2>/dev/null; then
  echo "Done — quarantine attribute removed."
else
  echo "Note: xattr reported a warning (often fine if already clear)."
fi

echo ""
echo "Opening VarFont Studio…"
open "$APP"
echo "Launched."
echo ""
echo "You can close this Terminal window."
echo "Press Return to close…"
read -r _
