#!/bin/bash
# Clears the download quarantine flag so Gatekeeper allows this ad-hoc alpha build.
# Double-click after dragging VarFontStudio.app to Applications.
# If macOS blocks this script too: Control-click → Open.
set -euo pipefail

cd "$(dirname "$0")"
HERE="$(pwd -P)"

if [[ -d "/Applications/VarFontStudio.app" ]]; then
  APP="/Applications/VarFontStudio.app"
elif [[ -d "$HERE/VarFontStudio.app" ]]; then
  APP="$HERE/VarFontStudio.app"
else
  osascript <<'EOF' >/dev/null
display alert "VarFont Studio not found" message "Drag VarFontStudio.app into the Applications folder, then double-click “Allow First Launch” again." as critical
EOF
  exit 1
fi

/usr/bin/xattr -cr "$APP" 2>/dev/null || true
open "$APP"
