#!/usr/bin/env bash
# Renders the README screenshots, docs/screenshot-light.webp and docs/screenshot-dark.webp.
# Builds and installs the dev app, opens the images in test-images in a fixed window
# and view, captures the window in light and dark appearance, and converts the captures to
# lossless WebP. The dev app's settings are restored afterwards.
#
# test-images/ is gitignored; put the images listed in FILES there first. Requires a 2x
# display, cwebp (brew install webp), and Screen Recording permission for the terminal.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGES=test-images
FILES=(base.png upscaled.png upscale-2.png clean.png)
VIEW=(--split --pixels --show 1,2 --pin 1 --zoom 481 --center 0.2378,0.0805)
WINDOW_WIDTH=1200
WINDOW_HEIGHT=750
SIDEBAR_WIDTH=317
INFO_HEIGHT=320

APP="$HOME/Applications/Comparator Dev.app"
EXECUTABLE="$APP/Contents/MacOS/Comparator"
DOMAIN=dev.chalish.Comparator.dev
TOOLS=build/screenshot-tools

for FILE in "${FILES[@]}"; do
  [[ -f "$IMAGES/$FILE" ]] || { echo "Missing $IMAGES/$FILE" >&2; exit 1; }
done
command -v cwebp >/dev/null || { echo "cwebp not found; install it with: brew install webp" >&2; exit 1; }

./scripts/build-app.sh --install
xcrun swiftc -O scripts/screenshot-tools.swift -o "$TOOLS"
[[ "$("$TOOLS" scale)" == 2 ]] || { echo "The main display must be at 2x (HiDPI)" >&2; exit 1; }

app_pid() {
  pgrep -f "^$EXECUTABLE" | head -1 || true
}

quit_app() {
  if [[ -n "$(app_pid)" ]]; then
    osascript -e "tell application id \"$DOMAIN\" to quit"
    while [[ -n "$(app_pid)" ]]; do sleep 0.1; done
  fi
}

TMP="$(mktemp -d)"
quit_app
HAD_SETTINGS=false
if defaults export "$DOMAIN" "$TMP/settings.plist" 2>/dev/null; then HAD_SETTINGS=true; fi

restore_settings() {
  quit_app
  if $HAD_SETTINGS; then
    defaults delete "$DOMAIN" 2>/dev/null || true
    defaults import "$DOMAIN" "$TMP/settings.plist"
  else
    defaults delete "$DOMAIN" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap restore_settings EXIT

CANVAS_WIDTH=$((WINDOW_WIDTH - SIDEBAR_WIDTH))
defaults write "$DOMAIN" "NSWindow Frame ComparisonWindow" "200 200 $WINDOW_WIDTH $WINDOW_HEIGHT"
defaults write "$DOMAIN" "NSSplitView Subview Frames SidebarWidth" -array \
  "0.000000, 0.000000, $SIDEBAR_WIDTH.000000, $WINDOW_HEIGHT.000000, NO, NO" \
  "$SIDEBAR_WIDTH.000000, 0.000000, $CANVAS_WIDTH.000000, $WINDOW_HEIGHT.000000, NO, NO"
defaults write "$DOMAIN" infoExpanded -bool YES
defaults write "$DOMAIN" infoHeight -float "$INFO_HEIGHT"

PATHS=()
for FILE in "${FILES[@]}"; do PATHS+=("$PWD/$IMAGES/$FILE"); done

for APPEARANCE in light dark; do
  if [[ $APPEARANCE == dark ]]; then
    defaults delete "$DOMAIN" NSRequiresAquaSystemAppearance 2>/dev/null || true
    defaults write "$DOMAIN" AppleInterfaceStyle Dark
  else
    defaults delete "$DOMAIN" AppleInterfaceStyle 2>/dev/null || true
    defaults write "$DOMAIN" NSRequiresAquaSystemAppearance -bool YES
  fi

  "$EXECUTABLE" "${PATHS[@]}" "${VIEW[@]}"
  WINDOW=""
  for _ in $(seq 100); do
    PID="$(app_pid)"
    if [[ -n "$PID" ]] && WINDOW="$("$TOOLS" window "$PID")"; then break; fi
    sleep 0.1
  done
  [[ -n "$WINDOW" ]] || { echo "The app's window didn't appear" >&2; exit 1; }
  # Let the images load and the window settle.
  sleep 2

  screencapture -x -l "$WINDOW" "$TMP/$APPEARANCE.png"
  cwebp -quiet -lossless -z 9 "$TMP/$APPEARANCE.png" -o "docs/screenshot-$APPEARANCE.webp"
  echo "Wrote docs/screenshot-$APPEARANCE.webp"
  quit_app
done
