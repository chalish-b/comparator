#!/usr/bin/env bash
# Builds build/Comparator.app. With --install, also copies it to ~/Applications
# and registers it so it shows up in Finder's "Open With" menu.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=Comparator
APP="build/$APP_NAME.app"

# macOS picks the app's look (Liquid Glass or the older design) from the SDK
# version recorded in the binary. SwiftPM records the deployment target there,
# so pass the installed SDK's version to the linker explicitly.
MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
SDK_VERSION="$(xcrun --show-sdk-version)"
BUILD_FLAGS=(-c release -Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION")

xcrun swift build "${BUILD_FLAGS[@]}" --product "$APP_NAME"
BIN_DIR="$(xcrun swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/$APP_NAME.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  echo "Installed $DEST"
fi
