#!/usr/bin/env bash
#
# build-mas.sh — build a signed installer package for the Mac App Store.
#
# Produces ClipTidy.pkg, signed and ready to upload to App Store Connect.
# Requires (all from the Apple Developer portal, one-time setup):
#   1. An app distribution cert: "Apple Distribution" or
#      "3rd Party Mac Developer Application", in your keychain.
#   2. An installer cert: "3rd Party Mac Developer Installer", in your keychain.
#   3. A "Mac App Store" provisioning profile for com.cliptidy.app, saved as
#      Resources/ClipTidy_MAS.provisionprofile (git-ignored) or passed via PROFILE=.
#
# The script auto-detects the certs and fails with guidance if they are missing,
# so it is safe to commit and run once the account setup is done.
#
# Override any of: ARCHS, APP_CERT, INSTALLER_CERT, PROFILE, OUTPUT_PKG.

set -euo pipefail
cd "$(dirname "$0")/.."

APP="ClipTidy"
BUNDLE="$APP.app"
ENTITLEMENTS="Resources/ClipTidy.entitlements"
INFO_PLIST="Resources/Info.plist"
ICON="Resources/AppIcon.icns"

: "${ARCHS:=arm64 x86_64}"                                   # universal by default
: "${PROFILE:=Resources/ClipTidy_MAS.provisionprofile}"
: "${OUTPUT_PKG:=$APP.pkg}"

APP_CERT="${APP_CERT:-$(security find-identity -v -p codesigning \
    | grep -oE '(Apple Distribution|3rd Party Mac Developer Application): [^"]*' | head -1 || true)}"
INSTALLER_CERT="${INSTALLER_CERT:-$(security find-identity -v \
    | grep -oE '3rd Party Mac Developer Installer: [^"]*' | head -1 || true)}"

fail() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$APP_CERT" ] || fail "No app distribution certificate found.
  Need 'Apple Distribution' or '3rd Party Mac Developer Application' in your keychain.
  Create it at developer.apple.com, then re-run (or set APP_CERT=...)."
[ -n "$INSTALLER_CERT" ] || fail "No installer certificate found.
  Need '3rd Party Mac Developer Installer' in your keychain.
  Create it at developer.apple.com, then re-run (or set INSTALLER_CERT=...)."
[ -f "$PROFILE" ] || fail "Provisioning profile not found at $PROFILE.
  Download the 'Mac App Store' profile for com.cliptidy.app and save it there
  (or set PROFILE=/path/to/profile.provisionprofile)."

echo "==> App cert:       $APP_CERT"
echo "==> Installer cert: $INSTALLER_CERT"
echo "==> Profile:        $PROFILE"
echo "==> Archs:          $ARCHS"

ARCH_FLAGS=""
for a in $ARCHS; do ARCH_FLAGS="$ARCH_FLAGS --arch $a"; done

echo "==> Building release"
swift build -c release $ARCH_FLAGS
BIN_DIR="$(swift build -c release $ARCH_FLAGS --show-bin-path)"

echo "==> Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/$APP" "$BUNDLE/Contents/MacOS/$APP"
cp "$INFO_PLIST" "$BUNDLE/Contents/Info.plist"
cp "$ICON" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$PROFILE" "$BUNDLE/Contents/embedded.provisionprofile"

echo "==> Signing app"
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$APP_CERT" \
    "$BUNDLE"
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

echo "==> Building signed installer -> $OUTPUT_PKG"
productbuild --component "$BUNDLE" /Applications \
    --sign "$INSTALLER_CERT" \
    "$OUTPUT_PKG"

echo ""
echo "Built $OUTPUT_PKG, signed and ready for App Store Connect."
echo "Upload with the Transporter app, or:"
echo "  xcrun altool --upload-app -f \"$OUTPUT_PKG\" -t macos \\"
echo "      -u <apple-id> -p <app-specific-password>"
