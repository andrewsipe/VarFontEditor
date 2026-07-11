#!/usr/bin/env bash
# Build a distributable VarFontStudio.app zip for GitHub Releases (no Xcode required for end users).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="VarFontStudio"
PROJECT="Apps/VarFontStudio/VarFontStudio.xcodeproj"
WORKSPACE="VarFontStudio.xcworkspace"
CONFIGURATION="Release"
DERIVED="$ROOT/build/ReleaseDerivedData"
PRODUCTS="$DERIVED/Build/Products/$CONFIGURATION"
APP="$PRODUCTS/VarFontStudio.app"
DIST="$ROOT/dist"

RUN_TESTS=1
if [[ "${1:-}" == "--skip-tests" ]]; then
  RUN_TESTS=0
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: xcodebuild not available — select full Xcode (not Command Line Tools only)" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if [[ $RUN_TESTS -eq 1 ]]; then
  echo "Running swift test…"
  swift test
fi

echo "Building $SCHEME ($CONFIGURATION)…"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"

build_with_project() {
  echo "Using project: $PROJECT"
  echo "Schemes in project:"
  xcodebuild -project "$PROJECT" -list
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=YES \
    build
}

build_with_workspace() {
  echo "Using workspace: $WORKSPACE"
  echo "Schemes in workspace:"
  xcodebuild -workspace "$WORKSPACE" -list
  xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=YES \
    build
}

if [[ -d "$PROJECT" ]]; then
  build_with_project
elif [[ -d "$WORKSPACE" ]]; then
  build_with_workspace
else
  echo "error: neither project ($PROJECT) nor workspace ($WORKSPACE) found" >&2
  exit 1
fi

if [[ ! -d "$APP" ]]; then
  echo "error: build succeeded but app not found at $APP" >&2
  exit 1
fi

"$ROOT/scripts/bundle-python-runtime.sh" "$APP"

echo "Re-signing app bundle…"
/usr/bin/codesign --force --deep --sign - --options runtime "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "0.0.0")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo "0")"
STAMP="$(date +%Y%m%d)"
ARCH="$(uname -m)"
ZIP_NAME="VarFontStudio-${VERSION}-b${BUILD}-${STAMP}-${ARCH}.zip"

mkdir -p "$DIST"
ZIP_PATH="$DIST/$ZIP_NAME"
rm -f "$ZIP_PATH"
ditto -c -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_PATH"

echo ""
echo "Release artifact: $ZIP_PATH"
echo "Upload this zip to GitHub Releases. Users unzip and drag VarFontStudio.app to Applications."
echo "First launch: if macOS blocks the app, right-click → Open (unsigned/ad-hoc build)."
