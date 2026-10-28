#!/usr/bin/env bash
# Compiles Resources/AppIcon.icon into Resources/AppIcon/: Assets.car, plus
# AppIcon.icns for older macOS versions. Run this after editing the icon in Icon
# Composer and commit the result. Requires Xcode.
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
