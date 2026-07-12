#!/usr/bin/env bash
# Copy a relocatable Python venv (with fontTools) into VarFontStudio.app/Contents/Resources/python
set -euo pipefail

APP_PATH="${1:?Usage: bundle-python-runtime.sh /path/to/VarFontStudio.app}"

if [[ ! -d "$APP_PATH/Contents" ]]; then
  echo "error: not an app bundle: $APP_PATH" >&2
  exit 1
fi

RESOURCES="$APP_PATH/Contents/Resources"
PYTHON_DST="$RESOURCES/python"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/varfont-python.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQ="$ROOT/Tools/vfcommit/requirements.txt"

echo "Creating Python runtime in $PYTHON_DST"
python3 -m venv --copies "$WORKDIR/venv"
export PIP_USER=0
"$WORKDIR/venv/bin/pip" install --upgrade pip wheel
"$WORKDIR/venv/bin/pip" install -r "$REQ"

rm -rf "$PYTHON_DST"
cp -R "$WORKDIR/venv" "$PYTHON_DST"

# Drop caches.
find "$PYTHON_DST" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

# Python 3.14+ venv may include a Unicode joke binary named "𝜋thon". That name
# trips encoding prompts in The Unarchiver / some unzip tools. Keep only ASCII
# names in bin/, and trim shell activation helpers we never invoke.
BIN="$PYTHON_DST/bin"
if [[ -d "$BIN" ]]; then
  python3 - <<'PY' "$BIN"
import os, sys
bin_dir = sys.argv[1]
keep_prefixes = ("python", "pip", "fonttools", "pyft", "ttx", "wheel")
for name in os.listdir(bin_dir):
    path = os.path.join(bin_dir, name)
    if name.startswith("activate") or name == "Activate.ps1":
        os.remove(path)
        print(f"removed helper {name}")
        continue
    if not name.isascii():
        os.remove(path)
        print(f"removed non-ASCII bin entry {name!r}")
        continue
    if not name.startswith(keep_prefixes):
        # Leave unknown ASCII tools alone; vfcommit only needs python3.
        pass
PY
fi

if [[ ! -x "$PYTHON_DST/bin/python3" ]]; then
  echo "error: bundled python3 missing after sanitize" >&2
  exit 1
fi

"$PYTHON_DST/bin/python3" -c "import fontTools; print('Bundled fontTools', fontTools.__version__)"
