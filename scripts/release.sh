#!/usr/bin/env bash
#
# release.sh — build a downloadable ClipTidy.dmg and publish it to GitHub Releases.
#
# ClipTidy ships from GitHub, not the App Store. This builds a universal,
# ad-hoc signed app, wraps it in a drag-to-Applications disk image, and (by
# default) publishes it as a release so anyone can download and run it.
#
# Usage:
#   ./scripts/release.sh              # build ClipTidy.dmg and publish a release
#   ./scripts/release.sh --no-publish # just build ClipTidy.dmg locally
#
# The version comes from CFBundleShortVersionString in Info.plist (tag "vX.Y"),
# so cutting a new release is: bump the version in Info.plist, run this.

set -euo pipefail
cd "$(dirname "$0")/.."

APP="ClipTidy"
BUNDLE="$APP.app"
ICON="Resources/AppIcon.icns"
INFO_PLIST="Resources/Info.plist"
DMG="$APP.dmg"

PUBLISH=1
[ "${1:-}" = "--no-publish" ] && PUBLISH=0

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
TAG="v$SHORT_VERSION"

echo "==> Building universal release (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "==> Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/$APP" "$BUNDLE/Contents/MacOS/$APP"
cp "$INFO_PLIST" "$BUNDLE/Contents/Info.plist"
cp "$ICON" "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing (so it runs; not notarized)"
codesign --force --sign - "$BUNDLE"

echo "==> Building $DMG"
STAGE="$(mktemp -d)"
cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "    built $DMG"

if [ "$PUBLISH" -eq 0 ]; then
    echo "Done (local only). Open $DMG and drag $APP to Applications to test."
    exit 0
fi

echo "==> Publishing GitHub release $TAG"
NOTES="Download **$DMG** below, open it, and drag ClipTidy to Applications.

First launch: right-click ClipTidy and choose **Open** (the app is not notarized, so macOS asks once). A wand icon then lives in your menu bar.

See the [README](https://github.com/denseymour/cliptidy#readme) for what it does and the keyboard shortcuts."

gh release create "$TAG" "$DMG" \
    --title "ClipTidy $SHORT_VERSION" \
    --notes "$NOTES"

echo "Published $TAG."
