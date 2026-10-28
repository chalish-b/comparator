#!/usr/bin/env bash
# Builds build/Comparator Dev.app, or build/Comparator.app with --release. With
# --install, also copies it to ~/Applications and registers it so it shows up in
# Finder's "Open With" menu.
#
# The dev build has its own name and bundle identifier, so it can be installed
# and run alongside the released app and keeps separate settings.
set -euo pipefail
cd "$(dirname "$0")/.."

RELEASE=false
INSTALL=false
for ARG in "$@"; do
  case "$ARG" in
    --release) RELEASE=true ;;
    --install) INSTALL=true ;;
    *) echo "usage: scripts/build-app.sh [--release] [--install]" >&2; exit 1 ;;
  esac
done

APP_NAME=Comparator
if $RELEASE; then
  DISPLAY_NAME="$APP_NAME"
else
  DISPLAY_NAME="$APP_NAME Dev"
fi
APP="build/$DISPLAY_NAME.app"

# macOS picks the app's look (Liquid Glass or the older design) from the SDK
# version recorded in the binary. SwiftPM records the deployment target there,
# so pass the installed SDK's version to the linker explicitly.
# The binary is universal (Apple silicon and Intel).
MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
SDK_VERSION="$(xcrun --show-sdk-version)"
BUILD_FLAGS=(-c release --arch arm64 --arch x86_64 -Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION")

xcrun swift build "${BUILD_FLAGS[@]}" --product "$APP_NAME"
BIN_DIR="$(xcrun swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The compiled icon is committed; scripts/compile-icon.sh regenerates it.
cp Resources/AppIcon/* "$APP/Contents/Resources/"
if ! $RELEASE; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier $BUNDLE_ID.dev" \
    -c "Set :CFBundleName $DISPLAY_NAME" \
    -c "Set :CFBundleDisplayName $DISPLAY_NAME" \
    "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP"
echo "Built $APP"

if $INSTALL; then
  DEST="$HOME/Applications/$DISPLAY_NAME.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  echo "Installed $DEST"
fi
