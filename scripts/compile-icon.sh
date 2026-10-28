#!/usr/bin/env bash
# Compiles Resources/AppIcon.icon into Resources/AppIcon/: Assets.car, plus
# AppIcon.icns for older macOS versions. Also renders the light and dark PNGs
# shown in the README. Run this after editing the icon in Icon Composer and
# commit the result. Requires Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
OUT=Resources/AppIcon

rm -rf "$OUT"
mkdir -p "$OUT"
xcrun actool Resources/AppIcon.icon --compile "$OUT" \
  --app-icon AppIcon --platform macosx --target-device mac \
  --minimum-deployment-target "$MIN_MACOS" \
  --output-partial-info-plist "$(mktemp)" --output-format human-readable-text >/dev/null
echo "Compiled $OUT"

ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
for RENDITION in Default:light Dark:dark; do
  PNG="docs/icon-${RENDITION#*:}.png"
  "$ICTOOL" Resources/AppIcon.icon --export-image --output-file "$PNG" \
    --platform macOS --rendition "${RENDITION%%:*}" --width 128 --height 128 --scale 2 >/dev/null
  echo "Rendered $PNG"
done
