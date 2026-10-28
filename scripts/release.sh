#!/usr/bin/env bash
# Usage: scripts/release.sh <version>
# Builds build/Comparator-<version>.dmg and, after confirmation, publishes it as
# the GitHub release v<version> at the current commit.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
TAG="v$VERSION"
APP_NAME=Comparator
APP="build/$APP_NAME.app"
DMG="build/$APP_NAME-$VERSION.dmg"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree has uncommitted changes." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Tag $TAG already exists." >&2
  exit 1
fi

scripts/build-app.sh --release

# The git tag is the version's source of truth; stamp it into the built app.
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion $VERSION" \
  "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

# The disk image shows the app next to a shortcut to /Applications.
rm -f "$DMG"
uvx dmgbuild -s scripts/dmg-settings.py -D app="$APP" "$APP_NAME" "$DMG"
echo "Built $DMG"

read -r -p "Publish $TAG to GitHub? [y/N] " REPLY
if [[ "$REPLY" != [yY] ]]; then
  exit 0
fi

NOTES="Install: download the DMG below and drag Comparator into Applications. macOS blocks the first launch because the app isn't signed with an Apple developer certificate — see [Install](https://github.com/chalish-b/comparator#install) for how to allow it."

git push origin HEAD
gh release create "$TAG" "$DMG" --target "$(git rev-parse HEAD)" --title "$APP_NAME $VERSION" --notes "$NOTES" --generate-notes
