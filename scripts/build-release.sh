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
  echo "Resolving Swift package dependencies…"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED" \
    -resolvePackageDependencies
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
  echo "Resolving Swift package dependencies…"
  xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED" \
    -resolvePackageDependencies
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
# Keep in sync with MACOSX_DEPLOYMENT_TARGET / Info.plist LSMinimumSystemVersion (14.0).
MACOS_LABEL="macOS14+"
case "$(uname -m)" in
  arm64) ARCH_LABEL="Apple-Silicon" ;;
  x86_64) ARCH_LABEL="Intel" ;;
  *) ARCH_LABEL="$(uname -m)" ;;
esac
FOLDER_NAME="VarFontStudio-${VERSION}-${MACOS_LABEL}-${ARCH_LABEL}"
ZIP_NAME="${FOLDER_NAME}.zip"

mkdir -p "$DIST"
STAGE="$DIST/$FOLDER_NAME"
rm -rf "$STAGE" 2>/dev/null || true
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/VarFontStudio.app"
cp "$ROOT/packaging/Allow First Launch.command" "$STAGE/Allow First Launch.command"
chmod +x "$STAGE/Allow First Launch.command"
cp "$ROOT/packaging/INSTALL.txt" "$STAGE/INSTALL.txt"

ZIP_PATH="$DIST/$ZIP_NAME"
rm -f "$ZIP_PATH"
# Folder wrapper so the helper ships beside the app (not a bare .app zip).
(cd "$DIST" && ditto -c -k --norsrc --keepParent "$FOLDER_NAME" "$ZIP_NAME")
rm -rf "$STAGE" 2>/dev/null || chmod -R u+w "$STAGE" 2>/dev/null || true
rm -rf "$STAGE" 2>/dev/null || true

echo ""
echo "Release artifact: $ZIP_PATH"
echo "Contents: VarFontStudio.app + Allow First Launch.command + INSTALL.txt"
echo "Users: drag app to Applications, then double-click Allow First Launch (clears quarantine)."
