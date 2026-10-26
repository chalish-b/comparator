#!/usr/bin/env bash
# Builds build/ImgCompare.app. With --install, also copies it to ~/Applications
# and registers it so it shows up in Finder's "Open With" menu.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=ImgCompare
APP="build/$APP_NAME.app"

xcrun swift build -c release --product "$APP_NAME"
BIN_DIR="$(xcrun swift build -c release --show-bin-path)"

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
